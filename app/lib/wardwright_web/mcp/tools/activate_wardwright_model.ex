defmodule WardwrightWeb.MCP.Tools.ActivateWardwrightModel do
  @moduledoc """
  Activate a validated Wardwright model artifact as a registered local model.

  Use this only after a draft artifact has been validated, simulated, and
  approved by the user. Activation registers or updates one model exposed
  through the OpenAI-compatible /v1 endpoints without replacing other registered
  models.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: false}

  alias WardwrightWeb.MCP.Tools
  alias WardwrightWeb.PolicyAuthoringDrafts

  schema do
    field(:artifact, :map,
      description:
        "Optional full artifact. When omitted, provide model_id, targets, route, governance, and stream_rules fields."
    )

    field(:model_id, :string, description: "Unprefixed Wardwright model id, for example support-router.")

    field(:version, :string, description: "Draft version label.")

    field(:targets, :list,
      description:
        "Provider target objects or Wardwright model targets with target_kind=wardwright_model and embedded artifact."
    )

    field(:route, :map,
      description:
        "Route graph node object. Current type values are dispatcher/context-fit, cascade/ordered fallback, and alloy/blended route."
    )

    field(:governance, :list, description: "Request, route, alert, history, and tool governance rule objects.")

    field(:stream_rules, :list,
      description: "Streaming response rules such as hold/rewrite/retry actions over literal or regex matches."
    )
  end

  @impl true
  def execute(params, frame) do
    case PolicyAuthoringDrafts.activate_wardwright_model(params) do
      {:ok, result} -> Tools.reply_json(result, frame)
      {:error, message, result} -> Tools.execution_error(message, frame, result)
    end
  end
end
