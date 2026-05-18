defmodule Wardwright.ElixirReference.ActionCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/action_core.gleam`.

  This module is documentation and test support only. Production calls the
  Gleam core through thin Elixir boundary wrappers.
  """

  def phase(kind, action) do
    cond do
      action in ["restrict_routes", "switch_model", "reroute"] -> "request.routing"
      action in ["inject_reminder_and_retry", "transform"] -> "request.rewrite"
      action in ["escalate", "alert_async"] -> "request.alert"
      action == "block" -> "request.terminal"
      kind in ["history_threshold", "history_regex_threshold"] -> "request.history"
      true -> "request.review"
    end
  end

  def effect_type(action) do
    case action do
      "block" -> "terminal"
      action when action in ["restrict_routes", "switch_model", "reroute"] -> "route_constraint"
      action when action in ["inject_reminder_and_retry", "transform"] -> "request_transform"
      action when action in ["escalate", "alert_async"] -> "alert"
      "annotate" -> "annotation"
      _ -> "custom"
    end
  end

  def conflict_key(action) do
    case action do
      "block" -> "terminal_decision"
      action when action in ["restrict_routes", "switch_model", "reroute"] -> "route_constraints"
      action when action in ["inject_reminder_and_retry", "transform"] -> "request_rewrite"
      _ -> ""
    end
  end

  def conflict_policy(action) do
    if conflict_key(action) == "", do: "parallel_safe", else: "ordered"
  end

  def default_priority(action) do
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

  def conflict_summary("route_constraints", "ordered") do
    "Multiple route-affecting policy actions matched; declaration order resolves the final route constraints."
  end

  def conflict_summary("terminal_decision", "ordered") do
    "Multiple terminal policy actions matched; fail-closed block semantics win."
  end

  def conflict_summary(key, policy) do
    "Multiple policy actions share #{key}; resolution policy is #{policy}."
  end

  def conflict_resolution("ordered"), do: "preserve policy declaration order"
  def conflict_resolution("parallel_safe"), do: ""
  def conflict_resolution(policy), do: policy
end
