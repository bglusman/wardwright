defmodule WardwrightWeb.MCP.Tools.ActivateSyntheticModel do
  @moduledoc """
  Activate a validated synthetic-model artifact as the current local model.

  Use this only after a draft artifact has been validated, simulated, and
  approved by the user. Activation changes the current local model exposed
  through the OpenAI-compatible /v1 endpoints.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: false}

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
    case PolicyAuthoringDrafts.activate_synthetic_model(params) do
      {:ok, result} -> Tools.reply_json(result, frame)
      {:error, message, result} -> Tools.execution_error(message, frame, result)
    end
  end
end
