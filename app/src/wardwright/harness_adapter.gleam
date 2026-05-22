import gleam/list

pub fn contract_version() -> String {
  "wardwright.harness_adapter.v0"
}

pub fn fidelity_label(
  native_session_import: Bool,
  native_session_fork: Bool,
  native_tool_results: Bool,
  workspace_snapshot: Bool,
  private_agent_state: Bool,
) -> String {
  case
    native_session_import,
    native_session_fork,
    native_tool_results,
    workspace_snapshot,
    private_agent_state
  {
    True, True, True, True, True -> "native_harness_replay"
    True, True, _, _, _ -> "session_import_best_effort"
    True, _, _, _, _ -> "session_import_no_native_fork"
    False, _, True, _, _ -> "model_context_replay"
    False, _, _, _, _ -> "prompt_handoff"
  }
}

pub fn missing_fidelity(
  native_session_import: Bool,
  native_session_fork: Bool,
  native_tool_results: Bool,
  workspace_snapshot: Bool,
  private_agent_state: Bool,
) -> List(String) {
  []
  |> require(native_session_import, "native_session_import")
  |> require(native_session_fork, "native_session_fork")
  |> require(native_tool_results, "native_tool_results")
  |> require(workspace_snapshot, "workspace_snapshot")
  |> require(private_agent_state, "private_agent_state")
  |> list.reverse
}

pub fn can_claim_equivalent_agent_resume(
  native_session_import: Bool,
  native_session_resume: Bool,
  native_tool_results: Bool,
  workspace_snapshot: Bool,
  private_agent_state: Bool,
) -> Bool {
  native_session_import
  && native_session_resume
  && native_tool_results
  && workspace_snapshot
  && private_agent_state
}

pub fn adapter_status(installed: Bool, native_session_import: Bool) -> String {
  case installed, native_session_import {
    True, True -> "available"
    True, False -> "handoff_only"
    False, _ -> "not_installed"
  }
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
