defmodule Wardwright.ElixirReference.StructuredCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/structured_core.gleam`.
  """

  def guard_action, do: "retry_with_validation_feedback"

  def success_status(0), do: "completed"
  def success_status(_guard_count), do: "completed_after_guard"

  def guard_rule_id(:json_syntax, schema_rule_id, _semantic_rule_id), do: schema_rule_id
  def guard_rule_id(:schema_validation, schema_rule_id, _semantic_rule_id), do: schema_rule_id
  def guard_rule_id(:semantic_validation, _schema_rule_id, semantic_rule_id), do: semantic_rule_id

  def parse_guard_type("json_syntax"), do: {:ok, :json_syntax}
  def parse_guard_type("schema_validation"), do: {:ok, :schema_validation}
  def parse_guard_type("semantic_validation"), do: {:ok, :semantic_validation}
  def parse_guard_type(_raw), do: :error

  def guard_rule_id_for_string(guard_type, schema_rule_id, semantic_rule_id) do
    case parse_guard_type(guard_type) do
      {:ok, parsed} -> guard_rule_id(parsed, schema_rule_id, semantic_rule_id)
      :error -> schema_rule_id
    end
  end

  def loop_outcome(rule_id, rule_failures, max_failures_per_rule, attempt_count, max_attempts) do
    cond do
      rule_failures >= max_failures_per_rule -> {:exhausted_rule_budget, rule_id}
      attempt_count >= max_attempts -> :exhausted_guard_budget
      true -> :continue
    end
  end

  def loop_outcome_status(
        rule_id,
        rule_failures,
        max_failures_per_rule,
        attempt_count,
        max_attempts
      ) do
    case loop_outcome(rule_id, rule_failures, max_failures_per_rule, attempt_count, max_attempts) do
      :continue -> "continue"
      :exhausted_guard_budget -> "exhausted_guard_budget"
      {:exhausted_rule_budget, _rule_id} -> "exhausted_rule_budget"
    end
  end
end
