defmodule Wardwright.MCPAuthoringTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn
  import Plug.Test

  alias Hermes.Server.Frame
  alias Hermes.Server.Response
  alias WardwrightWeb.MCP.Tools.DeleteDuneSnippet
  alias WardwrightWeb.MCP.Tools.DraftWardwrightModel
  alias WardwrightWeb.MCP.Tools.EvaluateDuneSnippet
  alias WardwrightWeb.MCP.Tools.ExplainProjection
  alias WardwrightWeb.MCP.Tools.ExportAgentHarnessTrace
  alias WardwrightWeb.MCP.Tools.ForkControlDebuggerCursor
  alias WardwrightWeb.MCP.Tools.ListControlDebuggerExamples
  alias WardwrightWeb.MCP.Tools.ListDuneSnippets
  alias WardwrightWeb.MCP.Tools.ListHarnessAdapters
  alias WardwrightWeb.MCP.Tools.LoadControlDebuggerTrace
  alias WardwrightWeb.MCP.Tools.ProposeRuleChange
  alias WardwrightWeb.MCP.Tools.RecordControlDebuggerExample
  alias WardwrightWeb.MCP.Tools.ReplayControlDebuggerCursor
  alias WardwrightWeb.MCP.Tools.ReplayReceiptPolicy
  alias WardwrightWeb.MCP.Tools.SaveControlDebuggerEvidence
  alias WardwrightWeb.MCP.Tools.SaveDuneSnippet
  alias WardwrightWeb.MCP.Tools.ValidatePolicyArtifact

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
             "export_agent_harness_trace",
             "fork_control_debugger_cursor",
             "list_control_debugger_examples",
             "list_dune_snippets",
             "list_harness_adapters",
             "load_control_debugger_trace",
             "propose_rule_change",
             "record_control_debugger_example",
             "replay_control_debugger_cursor",
             "replay_receipt_policy",
             "save_control_debugger_evidence",
             "save_dune_snippet",
             "simulate_policy",
             "validate_policy_artifact"
           ]
  end

  test "control debugger MCP tools run the read-before-edit loop without UI scraping" do
    assert {:reply, %Response{} = list_response, %Frame{}} =
             ListControlDebuggerExamples.execute(%{}, Frame.new())

    assert Enum.any?(list_response.structured_content["data"], &(&1["id"] == "read-before-edit"))

    assert {:reply, %Response{} = record_response, %Frame{}} =
             RecordControlDebuggerExample.execute(%{"example_id" => "read-before-edit"}, Frame.new())

    receipt_id = record_response.structured_content["receipt_id"]
    assert receipt_id =~ "rcpt_"

    session_id = get_in(record_response.structured_content, ["facts", "Original session"])
    cursor = get_in(record_response.structured_content, ["facts", "Fork cursor"])
    assert session_id =~ "session_"
    assert cursor =~ "#{session_id}:"

    assert {:reply, %Response{} = load_response, %Frame{}} =
             LoadControlDebuggerTrace.execute(%{"receipt_id" => receipt_id}, Frame.new())

    assert load_response.structured_content["session_id"] == session_id
    assert load_response.structured_content["suggested_fork_cursor"] == cursor
    assert Enum.any?(load_response.structured_content["events"], &(&1["cursor"] == cursor))

    assert {:reply, %Response{} = replay_response, %Frame{}} =
             ReplayControlDebuggerCursor.execute(
               %{"session_id" => session_id, "trace_cursor" => cursor},
               Frame.new()
             )

    assert replay_response.structured_content["provider_called"] == false
    assert get_in(replay_response.structured_content, ["facts", "Provider called"]) == "no"

    assert {:reply, %Response{} = fork_response, %Frame{}} =
             ForkControlDebuggerCursor.execute(
               %{
                 "policy_overlay" => %{"id" => "mcp-read-before-edit", "requires_prior_read_for" => ["edit_file"]},
                 "session_id" => session_id,
                 "trace_cursor" => cursor
               },
               Frame.new()
             )

    assert fork_response.structured_content["provider_called"] == false
    assert get_in(fork_response.structured_content, ["facts", "Comparison accepted"]) == "yes"
    assert get_in(fork_response.structured_content, ["facts", "Applied rules"]) == "mcp-read-before-edit"

    assert {:reply, %Response{} = save_response, %Frame{}} =
             SaveControlDebuggerEvidence.execute(
               %{
                 "pattern_id" => "tool-governance",
                 "session_id" => session_id,
                 "title" => "MCP read-before-edit trace evidence",
                 "trace_cursor" => cursor
               },
               Frame.new()
             )

    assert save_response.structured_content["pattern_id"] == "tool-governance"
    assert get_in(save_response.structured_content, ["scenario", "source"]) == "live_replay"
    assert get_in(save_response.structured_content, ["scenario", "receipt_preview", "trace_cursor"]) == cursor
  end

  test "agent harness MCP tools expose fidelity limits and export trace evidence" do
    session_id = recorded_session_id!()

    assert {:reply, %Response{} = list_response, %Frame{}} =
             ListHarnessAdapters.execute(%{}, Frame.new())

    opencode =
      Enum.find(list_response.structured_content["data"], &(&1["id"] == "opencode"))

    assert opencode["fidelity"] == "session_import_best_effort"
    assert opencode["equivalent_agent_resume"] == false

    assert {:reply, %Response{} = export_response, %Frame{}} =
             ExportAgentHarnessTrace.execute(
               %{"adapter_id" => "opencode", "session_id" => session_id},
               Frame.new()
             )

    assert get_in(export_response.structured_content, ["export", "artifact_format"]) == "opencode_session_json"
    assert get_in(export_response.structured_content, ["export", "adapter", "equivalent_agent_resume"]) == false
    assert hd(get_in(export_response.structured_content, ["export", "commands"])) =~ "opencode import"
  end

  test "receipt replay MCP tool fails closed for unknown receipts" do
    assert {:error, error, %Frame{}} =
             ReplayReceiptPolicy.execute(%{"receipt_id" => "rcpt_missing"}, Frame.new())

    assert error.reason == :execution_error
    assert error.message == "receipt not found"
    assert error.data == %{receipt_id: "rcpt_missing"}
  end

  test "projection tool returns deterministic projection payloads" do
    assert {:reply, %Response{} = response, %Frame{}} =
             ExplainProjection.execute(
               %{"pattern_id" => "tts-retry"},
               Frame.new()
             )

    assert get_in(response.structured_content, ["projection", "state_machine", "initial_state"]) ==
             "observing"
  end

  test "projection tool fails closed for unknown policy patterns" do
    assert {:error, error, %Frame{}} =
             ExplainProjection.execute(
               %{"pattern_id" => "not-real"},
               Frame.new()
             )

    assert error.reason == :execution_error
    assert error.message == "policy pattern not found"
    assert error.data == %{pattern_id: "not-real"}
  end

  test "validation tool reuses the artifact validator contract" do
    assert {:reply, %Response{} = response, %Frame{}} =
             ValidatePolicyArtifact.execute(%{}, Frame.new())

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
             ListDuneSnippets.execute(%{}, Frame.new())

    assert Enum.any?(
             list_response.structured_content["data"],
             &(&1["id"] == "route.private-context-local-only")
           )

    assert {:reply, %Response{} = eval_response, %Frame{}} =
             EvaluateDuneSnippet.execute(
               %{
                 "input" => %{"risk" => "high"},
                 "source" => """
                 if input["risk"] == "high" do
                   %{"action" => "require_review", "reason" => "high risk"}
                 else
                   %{"action" => "allow", "reason" => "low risk"}
                 end
                 """
               },
               Frame.new()
             )

    assert get_in(eval_response.structured_content, [
             "result",
             "policy_result",
             "action"
           ]) == "require_review"

    assert {:reply, %Response{} = save_response, %Frame{}} =
             SaveDuneSnippet.execute(
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
             EvaluateDuneSnippet.execute(
               %{
                 "input" => %{"risk" => "high"},
                 "snippet_id" => "workspace.high-risk-review"
               },
               Frame.new()
             )

    assert get_in(saved_eval_response.structured_content, [
             "result",
             "policy_result",
             "action"
           ]) == "require_review"

    assert {:reply, %Response{} = delete_response, %Frame{}} =
             DeleteDuneSnippet.execute(
               %{"snippet_id" => "workspace.high-risk-review"},
               Frame.new()
             )

    assert delete_response.structured_content["deleted"] == true
  end

  test "draft Wardwright model tool returns a callable model artifact" do
    assert {:reply, %Response{} = response, %Frame{}} =
             DraftWardwrightModel.execute(
               %{
                 "model_id" => "mcp-router",
                 "route" => %{
                   "id" => "dispatcher.context-fit",
                   "models" => ["local/small", "managed/large"],
                   "type" => "dispatcher"
                 },
                 "targets" => [
                   %{"context_window" => 1024, "model" => "local/small"},
                   %{"context_window" => 128_000, "model" => "managed/large"}
                 ]
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
             ProposeRuleChange.execute(
               %{
                 "collection" => "stream_rules",
                 "operation" => "append_rule",
                 "rule" => %{
                   "action" => "retry_with_reminder",
                   "id" => "retry-old-client",
                   "pattern" => "OldClient(",
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
        JSON.encode!(%{
          "id" => 1,
          "jsonrpc" => "2.0",
          "method" => "initialize",
          "params" => %{
            "capabilities" => %{},
            "clientInfo" => %{"name" => "wardwright-test", "version" => "0"},
            "protocolVersion" => "2025-03-26"
          }
        })
      )

    assert initialize.status == 200

    assert %{"result" => %{"serverInfo" => %{"name" => "wardwright-policy-authoring"}}} =
             JSON.decode!(initialize.resp_body)

    [session_id] = get_resp_header(initialize, "mcp-session-id")

    initialized =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-session-id", session_id)
      |> post(
        "/mcp",
        JSON.encode!(%{
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
        JSON.encode!(%{
          "id" => 2,
          "jsonrpc" => "2.0",
          "method" => "tools/list",
          "params" => %{}
        })
      )

    assert listed.status == 200

    tool_names =
      listed.resp_body
      |> JSON.decode!()
      |> get_in(["result", "tools"])
      |> Enum.map(& &1["name"])

    assert tool_names == [
             "activate_wardwright_model",
             "delete_dune_snippet",
             "draft_wardwright_model",
             "evaluate_dune_snippet",
             "explain_projection",
             "export_agent_harness_trace",
             "fork_control_debugger_cursor",
             "list_control_debugger_examples",
             "list_dune_snippets",
             "list_harness_adapters",
             "load_control_debugger_trace",
             "propose_rule_change",
             "record_control_debugger_example",
             "replay_control_debugger_cursor",
             "replay_receipt_policy",
             "save_control_debugger_evidence",
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
    assert JSON.decode!(rejected.resp_body)["error"]["code"] == "protected_endpoint"
  end

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)

  defp temp_workspace_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end

  defp recorded_session_id! do
    scenario = %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "debugger_example_id" => "read-before-edit",
      "expected" => %{"failure_class" => "read_before_edit_violation"},
      "model_id" => "counterfactual-mcp-test",
      "task" => "Enable the feature flag from settings.json.",
      "workspace" => %{
        "app.txt" => "feature_enabled=false",
        "settings.json" => ~s({"feature_enabled":false})
      }
    }

    assert {:ok, outcome} = WardwrightWeb.CounterfactualReplay.run_recorded_session(scenario)
    outcome["session_id"]
  end
end
