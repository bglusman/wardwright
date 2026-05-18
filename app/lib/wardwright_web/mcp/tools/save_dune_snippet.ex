defmodule WardwrightWeb.MCP.Tools.SaveDuneSnippet do
  @moduledoc """
  Persist a reviewed local Dune snippet so policies can reference it by id.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: false}

  alias Wardwright.PolicySandbox.DuneSnippetRegistry
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:id, :string,
      description:
        "Workspace snippet id. Use letters, numbers, dots, underscores, colons, or hyphens."
    )

    field(:title, :string, description: "Human-friendly title.")
    field(:phase, :string, description: "Policy phase this snippet is meant to support.")
    field(:description, :string, description: "Human-friendly behavior summary.")

    field(:source, :string,
      description:
        "Dune/Elixir source. The variable input contains the supplied JSON-like input map."
    )

    field(:input_shape, :map, description: "Optional documented input shape.")
    field(:example_input, :map, description: "Optional reviewed example input.")

    field(:replaces_primitives, :list,
      description: "Optional primitive or behavior names this snippet replaces."
    )
  end

  @impl true
  def execute(params, frame) do
    params
    |> DuneSnippetRegistry.save()
    |> case do
      {:ok, result} -> Tools.reply_json(result, frame)
      {:error, message} -> Tools.execution_error(message, frame)
    end
  end
end
