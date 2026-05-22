defmodule WardwrightWeb.MCP.Tools.SaveControlDebuggerEvidence do
  @moduledoc """
  Save selected Control Debugger trace evidence as a pinned simulator case.

  This is write-capable. The selected trace events can contain sensitive
  session metadata, so saved scenario packs must be reviewed before sharing.
  """

  use Hermes.Server.Component, type: :tool

  alias WardwrightWeb.ControlDebuggerTools
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:pattern_id, :string, required: true, description: "Workbench policy pattern id for the simulator case.")
    field(:session_id, :string, required: true, description: "Trace session id.")
    field(:trace_cursor, :string, required: true, description: "Selected trace cursor to preserve.")
    field(:title, :string, description: "Optional scenario title.")
    field(:scenario_id, :string, description: "Optional stable simulator scenario id.")
  end

  @impl true
  def execute(params, frame) do
    case ControlDebuggerTools.save_evidence(params) do
      {:ok, saved} -> Tools.reply_json(saved, frame)
      {:error, message, data} -> Tools.execution_error(message, frame, data)
    end
  end
end
