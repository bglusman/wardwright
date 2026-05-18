defmodule WardwrightWeb.MCP.Tools.ListDuneSnippets do
  @moduledoc """
  List built-in and local workspace Dune snippet candidates for policy authoring.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.MCP.Tools

  schema do
  end

  @impl true
  def execute(_params, frame) do
    Wardwright.PolicySandbox.DuneSnippetRegistry.list()
    |> Tools.reply_json(frame)
  end
end
