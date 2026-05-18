defmodule Wardwright.ElixirReference.PlanCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/plan_core.gleam`.
  """

  def threshold(value), do: max(1, value)

  def threshold_decision(count, threshold) do
    count = max(0, count)
    threshold = threshold(threshold)

    if count >= threshold do
      {:triggered, count, threshold}
    else
      {:not_triggered, count, threshold}
    end
  end

  def threshold_triggered?(count, threshold) do
    match?({:triggered, _count, _threshold}, threshold_decision(count, threshold))
  end

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

  def sequence_window_limit(false, _requested), do: 21
  def sequence_window_limit(true, requested), do: max(2, requested + 1)

  def within_wall_clock_window?(false, _max_ms, _current_ms, _prior_ms), do: true

  def within_wall_clock_window?(true, max_ms, current_ms, prior_ms),
    do: current_ms - prior_ms <= max_ms

  def event_after?(left_created_ms, left_sequence, right_created_ms, right_sequence) do
    {left_created_ms, left_sequence} > {right_created_ms, right_sequence}
  end
end
