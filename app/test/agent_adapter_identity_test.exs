defmodule Wardwright.AgentAdapterIdentityTest do
  use Wardwright.RouterCase

  alias Wardwright.AgentAdapters.Identity

  @secret String.duplicate("adapter-secret", 4)
  @now ~U[2026-05-23 21:00:00Z]

  setup do
    previous_secret = Application.get_env(:wardwright, :adapter_identity_secret)
    Application.put_env(:wardwright, :adapter_identity_secret, @secret)

    on_exit(fn ->
      if is_nil(previous_secret),
        do: Application.delete_env(:wardwright, :adapter_identity_secret),
        else: Application.put_env(:wardwright, :adapter_identity_secret, previous_secret)
    end)

    :ok
  end

  test "gateway pair endpoint issues an OMP adapter identity that the verify endpoint accepts" do
    workspace_fingerprint = Identity.workspace_fingerprint("/tmp/wardwright-project")

    pair_conn =
      call(:post, "/v1/agent-adapters/pair", %{
        "adapter_id" => "wardwright-omp",
        "adapter_version" => "0.1.0",
        "gateway_url" => "http://127.0.0.1:8787",
        "runtime" => "omp",
        "target" => "omp",
        "workspace_fingerprint" => workspace_fingerprint
      })

    assert pair_conn.status == 200
    identity = get_in(JSON.decode!(pair_conn.resp_body), ["identity"])
    assert identity["adapter_id"] == "wardwright-omp"
    assert is_binary(identity["token"])

    verify_conn =
      call(:post, "/v1/agent-adapters/identity/verify", %{
        "identity" => identity,
        "workspace_fingerprint" => workspace_fingerprint
      })

    assert verify_conn.status == 200
    body = JSON.decode!(verify_conn.resp_body)
    assert body["verified"] == true
    assert get_in(body, ["identity", "workspace_fingerprint"]) == workspace_fingerprint
  end

  test "gateway pair endpoint issues a Pi adapter identity that the verify endpoint accepts" do
    workspace_fingerprint = Identity.workspace_fingerprint("/tmp/wardwright-pi-project")

    pair_conn =
      call(:post, "/v1/agent-adapters/pair", %{
        "adapter_id" => "wardwright-pi",
        "adapter_version" => "0.1.0",
        "gateway_url" => "http://127.0.0.1:8787",
        "runtime" => "pi",
        "target" => "pi",
        "workspace_fingerprint" => workspace_fingerprint
      })

    assert pair_conn.status == 200
    identity = get_in(JSON.decode!(pair_conn.resp_body), ["identity"])
    assert identity["adapter_id"] == "wardwright-pi"
    assert is_binary(identity["token"])

    verify_conn =
      call(:post, "/v1/agent-adapters/identity/verify", %{
        "identity" => identity,
        "workspace_fingerprint" => workspace_fingerprint
      })

    assert verify_conn.status == 200
    body = JSON.decode!(verify_conn.resp_body)
    assert body["verified"] == true
    assert get_in(body, ["identity", "runtime"]) == "pi"
    assert get_in(body, ["identity", "workspace_fingerprint"]) == workspace_fingerprint
  end

  test "gateway pair endpoint issues a Claude Code adapter identity that the verify endpoint accepts" do
    workspace_fingerprint = Identity.workspace_fingerprint("/tmp/wardwright-claude-project")

    pair_conn =
      call(:post, "/v1/agent-adapters/pair", %{
        "adapter_id" => "wardwright-claude-code",
        "adapter_version" => "0.1.0",
        "gateway_url" => "http://127.0.0.1:8787",
        "runtime" => "claude-cli",
        "target" => "claude-code",
        "workspace_fingerprint" => workspace_fingerprint
      })

    assert pair_conn.status == 200
    identity = get_in(JSON.decode!(pair_conn.resp_body), ["identity"])
    assert identity["adapter_id"] == "wardwright-claude-code"
    assert identity["target"] == "claude-code"
    assert is_binary(identity["token"])

    verify_conn =
      call(:post, "/v1/agent-adapters/identity/verify", %{
        "identity" => identity,
        "workspace_fingerprint" => workspace_fingerprint
      })

    assert verify_conn.status == 200
    body = JSON.decode!(verify_conn.resp_body)
    assert body["verified"] == true
    assert get_in(body, ["identity", "runtime"]) == "claude-cli"
    assert get_in(body, ["identity", "target"]) == "claude-code"
  end

  test "gateway identity verification rejects wrong-workspace, expired, and malformed identities" do
    identity =
      paired_identity(%{
        "workspace_fingerprint" => Identity.workspace_fingerprint("/tmp/original-project")
      })

    wrong_workspace =
      call(:post, "/v1/agent-adapters/identity/verify", %{
        "identity" => identity,
        "workspace_fingerprint" => Identity.workspace_fingerprint("/tmp/other-project")
      })

    assert wrong_workspace.status == 403
    assert get_in(JSON.decode!(wrong_workspace.resp_body), ["error", "code"]) == "adapter_identity_wrong_workspace"

    expired =
      call(:post, "/v1/agent-adapters/identity/verify", %{
        "identity" => paired_identity(%{}, now: ~U[2020-01-01 00:00:00Z], ttl_seconds: 1),
        "workspace_fingerprint" => Identity.workspace_fingerprint("/tmp/wardwright-project")
      })

    assert expired.status == 401
    assert get_in(JSON.decode!(expired.resp_body), ["error", "code"]) == "adapter_identity_expired"

    malformed =
      call(:post, "/v1/agent-adapters/identity/verify", %{
        "identity" => %{"adapter_id" => "wardwright-omp", "token" => "not-a-token"},
        "workspace_fingerprint" => Identity.workspace_fingerprint("/tmp/wardwright-project")
      })

    assert malformed.status == 401
    assert get_in(JSON.decode!(malformed.resp_body), ["error", "code"]) == "adapter_identity_invalid"
  end

  test "gateway pair endpoint refuses to mint identities for unsupported adapter targets" do
    pair_conn =
      call(:post, "/v1/agent-adapters/pair", %{
        "adapter_id" => "wardwright-opencode",
        "adapter_version" => "0.1.0",
        "gateway_url" => "http://127.0.0.1:8787",
        "runtime" => "opencode-native",
        "target" => "opencode",
        "workspace_fingerprint" => Identity.workspace_fingerprint("/tmp/wardwright-project")
      })

    assert pair_conn.status == 400
    assert get_in(JSON.decode!(pair_conn.resp_body), ["error", "code"]) == "invalid_adapter_pairing"
  end

  defp paired_identity(attrs, opts \\ []) do
    workspace_fingerprint =
      Map.get(attrs, "workspace_fingerprint") ||
        Identity.workspace_fingerprint("/tmp/wardwright-project")

    {:ok, identity} =
      Identity.issue(
        Map.merge(
          %{
            "adapter_id" => "wardwright-omp",
            "adapter_version" => "0.1.0",
            "gateway_url" => "http://127.0.0.1:8787",
            "runtime" => "omp",
            "target" => "omp",
            "workspace_fingerprint" => workspace_fingerprint
          },
          attrs
        ),
        Keyword.merge([secret: @secret, now: @now], opts)
      )

    identity
  end
end
