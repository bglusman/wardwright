defmodule WardwrightWeb.MCP.Tools.ReplayControlDebuggerCursor do
  @moduledoc """
  Replay a Control Debugger trace up to a selected cursor without a provider call.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.ControlDebuggerTools
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:session_id, :string, required: true, description: "Trace session id.")
    field(:trace_cursor, :string, required: true, description: "Cursor to stop before.")
  end

  @impl true
  def execute(params, frame) do
    case ControlDebuggerTools.replay_cursor(params) do
      {:ok, replay} -> Tools.reply_json(replay, frame)
      {:error, message, data} -> Tools.execution_error(message, frame, data)
    end
  end
end
