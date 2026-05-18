defmodule Wardwright.ElixirReference.ToolContextCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/tool_context_core.gleam`.
  """

  def inferred_phase(has_primary_tool, has_available_tools, has_tool_result) do
    cond do
      has_tool_result -> "result_interpretation"
      has_primary_tool or has_available_tools -> "planning"
      true -> ""
    end
  end

  def inferred_confidence(
        has_chosen_tool,
        has_assistant_tool,
        available_tool_count,
        has_tool_result
      ) do
    cond do
      has_chosen_tool or has_assistant_tool -> "exact"
      has_tool_result -> "inferred"
      available_tool_count == 1 -> "declared"
      true -> "ambiguous"
    end
  end

  def result_status(true), do: "unknown"
  def result_status(false), do: ""

  def default_namespace(true, _tool_type), do: ""
  def default_namespace(false, "function"), do: "openai.function"
  def default_namespace(false, _tool_type), do: "openai.tool"

  def list_matches?([], _actual), do: true
  def list_matches?(_expected, ""), do: false
  def list_matches?(expected, actual), do: actual in expected
end
