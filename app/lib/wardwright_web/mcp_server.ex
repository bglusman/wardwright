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
  alias WardwrightWeb.MCP.Tools.ListDuneSnippets
  alias WardwrightWeb.MCP.Tools.ProposeRuleChange
  alias WardwrightWeb.MCP.Tools.SaveDuneSnippet
  alias WardwrightWeb.MCP.Tools.SimulatePolicy
  alias WardwrightWeb.MCP.Tools.ValidatePolicyArtifact

  Code.ensure_compiled!(ExplainProjection)
  Code.ensure_compiled!(SimulatePolicy)
  Code.ensure_compiled!(ListDuneSnippets)
  Code.ensure_compiled!(EvaluateDuneSnippet)
  Code.ensure_compiled!(SaveDuneSnippet)
  Code.ensure_compiled!(DeleteDuneSnippet)
  Code.ensure_compiled!(DraftWardwrightModel)
  Code.ensure_compiled!(ActivateWardwrightModel)
  Code.ensure_compiled!(ProposeRuleChange)
  Code.ensure_compiled!(ValidatePolicyArtifact)

  component(ExplainProjection, name: "explain_projection")
  component(SimulatePolicy, name: "simulate_policy")
  component(ListDuneSnippets, name: "list_dune_snippets")
  component(EvaluateDuneSnippet, name: "evaluate_dune_snippet")
  component(SaveDuneSnippet, name: "save_dune_snippet")
  component(DeleteDuneSnippet, name: "delete_dune_snippet")
  component(DraftWardwrightModel, name: "draft_wardwright_model")
  component(ActivateWardwrightModel, name: "activate_wardwright_model")
  component(ProposeRuleChange, name: "propose_rule_change")
  component(ValidatePolicyArtifact, name: "validate_policy_artifact")
end
