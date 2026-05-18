defmodule Wardwright.ElixirReference.ProjectionCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/projection_core.gleam`.
  """

  def state_ids("tts-retry", _known_pattern),
    do: ["observing", "guarding", "retrying", "recording"]

  def state_ids("stream-rewrite-state", _known_pattern),
    do: ["observing", "rewriting", "review_required", "recording"]

  def state_ids(_pattern_id, true), do: ["active"]
  def state_ids(_pattern_id, false), do: []

  def route_action("", true), do: "engine_decision"
  def route_action("", false), do: "restrict_routes"
  def route_action(action, _has_engine), do: action

  def route_confidence(true), do: "opaque"
  def route_confidence(false), do: "exact"

  def route_effect_target(action) when action in ["restrict_routes", "switch_model", "reroute"],
    do: "route"

  def route_effect_target("block"), do: "request"
  def route_effect_target(_action), do: "policy"

  def tool_action(_kind, top_action, _then_action, _transition_to) when top_action != "",
    do: top_action

  def tool_action("tool_loop_threshold", _top_action, _then_action, _transition_to),
    do: "fail_closed"

  def tool_action("tool_sequence", _top_action, _then_action, transition_to)
      when transition_to != "", do: "state_transition"

  def tool_action("tool_sequence", _top_action, then_action, _transition_to)
      when then_action != "", do: then_action

  def tool_action("tool_result_guard", _top_action, _then_action, _transition_to),
    do: "review_result"

  def tool_action("tool_denylist", _top_action, _then_action, _transition_to), do: "deny_tool"
  def tool_action(_kind, _top_action, _then_action, _transition_to), do: "constrain_tools"

  def tool_effect_target(action) when action in ["deny_tool", "constrain_tools"], do: "tool"
  def tool_effect_target(action) when action in ["fail_closed", "block"], do: "request"
  def tool_effect_target(_action), do: "policy"

  def tool_rule_phase(true, _is_result_rule), do: "tool.loop_governing"
  def tool_rule_phase(false, true), do: "tool.result_interpreting"
  def tool_rule_phase(false, false), do: "tool.planning"

  def effect_confidence("primitive"), do: "exact"
  def effect_confidence(_source_type), do: "inferred"

  def tool_context_phase("tool.result_interpreting"), do: "result_interpretation"
  def tool_context_phase("tool.loop_governing"), do: "loop_governance"
  def tool_context_phase("tool.planning"), do: "planning"
  def tool_context_phase(phase), do: phase
end
