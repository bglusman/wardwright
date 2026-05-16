defmodule Wardwright.PolicyCoreReference do
  @moduledoc """
  Executable Elixir reference for selected Gleam policy cores.

  This file intentionally lives under `src/wardwright/elixir_reference` as
  documentation and test support. Mix does not compile it into the application;
  `test/gleam_policy_core_test.exs` loads it explicitly to keep representative
  Elixir semantics available for readers while production code calls Gleam.
  """

  def success_status(guard_count) do
    if guard_count == 0, do: "completed", else: "completed_after_guard"
  end

  def loop_outcome_status(
        rule_id,
        rule_failures,
        max_failures_per_rule,
        attempt_count,
        max_attempts
      ) do
    cond do
      rule_failures >= max_failures_per_rule -> {"exhausted_rule_budget", rule_id}
      attempt_count >= max_attempts -> {"exhausted_guard_budget", nil}
      true -> {"continue", nil}
    end
    |> elem(0)
  end

  def count_decision(matches, opts) do
    threshold = opts |> Keyword.fetch!(:threshold) |> max(1)
    recent_limit = opts |> Keyword.fetch!(:recent_limit) |> max(1)
    working_set_size = Keyword.fetch!(opts, :working_set_size)
    scope = Keyword.fetch!(opts, :scope)

    count = matches |> Enum.take(recent_limit) |> Enum.count(& &1)
    status = if count >= threshold, do: :triggered, else: :not_triggered

    {status, scope, count, threshold, recent_limit, working_set_size}
  end

  def plan_threshold(value), do: max(1, value)
  def plan_threshold_triggered?(count, threshold), do: max(0, count) >= max(1, threshold)

  def tool_policy_status(action) do
    case action do
      "block" -> "blocked"
      action when action in ["restrict_routes", "switch_model", "reroute"] -> "rerouted"
      action when action in ["escalate", "alert_async"] -> "alerted"
      action when action in ["inject_reminder_and_retry", "transform"] -> "transformed"
      _ -> "allowed"
    end
  end

  def scope_label(""), do: "session"
  def scope_label("session_id"), do: "session"
  def scope_label("run_id"), do: "run"
  def scope_label(value), do: value

  def state_scope_matches?("", _current_state), do: true
  def state_scope_matches?("active", current_state), do: current_state == "active"
  def state_scope_matches?(required_state, current_state), do: current_state == required_state

  def sequence_window_limit(nil), do: 21
  def sequence_window_limit(requested), do: max(2, requested + 1)

  def within_wall_clock_window?(nil, _current_ms, _prior_ms), do: true
  def within_wall_clock_window?(max_ms, current_ms, prior_ms), do: current_ms - prior_ms <= max_ms

  def event_after?(left_created_ms, left_sequence, right_created_ms, right_sequence) do
    {left_created_ms, left_sequence} > {right_created_ms, right_sequence}
  end

  def stream_action_tag(action, match_scope) do
    case {action, match_scope} do
      {"rewrite", "stream_window"} -> "rewrite_window"
      {"rewrite", _} -> "rewrite_chunk"
      {"rewrite_chunk", "stream_window"} -> "rewrite_window"
      {"rewrite_chunk", _} -> "rewrite_chunk"
      {"drop_chunk", _} -> "drop_chunk"
      {action, _} when action in ["block", "block_final"] -> "block"
      {action, _} when action in ["retry", "retry_with_reminder"] -> "retry"
      {"pass", _} -> "pass"
      _ -> "annotate"
    end
  end

  def terminal_stream_status(action) do
    case stream_action_tag(action, "chunk") do
      "block" -> "stream_policy_blocked"
      "retry" -> "stream_policy_retry_required"
      _ -> "completed"
    end
  end

  def action_phase(kind, action) do
    cond do
      action in ["restrict_routes", "switch_model", "reroute"] -> "request.routing"
      action in ["inject_reminder_and_retry", "transform"] -> "request.rewrite"
      action in ["escalate", "alert_async"] -> "request.alert"
      action == "block" -> "request.terminal"
      kind in ["history_threshold", "history_regex_threshold"] -> "request.history"
      true -> "request.review"
    end
  end

  def action_effect_type(action) do
    case action do
      "block" -> "terminal"
      action when action in ["restrict_routes", "switch_model", "reroute"] -> "route_constraint"
      action when action in ["inject_reminder_and_retry", "transform"] -> "request_transform"
      action when action in ["escalate", "alert_async"] -> "alert"
      "annotate" -> "annotation"
      _ -> "custom"
    end
  end

  def action_conflict_key(action) do
    case action do
      "block" -> "terminal_decision"
      action when action in ["restrict_routes", "switch_model", "reroute"] -> "route_constraints"
      action when action in ["inject_reminder_and_retry", "transform"] -> "request_rewrite"
      _ -> ""
    end
  end

  def action_conflict_policy(action) do
    if action_conflict_key(action) == "", do: "parallel_safe", else: "ordered"
  end

  def action_default_priority(action) do
    case action do
      "block" -> 10
      action when action in ["restrict_routes", "switch_model", "reroute"] -> 30
      action when action in ["inject_reminder_and_retry", "transform"] -> 50
      action when action in ["escalate", "alert_async"] -> 70
      _ -> 90
    end
  end

  def result_action(status, has_blocking_action, _action_count) do
    cond do
      status == "error" -> "block"
      has_blocking_action -> "block"
      true -> "allow"
    end
  end
end
