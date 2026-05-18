defmodule WardwrightWeb.MCP.Tools.DraftSyntheticModel do
  @moduledoc """
  Build and validate a draft synthetic-model artifact without activating it.

  Use this when a user or agent wants to create a reviewable Wardwright model
  from target models, route selectors, governance rules, and stream rules. This
  is intentionally read-only: it returns an artifact, validation result, access
  details, and next steps, but it does not change the served model.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.MCP.Tools
  alias WardwrightWeb.PolicyAuthoringDrafts

  schema do
    field(:artifact, :map,
      description:
        "Optional full artifact. When omitted, provide synthetic_model, targets, route, governance, and stream_rules fields."
    )

    field(:synthetic_model, :string,
      description: "Unprefixed synthetic model id, for example support-router."
    )

    field(:version, :string, description: "Draft version label.")

    field(:targets, :list,
      description: "Concrete target model objects, usually with model and context_window fields."
    )

    field(:route, :map,
      description:
        "Route selector object. Supported type values are dispatcher, cascade, and alloy."
    )

    field(:governance, :list,
      description: "Request, route, alert, history, and tool governance rule objects."
    )

    field(:stream_rules, :list,
      description:
        "Streaming response rules such as hold/rewrite/retry actions over literal or regex matches."
    )
  end

  @impl true
  def execute(params, frame) do
    params
    |> PolicyAuthoringDrafts.synthetic_model_draft()
    |> Tools.reply_json(frame)
  end
end
