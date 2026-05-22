import gleam/list

pub fn api_contract_version() -> String {
  "wardwright.counterfactual_replay.v0"
}

pub fn recording_scope(
  vcr_mode: String,
  has_session_transcript: Bool,
  receipt_count: Int,
) -> String {
  case vcr_mode, has_session_transcript, receipt_count > 1 {
    "full_session", True, True -> "replayable_session"
    "full_session", _, _ -> "single_turn_full_session"
    "metadata_only", _, _ -> "metadata_only"
    _, _, _ -> "unsupported_recording_mode"
  }
}

pub fn missing_runtime_capabilities(
  has_session_transcript: Bool,
  has_event_cursor: Bool,
  has_policy_overlay: Bool,
  has_live_continuation: Bool,
) -> List(String) {
  []
  |> require(has_session_transcript, "session_transcript")
  |> require(has_event_cursor, "replay_to_event_cursor")
  |> require(has_policy_overlay, "fork_policy_overlay")
  |> require(has_live_continuation, "live_continuation")
  |> list.reverse
}

pub fn replay_mode(missing_capabilities: List(String)) -> String {
  case missing_capabilities {
    [] -> "live_counterfactual"
    _ -> "explain_only"
  }
}

pub fn accepted_outcome(
  original_status: String,
  fork_status: String,
  original_failure_class: String,
  fork_failure_class: String,
) -> Bool {
  original_status == "failed"
  && fork_status == "passed"
  && original_failure_class != ""
  && fork_failure_class == ""
}

fn require(
  missing: List(String),
  present: Bool,
  capability: String,
) -> List(String) {
  case present {
    True -> missing
    False -> [capability, ..missing]
  }
}
