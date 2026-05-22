defmodule WardwrightWeb.MCP.Tools.LoadControlDebuggerTrace do
  @moduledoc """
  Load Control Debugger trace events by receipt id or session id.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.ControlDebuggerTools
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:receipt_id, :string, description: "Receipt id whose full-session transcript should be loaded.")
    field(:session_id, :string, description: "Trace session id to load directly.")
  end

  @impl true
  def execute(params, frame) do
    case ControlDebuggerTools.load_trace(params) do
      {:ok, trace} -> Tools.reply_json(trace, frame)
      {:error, message, data} -> Tools.execution_error(message, frame, data)
    end
  end
end
