defmodule WardwrightWeb.MCP.Tools.ListHarnessAdapters do
  @moduledoc """
  List agent harness adapters and their replay fidelity limits.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.MCP.Tools

  schema do
  end

  @impl true
  def execute(_params, frame) do
    Tools.reply_json(%{"data" => WardwrightWeb.AgentHarnessAdapters.list()}, frame)
  end
end
