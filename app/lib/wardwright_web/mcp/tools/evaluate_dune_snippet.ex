defmodule WardwrightWeb.MCP.Tools.EvaluateDuneSnippet do
  @moduledoc """
  Evaluate a registry or ad hoc Dune policy snippet against caller-supplied input.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias Wardwright.PolicySandbox.DuneSnippetRegistry
  alias WardwrightWeb.MCP.Tools

  schema do
    field(:snippet_id, :string,
      description: "Built-in snippet id. Omit when supplying ad hoc source."
    )

    field(:source, :string,
      description:
        "Optional ad hoc Dune/Elixir source. The variable input contains the supplied JSON-like input map."
    )

    field(:input, :map,
      description: "JSON-like input map to bind as input before running the snippet."
    )

    field(:limits, :map,
      description: "Optional timeout_ms, max_reductions, and max_heap_size evaluation limits."
    )
  end

  @impl true
  def execute(params, frame) do
    params
    |> DuneSnippetRegistry.evaluate()
    |> case do
      {:error, message} -> Tools.execution_error(message, frame)
      {:ok, result} -> Tools.reply_json(result, frame)
    end
  end
end
