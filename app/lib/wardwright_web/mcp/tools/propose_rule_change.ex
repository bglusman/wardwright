defmodule WardwrightWeb.MCP.Tools.ProposeRuleChange do
  @moduledoc """
  Return a draft artifact containing a deterministic rule change.

  Use this for small, reviewable edits to existing governance or stream rules.
  The tool never applies changes. It returns a proposed artifact that should be
  validated, simulated, and reviewed before activation.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.MCP.Tools
  alias WardwrightWeb.PolicyAuthoringDrafts

  schema do
    field(:artifact, :map,
      description: "Optional artifact to modify; defaults to current config."
    )

    field(:operation, :string, description: "append_rule, replace_rule, or remove_rule.")

    field(:collection, :string, description: "governance or stream_rules.")

    field(:rule, :map,
      description:
        "Rule object for append_rule or replace_rule. Governance rules cover request/route/history/tool/alert behavior; stream_rules cover streamed response behavior."
    )

    field(:rule_id, :string, description: "Rule id for replace_rule or remove_rule.")
  end

  @impl true
  def execute(params, frame) do
    params
    |> PolicyAuthoringDrafts.propose_rule_change()
    |> Tools.reply_json(frame)
  end
end
