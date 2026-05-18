defmodule WardwrightWeb.MCP.Tools.DeleteDuneSnippet do
  @moduledoc """
  Delete a local workspace Dune snippet.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: false}

  alias Wardwright.PolicySandbox.DuneSnippetRegistry
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:snippet_id, :string, description: "Workspace Dune snippet id to delete.")
  end

  @impl true
  def execute(params, frame) do
    params
    |> Map.get("snippet_id", Map.get(params, :snippet_id))
    |> DuneSnippetRegistry.delete()
    |> case do
      {:ok, result} -> Tools.reply_json(result, frame)
      {:error, message} -> Tools.execution_error(message, frame)
    end
  end
end
