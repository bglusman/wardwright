defmodule WardwrightWeb.MCPServer do
  @moduledoc false

  use Hermes.Server,
    name: "wardwright-policy-authoring",
    version: Mix.Project.config()[:version],
    capabilities: [:tools]

  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.ExplainProjection)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.SimulatePolicy)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.ListDuneSnippets)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.EvaluateDuneSnippet)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.SaveDuneSnippet)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.DeleteDuneSnippet)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.DraftSyntheticModel)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.ActivateSyntheticModel)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.ProposeRuleChange)
  Code.ensure_compiled!(WardwrightWeb.MCP.Tools.ValidatePolicyArtifact)

  component(WardwrightWeb.MCP.Tools.ExplainProjection, name: "explain_projection")
  component(WardwrightWeb.MCP.Tools.SimulatePolicy, name: "simulate_policy")
  component(WardwrightWeb.MCP.Tools.ListDuneSnippets, name: "list_dune_snippets")
  component(WardwrightWeb.MCP.Tools.EvaluateDuneSnippet, name: "evaluate_dune_snippet")
  component(WardwrightWeb.MCP.Tools.SaveDuneSnippet, name: "save_dune_snippet")
  component(WardwrightWeb.MCP.Tools.DeleteDuneSnippet, name: "delete_dune_snippet")
  component(WardwrightWeb.MCP.Tools.DraftSyntheticModel, name: "draft_synthetic_model")
  component(WardwrightWeb.MCP.Tools.ActivateSyntheticModel, name: "activate_synthetic_model")
  component(WardwrightWeb.MCP.Tools.ProposeRuleChange, name: "propose_rule_change")
  component(WardwrightWeb.MCP.Tools.ValidatePolicyArtifact, name: "validate_policy_artifact")
end
