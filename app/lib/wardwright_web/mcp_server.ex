defmodule WardwrightWeb.MCPServer do
  @moduledoc false

  use Hermes.Server,
    name: "wardwright-policy-authoring",
    version: Mix.Project.config()[:version],
    capabilities: [:tools]

  component(WardwrightWeb.MCP.Tools.ExplainProjection, name: "explain_projection")
  component(WardwrightWeb.MCP.Tools.SimulatePolicy, name: "simulate_policy")
  component(WardwrightWeb.MCP.Tools.DraftSyntheticModel, name: "draft_synthetic_model")
  component(WardwrightWeb.MCP.Tools.ActivateSyntheticModel, name: "activate_synthetic_model")
  component(WardwrightWeb.MCP.Tools.ProposeRuleChange, name: "propose_rule_change")
  component(WardwrightWeb.MCP.Tools.ValidatePolicyArtifact, name: "validate_policy_artifact")
end
