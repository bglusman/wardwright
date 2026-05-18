defmodule Wardwright.PolicyCoreReference do
  @moduledoc """
  Compatibility facade for executable Elixir references to the Gleam policy cores.

  This file intentionally lives under `src/wardwright/elixir_reference` as
  documentation and test support. Mix does not compile it into the application;
  tests load it explicitly to keep Elixir semantics available for readers while
  production code calls Gleam.
  """

  Code.require_file("action_core_reference.exs", __DIR__)
  Code.require_file("alert_core_reference.exs", __DIR__)
  Code.require_file("history_core_reference.exs", __DIR__)
  Code.require_file("plan_core_reference.exs", __DIR__)
  Code.require_file("projection_core_reference.exs", __DIR__)
  Code.require_file("route_core_reference.exs", __DIR__)
  Code.require_file("stream_core_reference.exs", __DIR__)
  Code.require_file("structured_core_reference.exs", __DIR__)
  Code.require_file("structured_validation_core_reference.exs", __DIR__)
  Code.require_file("tool_context_core_reference.exs", __DIR__)

  alias Wardwright.ElixirReference.ActionCore
  alias Wardwright.ElixirReference.HistoryCore
  alias Wardwright.ElixirReference.PlanCore
  alias Wardwright.ElixirReference.StreamCore
  alias Wardwright.ElixirReference.StructuredCore

  defdelegate success_status(guard_count), to: StructuredCore

  defdelegate loop_outcome_status(
                rule_id,
                rule_failures,
                max_failures_per_rule,
                attempt_count,
                max_attempts
              ), to: StructuredCore

  defdelegate count_decision(matches, opts), to: HistoryCore, as: :count_matches
  defdelegate plan_threshold(value), to: PlanCore, as: :threshold
  defdelegate plan_threshold_triggered?(count, threshold), to: PlanCore, as: :threshold_triggered?
  defdelegate tool_policy_status(action), to: PlanCore
  defdelegate scope_label(scope), to: PlanCore
  defdelegate state_scope_matches?(required_state, current_state), to: PlanCore
  def sequence_window_limit(nil), do: PlanCore.sequence_window_limit(false, 0)
  def sequence_window_limit(requested), do: PlanCore.sequence_window_limit(true, requested)

  def within_wall_clock_window?(nil, current_ms, prior_ms),
    do: PlanCore.within_wall_clock_window?(false, 0, current_ms, prior_ms)

  def within_wall_clock_window?(max_ms, current_ms, prior_ms),
    do: PlanCore.within_wall_clock_window?(true, max_ms, current_ms, prior_ms)

  defdelegate event_after?(left_created_ms, left_sequence, right_created_ms, right_sequence),
    to: PlanCore

  defdelegate stream_action_tag(action, match_scope), to: StreamCore, as: :action_tag
  defdelegate terminal_stream_status(action), to: StreamCore, as: :terminal_status
  defdelegate action_phase(kind, action), to: ActionCore, as: :phase
  defdelegate action_effect_type(action), to: ActionCore, as: :effect_type
  defdelegate action_conflict_key(action), to: ActionCore, as: :conflict_key
  defdelegate action_conflict_policy(action), to: ActionCore, as: :conflict_policy
  defdelegate action_default_priority(action), to: ActionCore, as: :default_priority
  defdelegate result_action(status, has_blocking_action, action_count), to: ActionCore
end
