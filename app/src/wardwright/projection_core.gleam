import gleam/string

pub type StateTransition =
  #(String, String, String, String, String)

pub fn derive_summary(
  pattern_id: String,
  model_id: String,
  config_version: String,
) -> #(String, String, String, Bool, List(StateTransition)) {
  let #(initial_state, default_projection, transitions) =
    state_machine(pattern_id)

  #(
    engine_id(pattern_id),
    artifact_label(pattern_id, model_id, config_version),
    initial_state,
    default_projection,
    transitions,
  )
}

pub fn state_ids(pattern_id: String, known_pattern: Bool) -> List(String) {
  case pattern_id, known_pattern {
    "tts-retry", _ -> ["observing", "guarding", "retrying", "recording"]
    "stream-rewrite-state", _ -> [
      "observing",
      "rewriting",
      "review_required",
      "recording",
    ]
    _, True -> ["active"]
    _, False -> []
  }
}

pub fn engine_id(pattern_id: String) -> String {
  case pattern_id {
    "ambiguous-success" -> "hybrid-output-review"
    "route-privacy" -> "request-route-plan"
    "tool-governance" -> "tool-context-plan"
    _ -> "structured-stream-primitives"
  }
}

pub fn artifact_label(
  pattern_id: String,
  model_id: String,
  config_version: String,
) -> String {
  "draft."
  <> blank_default(pattern_id, "policy")
  <> ".001 / "
  <> blank_default(model_id, "model")
  <> " / "
  <> blank_default(config_version, "unversioned")
}

pub fn state_machine(
  pattern_id: String,
) -> #(String, Bool, List(StateTransition)) {
  case pattern_id {
    "tts-retry" -> #("observing", False, [
      #(
        "observing",
        "stream.release",
        "recording",
        "release_stream",
        "tts.receipt-events",
      ),
      #(
        "observing",
        "stream.match",
        "guarding",
        "abort_attempt",
        "tts.no-old-client",
      ),
      #(
        "guarding",
        "attempt.retry",
        "retrying",
        "retry_with_reminder",
        "tts.retry-arbiter",
      ),
      #(
        "retrying",
        "stream.match",
        "guarding",
        "abort_attempt",
        "tts.no-old-client",
      ),
      #(
        "retrying",
        "retry.release",
        "retrying",
        "release_stream",
        "tts.no-old-client",
      ),
      #(
        "retrying",
        "receipt.write",
        "recording",
        "annotate_receipt",
        "tts.receipt-events",
      ),
    ])

    "stream-rewrite-state" -> #("observing", False, [
      #(
        "observing",
        "stream.release",
        "recording",
        "release_stream",
        "stream.rewrite-receipt",
      ),
      #(
        "observing",
        "history.related-secret",
        "review_required",
        "state_transition",
        "stream.secret-transition",
      ),
      #(
        "observing",
        "request.rewrite",
        "observing",
        "rewrite_span",
        "request.rewrite-context",
      ),
      #(
        "observing",
        "regex.rewrite",
        "rewriting",
        "rewrite_span",
        "stream.redact-account",
      ),
      #(
        "rewriting",
        "rewrite.release",
        "recording",
        "release_stream",
        "stream.rewrite-receipt",
      ),
      #(
        "rewriting",
        "regex.related-secret",
        "review_required",
        "state_transition",
        "stream.secret-transition",
      ),
      #(
        "review_required",
        "receipt.write",
        "recording",
        "annotate_receipt",
        "stream.rewrite-receipt",
      ),
    ])

    _ -> #("active", True, [])
  }
}

pub fn route_action(action: String, has_engine: Bool) -> String {
  case action, has_engine {
    "", True -> "engine_decision"
    "", False -> "restrict_routes"
    action, _ -> action
  }
}

pub fn route_confidence(has_engine: Bool) -> String {
  case has_engine {
    True -> "opaque"
    False -> "exact"
  }
}

pub fn route_effect_target(action: String) -> String {
  case action {
    "restrict_routes" -> "route"
    "switch_model" | "reroute" -> "route"
    "block" -> "request"
    _ -> "policy"
  }
}

pub fn tool_action(
  kind: String,
  top_action: String,
  then_action: String,
  transition_to: String,
) -> String {
  case top_action, kind, transition_to, then_action {
    top_action, _, _, _ if top_action != "" -> top_action
    _, "tool_loop_threshold", _, _ -> "fail_closed"
    _, "tool_sequence", transition_to, _ if transition_to != "" ->
      "state_transition"
    _, "tool_sequence", _, then_action if then_action != "" -> then_action
    _, "allowed_tools", _, _ -> "block"
    _, "tool_result_guard", _, _ -> "review_result"
    _, "tool_denylist", _, _ -> "deny_tool"
    _, _, _, _ -> "constrain_tools"
  }
}

pub fn tool_effect_target(action: String) -> String {
  case action {
    "deny_tool" | "constrain_tools" -> "tool"
    "fail_closed" | "block" -> "request"
    _ -> "policy"
  }
}

pub fn tool_rule_phase(is_loop_rule: Bool, is_result_rule: Bool) -> String {
  case is_loop_rule, is_result_rule {
    True, _ -> "tool.loop_governing"
    False, True -> "tool.result_interpreting"
    False, False -> "tool.planning"
  }
}

pub fn effect_confidence(source_type: String) -> String {
  case source_type {
    "primitive" -> "exact"
    _ -> "inferred"
  }
}

pub fn tool_context_phase(phase: String) -> String {
  case phase {
    "tool.result_interpreting" -> "result_interpretation"
    "tool.loop_governing" -> "loop_governance"
    "tool.planning" -> "planning"
    _ -> phase
  }
}

fn blank_default(value: String, fallback: String) -> String {
  case string.trim(value) {
    "" -> fallback
    trimmed -> trimmed
  }
}
