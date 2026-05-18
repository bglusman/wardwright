defmodule Wardwright.MCPAuthoringTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  import Phoenix.ConnTest

  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @endpoint WardwrightWeb.Endpoint

  setup_all do
    original_config = Application.get_env(:wardwright, WardwrightWeb.Endpoint, [])

    endpoint_config =
      Keyword.merge(original_config,
        http: [ip: {127, 0, 0, 1}, port: 0],
        server: false,
        secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))
      )

    Application.put_env(:wardwright, WardwrightWeb.Endpoint, endpoint_config)
    start_supervised!(WardwrightWeb.Endpoint)

    on_exit(fn ->
      Application.put_env(:wardwright, WardwrightWeb.Endpoint, original_config)
    end)

    :ok
  end

  setup do
    Wardwright.reset_config()
    Wardwright.ReceiptStore.clear()
    Wardwright.PolicyScenarioStore.clear()
    Wardwright.PolicyCache.reset()
    :ok
  end

  test "Hermes MCP server exposes policy authoring tools" do
    tool_names =
      WardwrightWeb.MCPServer.__components__(:tool)
      |> Enum.map(& &1.name)

    assert tool_names == [
             "activate_wardwright_model",
             "delete_dune_snippet",
             "draft_wardwright_model",
             "evaluate_dune_snippet",
             "explain_projection",
             "list_dune_snippets",
             "propose_rule_change",
             "save_dune_snippet",
             "simulate_policy",
             "validate_policy_artifact"
           ]
  end

  test "projection tool returns deterministic projection payloads" do
    assert {:reply, %Response{} = response, %Frame{}} =
             WardwrightWeb.MCP.Tools.ExplainProjection.execute(
               %{"pattern_id" => "tts-retry"},
               Frame.new()
             )

    assert get_in(response.structured_content, ["projection", "state_machine", "initial_state"]) ==
             "observing"
  end

  test "projection tool fails closed for unknown policy patterns" do
    assert {:error, error, %Frame{}} =
             WardwrightWeb.MCP.Tools.ExplainProjection.execute(
               %{"pattern_id" => "not-real"},
               Frame.new()
             )

    assert error.reason == :execution_error
    assert error.message == "policy pattern not found"
    assert error.data == %{pattern_id: "not-real"}
  end

  test "validation tool reuses the artifact validator contract" do
    assert {:reply, %Response{} = response, %Frame{}} =
             WardwrightWeb.MCP.Tools.ValidatePolicyArtifact.execute(%{}, Frame.new())

    assert response.structured_content["schema"] == "wardwright.policy_validation.v1"
    assert response.structured_content["source"] == "current_config"
  end

  test "Dune snippet MCP tools list registry snippets and evaluate ad hoc source" do
    original_workspace = Application.get_env(:wardwright, :dune_snippet_workspace_dir)
    workspace_dir = temp_workspace_dir("wardwright-mcp-dune-snippets")
    Application.put_env(:wardwright, :dune_snippet_workspace_dir, workspace_dir)

    on_exit(fn ->
      File.rm_rf!(workspace_dir)
      restore_env(:dune_snippet_workspace_dir, original_workspace)
    end)

    assert {:reply, %Response{} = list_response, %Frame{}} =
             WardwrightWeb.MCP.Tools.ListDuneSnippets.execute(%{}, Frame.new())

    assert Enum.any?(
             list_response.structured_content["data"],
             &(&1["id"] == "route.private-context-local-only")
           )

    assert {:reply, %Response{} = eval_response, %Frame{}} =
             WardwrightWeb.MCP.Tools.EvaluateDuneSnippet.execute(
               %{
                 "source" => """
                 if input["risk"] == "high" do
                   %{"action" => "require_review", "reason" => "high risk"}
                 else
                   %{"action" => "allow", "reason" => "low risk"}
                 end
                 """,
                 "input" => %{"risk" => "high"}
               },
               Frame.new()
             )

    assert get_in(eval_response.structured_content, [
             "result",
             "policy_result",
             "action"
           ]) == "require_review"

    assert {:reply, %Response{} = save_response, %Frame{}} =
             WardwrightWeb.MCP.Tools.SaveDuneSnippet.execute(
               %{
                 "id" => "workspace.high-risk-review",
                 "source" => """
                 if input["risk"] == "high" do
                   %{"action" => "require_review", "reason" => "saved high risk snippet"}
                 else
                   %{"action" => "allow"}
                 end
                 """
               },
               Frame.new()
             )

    assert get_in(save_response.structured_content, ["snippet", "id"]) ==
             "workspace.high-risk-review"

    assert {:reply, %Response{} = saved_eval_response, %Frame{}} =
             WardwrightWeb.MCP.Tools.EvaluateDuneSnippet.execute(
               %{
                 "snippet_id" => "workspace.high-risk-review",
                 "input" => %{"risk" => "high"}
               },
               Frame.new()
             )

    assert get_in(saved_eval_response.structured_content, [
             "result",
             "policy_result",
             "action"
           ]) == "require_review"

    assert {:reply, %Response{} = delete_response, %Frame{}} =
             WardwrightWeb.MCP.Tools.DeleteDuneSnippet.execute(
               %{"snippet_id" => "workspace.high-risk-review"},
               Frame.new()
             )

    assert delete_response.structured_content["deleted"] == true
  end

  test "draft Wardwright model tool returns a callable model artifact" do
    assert {:reply, %Response{} = response, %Frame{}} =
             WardwrightWeb.MCP.Tools.DraftWardwrightModel.execute(
               %{
                 "model_id" => "mcp-router",
                 "targets" => [
                   %{"model" => "local/small", "context_window" => 1024},
                   %{"model" => "managed/large", "context_window" => 128_000}
                 ],
                 "route" => %{
                   "type" => "dispatcher",
                   "id" => "dispatcher.context-fit",
                   "models" => ["local/small", "managed/large"]
                 }
               },
               Frame.new()
             )

    assert get_in(response.structured_content, ["artifact", "model_id"]) == "mcp-router"
    assert get_in(response.structured_content, ["validation", "errors"]) == []

    assert get_in(response.structured_content, ["access", "model_ids"]) == [
             "mcp-router",
             "wardwright/mcp-router"
           ]
  end

  test "propose rule change tool returns a draft-only proposal" do
    assert {:reply, %Response{} = response, %Frame{}} =
             WardwrightWeb.MCP.Tools.ProposeRuleChange.execute(
               %{
                 "operation" => "append_rule",
                 "collection" => "stream_rules",
                 "rule" => %{
                   "id" => "retry-old-client",
                   "pattern" => "OldClient(",
                   "action" => "retry_with_reminder",
                   "reminder" => "Use NewClient instead."
                 }
               },
               Frame.new()
             )

    assert get_in(response.structured_content, ["proposal", "applied"]) == false
    assert get_in(response.structured_content, ["proposal", "rule_id"]) == "retry-old-client"
    assert get_in(response.structured_content, ["validation", "errors"]) == []
  end

  test "streamable HTTP transport initializes and lists tools through the Phoenix mount" do
    initialize =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post(
        "/mcp",
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => "2025-03-26",
            "capabilities" => %{},
            "clientInfo" => %{"name" => "wardwright-test", "version" => "0"}
          }
        })
      )

    assert initialize.status == 200

    assert %{"result" => %{"serverInfo" => %{"name" => "wardwright-policy-authoring"}}} =
             Jason.decode!(initialize.resp_body)

    [session_id] = get_resp_header(initialize, "mcp-session-id")

    initialized =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-session-id", session_id)
      |> post(
        "/mcp",
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized",
          "params" => %{}
        })
      )

    assert initialized.status == 202

    listed =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-session-id", session_id)
      |> post(
        "/mcp",
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })
      )

    assert listed.status == 200

    tool_names =
      listed.resp_body
      |> Jason.decode!()
      |> get_in(["result", "tools"])
      |> Enum.map(& &1["name"])

    assert tool_names == [
             "activate_wardwright_model",
             "delete_dune_snippet",
             "draft_wardwright_model",
             "evaluate_dune_snippet",
             "explain_projection",
             "list_dune_snippets",
             "propose_rule_change",
             "save_dune_snippet",
             "simulate_policy",
             "validate_policy_artifact"
           ]
  end

  test "protected access plug rejects non-local callers without an admin token" do
    original_prototype_access = Application.get_env(:wardwright, :allow_prototype_access)
    original_admin_token = Application.get_env(:wardwright, :admin_token)

    Application.put_env(:wardwright, :allow_prototype_access, false)
    Application.delete_env(:wardwright, :admin_token)

    on_exit(fn ->
      restore_env(:allow_prototype_access, original_prototype_access)
      restore_env(:admin_token, original_admin_token)
    end)

    rejected =
      conn(:post, "/mcp", "{}")
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> WardwrightWeb.ProtectedAccess.call([])

    assert rejected.status == 403
    assert rejected.halted
    assert Jason.decode!(rejected.resp_body)["error"]["code"] == "protected_endpoint"
  end

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)

  defp temp_workspace_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end
end
