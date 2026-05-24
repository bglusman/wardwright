defmodule WardwrightWeb.MCP.Tools.ForkControlDebuggerCursor do
  @moduledoc """
  Fork a Control Debugger trace at a selected cursor and continue deterministically.

  This writes fork transcript evidence but does not call a provider. It uses the
  deterministic scripted continuation that the Ralph read-before-edit UI path
  uses by default.
  """

  use Hermes.Server.Component, type: :tool

  alias WardwrightWeb.ControlDebuggerTools
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:session_id, :string, required: true, description: "Trace session id.")
    field(:trace_cursor, :string, required: true, description: "Cursor to fork from.")

    field(:policy_overlay, :map, description: "Policy overlay JSON object to apply before deterministic continuation.")
  end

  @impl true
  def execute(params, frame) do
    case ControlDebuggerTools.fork_cursor(params) do
      {:ok, fork} -> Tools.reply_json(fork, frame)
      {:error, message, data} -> Tools.execution_error(message, frame, data)
    end
  end
end
