defmodule WardwrightWeb.MCPServer do
  @moduledoc false

  use Hermes.Server,
    name: "wardwright-policy-authoring",
    version: Mix.Project.config()[:version],
    capabilities: [:tools]

  alias WardwrightWeb.MCP.Tools.ActivateWardwrightModel
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
  alias WardwrightWeb.MCP.Tools.SimulatePolicy
  alias WardwrightWeb.MCP.Tools.ValidatePolicyArtifact
  alias WardwrightWeb.MCP.Tools.VerifyHarnessStateFidelity

  Code.ensure_compiled!(ExplainProjection)
  Code.ensure_compiled!(SimulatePolicy)
  Code.ensure_compiled!(ReplayReceiptPolicy)
  Code.ensure_compiled!(ListControlDebuggerExamples)
  Code.ensure_compiled!(RecordControlDebuggerExample)
  Code.ensure_compiled!(LoadControlDebuggerTrace)
  Code.ensure_compiled!(ReplayControlDebuggerCursor)
  Code.ensure_compiled!(ForkControlDebuggerCursor)
  Code.ensure_compiled!(SaveControlDebuggerEvidence)
  Code.ensure_compiled!(ListHarnessAdapters)
  Code.ensure_compiled!(ExportAgentHarnessTrace)
  Code.ensure_compiled!(ListDuneSnippets)
  Code.ensure_compiled!(EvaluateDuneSnippet)
  Code.ensure_compiled!(SaveDuneSnippet)
  Code.ensure_compiled!(DeleteDuneSnippet)
  Code.ensure_compiled!(DraftWardwrightModel)
  Code.ensure_compiled!(ActivateWardwrightModel)
  Code.ensure_compiled!(ProposeRuleChange)
  Code.ensure_compiled!(ValidatePolicyArtifact)
  Code.ensure_compiled!(VerifyHarnessStateFidelity)

  component(ExplainProjection, name: "explain_projection")
  component(SimulatePolicy, name: "simulate_policy")
  component(ReplayReceiptPolicy, name: "replay_receipt_policy")
  component(ListControlDebuggerExamples, name: "list_control_debugger_examples")
  component(RecordControlDebuggerExample, name: "record_control_debugger_example")
  component(LoadControlDebuggerTrace, name: "load_control_debugger_trace")
  component(ReplayControlDebuggerCursor, name: "replay_control_debugger_cursor")
  component(ForkControlDebuggerCursor, name: "fork_control_debugger_cursor")
  component(SaveControlDebuggerEvidence, name: "save_control_debugger_evidence")
  component(ListHarnessAdapters, name: "list_harness_adapters")
  component(ExportAgentHarnessTrace, name: "export_agent_harness_trace")
  component(ListDuneSnippets, name: "list_dune_snippets")
  component(EvaluateDuneSnippet, name: "evaluate_dune_snippet")
  component(SaveDuneSnippet, name: "save_dune_snippet")
  component(DeleteDuneSnippet, name: "delete_dune_snippet")
  component(DraftWardwrightModel, name: "draft_wardwright_model")
  component(ActivateWardwrightModel, name: "activate_wardwright_model")
  component(ProposeRuleChange, name: "propose_rule_change")
  component(ValidatePolicyArtifact, name: "validate_policy_artifact")
  component(VerifyHarnessStateFidelity, name: "verify_harness_state_fidelity")
end
