defmodule WardwrightWeb.MCP.Tools.ListControlDebuggerExamples do
  @moduledoc """
  List built-in Control Debugger counterfactual examples.
  """

  use Hermes.Server.Component, type: :tool, annotations: %{read_only: true}

  alias WardwrightWeb.ControlDebuggerTools
  alias WardwrightWeb.MCP.Tools

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:ok, examples} = ControlDebuggerTools.list_examples()
    Tools.reply_json(examples, frame)
  end
end
