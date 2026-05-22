defmodule WardwrightWeb.MCP.Tools.ReplayReceiptPolicy do
  @moduledoc """
  Replay recorded policy and route decisions for one receipt without a provider call.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.MCP.Tools

  schema do
    field(:receipt_id, :string, required: true, description: "Receipt id to replay from recorded VCR data.")
  end

  @impl true
  def execute(params, frame) do
    receipt_id = Map.get(params, :receipt_id) || Map.get(params, "receipt_id")

    case Wardwright.PolicyReplay.replay_receipt_id(to_string(receipt_id || "")) do
      {:ok, replay} -> Tools.reply_json(%{"replay" => replay}, frame)
      {:error, :receipt_not_found} -> Tools.execution_error("receipt not found", frame, %{receipt_id: receipt_id})
      {:error, message} -> Tools.execution_error(message, frame)
    end
  end
end
