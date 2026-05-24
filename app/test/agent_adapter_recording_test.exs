defmodule Wardwright.AgentAdapterRecordingTest do
  use Wardwright.RouterCase

  alias Wardwright.AgentAdapters.Identity

  @secret String.duplicate("adapter-secret", 4)
  @now ~U[2026-05-23 22:00:00Z]
  @workspace_fingerprint Identity.workspace_fingerprint("/tmp/wardwright-project")

  setup do
    previous_secret = Application.get_env(:wardwright, :adapter_identity_secret)
    previous_workspace_fingerprint = Application.get_env(:wardwright, :adapter_workspace_fingerprint)
    Application.put_env(:wardwright, :adapter_identity_secret, @secret)
    Application.put_env(:wardwright, :adapter_workspace_fingerprint, @workspace_fingerprint)

    on_exit(fn ->
      if is_nil(previous_secret),
        do: Application.delete_env(:wardwright, :adapter_identity_secret),
        else: Application.put_env(:wardwright, :adapter_identity_secret, previous_secret)

      if is_nil(previous_workspace_fingerprint),
        do: Application.delete_env(:wardwright, :adapter_workspace_fingerprint),
        else: Application.put_env(:wardwright, :adapter_workspace_fingerprint, previous_workspace_fingerprint)
    end)

    :ok
  end

  test "generic clients stay metadata-only when adapted agents auto-record" do
    assert call(:post, "/__test/config", recording_config()).status == 200

    conn = chat("generic-session")

    assert conn.status == 200
    receipt = response_receipt(conn)
    assert get_in(receipt, ["vcr", "mode"]) == "metadata_only"
    refute get_in(receipt, ["vcr", "full_session"])
    refute get_in(receipt, ["caller", "adapter"])
  end

  test "verified adapter identity enables full-session recording and stores sanitized adapter trace metadata" do
    assert call(:post, "/__test/config", recording_config()).status == 200

    headers = [
      {"x-wardwright-adapter-identity", JSON.encode!(paired_identity())},
      {"x-wardwright-workspace-fingerprint", @workspace_fingerprint}
    ]

    conn = chat("adapter-session", headers)

    assert conn.status == 200
    receipt = response_receipt(conn)
    assert get_in(receipt, ["vcr", "mode"]) == "full_session"

    assert get_in(receipt, ["vcr", "full_session", "request", "body", "messages", Access.at(0), "content"]) ==
             "adapter recording fixture"

    assert get_in(receipt, ["caller", "adapter", "adapter_id"]) == "wardwright-omp"
    assert get_in(receipt, ["caller", "adapter", "runtime"]) == "omp"
    assert get_in(receipt, ["caller", "adapter", "target"]) == "omp"
    assert get_in(receipt, ["caller", "adapter", "verification_state"]) == "verified"
    assert get_in(receipt, ["caller", "adapter", "recording_mode"]) == "auto"
    refute JSON.encode!(receipt) =~ paired_identity()["token"]
  end

  test "verified Claude Code identity uses adapter-scoped recording without native resume claims" do
    assert call(:post, "/__test/config", recording_config()).status == 200

    identity =
      paired_identity(%{
        "adapter_id" => "wardwright-claude-code",
        "runtime" => "claude-cli",
        "target" => "claude-code"
      })

    headers = [
      {"x-wardwright-adapter-identity", JSON.encode!(identity)},
      {"x-wardwright-workspace-fingerprint", @workspace_fingerprint}
    ]

    conn = chat("claude-adapter-session", headers)

    assert conn.status == 200
    receipt = response_receipt(conn)
    assert get_in(receipt, ["vcr", "mode"]) == "full_session"
    assert get_in(receipt, ["caller", "adapter", "adapter_id"]) == "wardwright-claude-code"
    assert get_in(receipt, ["caller", "adapter", "runtime"]) == "claude-cli"
    assert get_in(receipt, ["caller", "adapter", "target"]) == "claude-code"
    assert get_in(receipt, ["caller", "adapter", "verification_state"]) == "verified"
    refute JSON.encode!(receipt) =~ identity["token"]
  end

  test "declared but unverified adapters do not receive adapted-agent auto recording" do
    assert call(:post, "/__test/config", recording_config()).status == 200

    conn =
      chat("declared-adapter-session", [
        {"x-wardwright-adapter-id", "wardwright-omp"},
        {"x-wardwright-adapter-runtime", "omp"},
        {"x-wardwright-adapter-target", "omp"}
      ])

    assert conn.status == 200
    receipt = response_receipt(conn)
    assert get_in(receipt, ["vcr", "mode"]) == "metadata_only"
    assert get_in(receipt, ["caller", "adapter", "verification_state"]) == "installed_unverified"
    assert get_in(receipt, ["caller", "adapter", "recording_mode"]) == "manual"
  end

  test "wrong-workspace and expired adapter identities are rejected before recording" do
    assert call(:post, "/__test/config", recording_config()).status == 200
    other_workspace = Identity.workspace_fingerprint("/tmp/other-project")

    wrong_workspace =
      chat("wrong-workspace-session", [
        {"x-wardwright-adapter-identity", JSON.encode!(paired_identity(%{"workspace_fingerprint" => other_workspace}))},
        {"x-wardwright-workspace-fingerprint", other_workspace}
      ])

    assert wrong_workspace.status == 403
    assert get_in(JSON.decode!(wrong_workspace.resp_body), ["error", "code"]) == "adapter_identity_wrong_workspace"

    expired =
      chat("expired-session", [
        {"x-wardwright-adapter-identity",
         JSON.encode!(paired_identity(%{}, now: ~U[2020-01-01 00:00:00Z], ttl_seconds: 1))},
        {"x-wardwright-workspace-fingerprint", @workspace_fingerprint}
      ])

    assert expired.status == 401
    assert get_in(JSON.decode!(expired.resp_body), ["error", "code"]) == "adapter_identity_expired"
  end

  test "explicit recording header still enables full-session recording for generic clients" do
    assert call(:post, "/__test/config", recording_config()).status == 200

    conn = chat("explicit-generic-session", [{"x-wardwright-recording", "auto"}])

    assert conn.status == 200
    receipt = response_receipt(conn)
    assert get_in(receipt, ["vcr", "mode"]) == "full_session"

    assert get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "session_id"]) ==
             "explicit-generic-session"

    refute get_in(receipt, ["caller", "adapter"])
  end

  defp recording_config do
    unit_policy_config()
    |> Map.put("recording", %{"adapted_agents" => "auto", "default" => "manual", "generic_clients" => "manual"})
    |> Map.put("targets", [
      %{"canned_outputs" => ["adapter recording response"], "context_window" => 256, "model" => "canned/model"}
    ])
  end

  defp chat(session_id, headers \\ []) do
    call(
      :post,
      "/v1/chat/completions",
      %{
        "messages" => [%{"content" => "adapter recording fixture", "role" => "user"}],
        "metadata" => %{"session_id" => session_id},
        "model" => "unit-model"
      },
      headers
    )
  end

  defp response_receipt(conn) do
    receipt_id = get_in(JSON.decode!(conn.resp_body), ["wardwright", "receipt_id"])
    Wardwright.ReceiptStore.get(receipt_id)
  end

  defp paired_identity(attrs \\ %{}, opts \\ []) do
    {:ok, identity} =
      Identity.issue(
        Map.merge(
          %{
            "adapter_id" => "wardwright-omp",
            "adapter_version" => "0.1.0-rc.1",
            "gateway_url" => "http://127.0.0.1:8787",
            "runtime" => "omp",
            "target" => "omp",
            "workspace_fingerprint" => @workspace_fingerprint
          },
          attrs
        ),
        Keyword.merge([secret: @secret, now: @now], opts)
      )

    identity
  end
end
