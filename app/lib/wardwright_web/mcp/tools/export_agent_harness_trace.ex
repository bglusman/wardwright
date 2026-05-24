defmodule WardwrightWeb.MCP.Tools.ExportAgentHarnessTrace do
  @moduledoc """
  Export a recorded session trace for an external agent harness.

  This returns a reviewable artifact and command hints. It must not be treated
  as equivalent hidden agent state unless the adapter says
  equivalent_agent_resume is true.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.AgentHarnessAdapters
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:adapter_id, :string, required: true, description: "Harness adapter id, for example opencode.")
    field(:session_id, :string, required: true, description: "Wardwright full-session trace id to export.")
    field(:cwd, :string, description: "Optional workspace path to record in the exported harness artifact.")
    field(:title, :string, description: "Optional human-readable title for the exported harness session.")
  end

  @impl true
  def execute(params, frame) do
    adapter_id = Map.get(params, :adapter_id) || Map.get(params, "adapter_id")
    session_id = Map.get(params, :session_id) || Map.get(params, "session_id")

    opts =
      params
      |> Map.take([:cwd, :title, "cwd", "title"])
      |> Map.new(fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        pair -> pair
      end)

    case AgentHarnessAdapters.export(to_string(session_id || ""), to_string(adapter_id || ""), opts) do
      {:ok, export} -> Tools.reply_json(%{"export" => export}, frame)
      {:error, message} -> Tools.execution_error(message, frame)
    end
  end
end
