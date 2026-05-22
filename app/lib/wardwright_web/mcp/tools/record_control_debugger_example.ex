defmodule WardwrightWeb.MCP.Tools.RecordControlDebuggerExample do
  @moduledoc """
  Record a built-in Control Debugger counterfactual example.

  This writes receipt and transcript evidence for the selected example. The
  built-in examples use deterministic scripted continuation and do not require a
  paid provider call.
  """

  use Hermes.Server.Component, type: :tool

  alias WardwrightWeb.ControlDebuggerTools
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:example_id, :string,
      required: true,
      description: "Built-in example id, for example read-before-edit or output-contract."
    )
  end

  @impl true
  def execute(params, frame) do
    example_id = Map.get(params, :example_id) || Map.get(params, "example_id")

    case ControlDebuggerTools.record_example(to_string(example_id || "")) do
      {:ok, recording} -> Tools.reply_json(recording, frame)
      {:error, message, data} -> Tools.execution_error(message, frame, data)
    end
  end
end
