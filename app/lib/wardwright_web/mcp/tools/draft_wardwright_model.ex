defmodule WardwrightWeb.MCP.Tools.DraftWardwrightModel do
  @moduledoc """
  Build and validate a draft Wardwright model artifact without activating it.

  Use this when a user or agent wants to create a reviewable Wardwright model
  from provider targets, Wardwright model targets, route graph nodes,
  governance rules, and stream rules. This is intentionally read-only: it
  returns an artifact, validation result, access details, and next steps, but it
  does not change the served model.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.MCP.Tools
  alias WardwrightWeb.PolicyAuthoringDrafts

  schema do
    field(:artifact, :map,
      description:
        "Optional full artifact. When omitted, provide model_id, targets, route, governance, and stream_rules fields."
    )

    field(:model_id, :string,
      description: "Unprefixed Wardwright model id, for example support-router."
    )

    field(:version, :string, description: "Draft version label.")

    field(:targets, :list,
      description:
        "Provider target objects or Wardwright model targets with target_kind=wardwright_model and embedded artifact."
    )

    field(:route, :map,
      description:
        "Route graph node object. Current type values are dispatcher/context-fit, cascade/ordered fallback, and alloy/blended route."
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
    |> PolicyAuthoringDrafts.wardwright_model_draft()
    |> Tools.reply_json(frame)
  end
end
