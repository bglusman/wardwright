import gleam/json
import gleam/result
import gleam/string
import lustre/dev/query
import lustre/dev/simulate
import lustre/element
import wardwright/lustre_control_debugger

pub fn initial_view_contains(expected_text: String) -> Bool {
  start()
  |> view_contains(expected_text)
}

pub fn importing_receipt_shows_status(
  receipt_id: String,
  pattern_id: String,
  title: String,
  expected_text: String,
) -> Bool {
  start()
  |> input("control_receipt_id_text", receipt_id)
  |> change_select("control_pattern_id", pattern_id)
  |> input("control_scenario_title", title)
  |> click_button("Save scenario")
  |> view_contains(expected_text)
}

pub fn replaying_receipt_shows_facts(
  receipt_id: String,
  expected_status: String,
  expected_model: String,
) -> Bool {
  let simulation =
    start()
    |> input("control_receipt_id_text", receipt_id)
    |> click_button("Explain receipt")

  view_contains(simulation, "Replay did not call a provider")
  && view_contains(simulation, expected_status)
  && view_contains(simulation, expected_model)
  && view_contains(simulation, "Replay provider call")
  && view_contains(simulation, "Original provider")
}

pub fn receipt_text_input_is_controlled(receipt_id: String) -> Bool {
  start()
  |> input("control_receipt_id_text", receipt_id)
  |> view_has_control_value("control_receipt_id_text", receipt_id)
}

pub fn receipt_select_has_accessible_name() -> Bool {
  start()
  |> view_has_select_accessible_name("control_receipt_id", "Recent receipt")
}

pub fn running_counterfactual_demo_shows_outcome() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")

  view_contains(simulation, "Recorded scripted example session.")
  && view_contains(simulation, "Original session")
  && view_contains(simulation, "Fork cursor")
  && view_contains(simulation, "Replay provider call")
  && view_contains(simulation, "Comparison accepted")
  && view_contains(simulation, "read-before-edit")
  && view_contains(simulation, "Selected receipt: rcpt_")
  && view_contains(simulation, "Loaded 9 trace event(s)")
  && view_contains(simulation, "Actions for selected event")
  && view_contains(simulation, "Selected trace event")
  && view_contains(simulation, "Recorded evidence")
  && view_contains(simulation, "What changes")
  && view_contains(simulation, "Agent harness export")
  && view_contains(simulation, "Replay selected point")
  && view_contains(simulation, "Continue from selected point")
  && view_contains(
    simulation,
    "Continuation mode only changes Fork and continue.",
  )
  && view_contains(simulation, "Tool call: edit_file")
  && !view_contains(simulation, "No session trace loaded yet")
}

pub fn read_before_edit_trace_states_exact_violation() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")

  view_contains(
    simulation,
    "Violation: edit_file ran before read_file for app.txt.",
  )
  && view_contains(
    simulation,
    "Violation: edit_file ran before read_file for app.txt. Suggested fork point: before mutating app.txt.",
  )
}

pub fn read_before_edit_example_targets_tool_governance_pattern() -> Bool {
  start()
  |> click_button("Record example session")
  |> view_has_select_value("control_pattern_id", "tool-governance")
}

pub fn output_contract_example_targets_output_pattern() -> Bool {
  start()
  |> change_select("control_counterfactual_example", "output-contract")
  |> click_button("Record example session")
  |> view_has_select_value("control_pattern_id", "ambiguous-success")
}

pub fn harness_export_requires_loaded_trace() -> Bool {
  start()
  |> click_button("Prepare harness handoff")
  |> view_contains("Load a session trace before exporting")
}

pub fn opencode_harness_export_shows_fidelity_warning() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Prepare harness handoff")

  view_contains(simulation, "Prepared OpenCode trace handoff and saved")
  && view_contains(simulation, "session_import_best_effort")
  && view_contains(simulation, "Saved file")
  && view_contains(simulation, "Equivalent agent resume")
  && view_contains(simulation, "no")
  && view_contains(simulation, "opencode import")
}

pub fn fork_actions_are_contextual_to_loaded_event() -> Bool {
  let initial = start()

  let loaded =
    start()
    |> click_button("Record example session")

  !view_contains(initial, "Replay selected point")
  && !view_contains(initial, "Continue from selected point")
  && view_contains(loaded, "Actions for selected event")
  && view_contains(loaded, "Click a timeline event to move the replay cursor")
  && view_contains(loaded, "Replay uses recorded evidence only")
  && view_contains(loaded, "Replay selected point")
  && view_contains(loaded, "Continue from selected point")
}

pub fn output_contract_example_shows_non_tool_fork_point() -> Bool {
  let simulation =
    start()
    |> change_select("control_counterfactual_example", "output-contract")
    |> click_button("Record example session")

  view_contains(simulation, "Recorded scripted example session.")
  && view_contains(simulation, "Output contract repair")
  && view_contains(simulation, "result-json-contract")
  && view_contains(simulation, "Loaded 5 trace event(s)")
  && view_contains(simulation, "Model response")
  && view_contains(
    simulation,
    "Suggested fork point: before the response is validated or repaired.",
  )
  && view_contains(simulation, "Policy decision")
  && !view_contains(simulation, "unsafe")
}

pub fn loading_transcript_from_demo_receipt_shows_fork_points() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")

  view_contains(simulation, "Loaded 9 trace event(s)")
  && view_contains(simulation, "Session trace inspector")
  && view_contains(simulation, "Tool call: edit_file")
  && view_contains(simulation, "Suggested fork point")
  && view_contains(simulation, "before mutating app.txt")
}

pub fn replaying_to_loaded_fork_point_shows_no_provider_call() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> click_button("Replay to fork point")

  view_contains(
    simulation,
    "Replayed to selected fork point without calling a provider",
  )
  && view_contains(simulation, "Events replayed")
  && view_contains(simulation, "Provider called")
  && view_contains(simulation, "no")
}

pub fn forking_from_loaded_fork_point_shows_comparison() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> click_button("Fork and continue")

  view_contains(
    simulation,
    "Forked from selected point, applied policy overlay, and continued.",
  )
  && view_contains(simulation, "Fork status")
  && view_contains(simulation, "passed")
  && view_contains(simulation, "Comparison accepted")
  && view_contains(simulation, "yes")
  && view_contains(simulation, "Applied rules")
  && view_contains(simulation, "read-before-edit")
}

pub fn live_model_continuation_shows_provider_call(model_id: String) -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> change_select("control_continuation_mode", "wardwright_model")
    |> change_select("control_live_model_id", model_id)
    |> click_button("Fork and continue")

  view_contains(simulation, "continued through a Wardwright model")
  && view_contains(simulation, "Continuation")
  && view_contains(simulation, "live Wardwright model " <> model_id)
  && view_contains(simulation, "Provider called")
  && view_contains(simulation, "yes")
  && view_contains(simulation, "Live receipt")
  && view_contains(simulation, "Comparison accepted")
}

pub fn invalid_policy_overlay_blocks_fork() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> input("control_policy_overlay_json", "{")
    |> click_button("Fork and continue")

  view_contains(simulation, "Policy overlay JSON is invalid")
}

pub fn blank_policy_overlay_blocks_fork() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> input("control_policy_overlay_json", "")
    |> click_button("Fork and continue")

  view_contains(simulation, "Policy overlay must not be empty")
}

pub fn generic_policy_overlay_can_fork() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> input("control_policy_overlay_json", "{\"id\":\"custom\"}")
    |> click_button("Fork and continue")

  view_contains(
    simulation,
    "Forked from selected point, applied policy overlay, and continued.",
  )
  && view_contains(simulation, "custom")
}

pub fn custom_policy_overlay_changes_applied_rule() -> Bool {
  let simulation =
    start()
    |> click_button("Record example session")
    |> click_button("Load trace")
    |> input(
      "control_policy_overlay_json",
      "{\"id\":\"custom-read-gate\",\"requires_prior_read_for\":[\"edit_file\"]}",
    )
    |> click_button("Fork and continue")

  view_contains(
    simulation,
    "Forked from selected point, applied policy overlay, and continued.",
  )
  && view_contains(simulation, "Applied rules")
  && view_contains(simulation, "custom-read-gate")
}

pub fn policy_overlay_textarea_is_controlled(overlay_json: String) -> Bool {
  start()
  |> click_button("Record example session")
  |> input("control_policy_overlay_json", overlay_json)
  |> view_has_textarea_value("control_policy_overlay_json", overlay_json)
}

fn start() {
  simulate.simple(
    init: lustre_control_debugger.init,
    update: lustre_control_debugger.update,
    view: lustre_control_debugger.view,
  )
  |> simulate.start(Nil)
}

fn input(simulation, control_id: String, field_value: String) {
  simulate.input(simulation, on: by_id(control_id), value: field_value)
}

fn change_select(simulation, control_id: String, selected_id: String) {
  simulate.event(simulation, on: by_id(control_id), name: "change", data: [
    #(
      "target",
      json.object([
        #("value", json.string(selected_id)),
      ]),
    ),
  ])
}

fn click_button(simulation, label: String) {
  simulation
  |> simulate.click(on: query.element(
    matching: query.tag("button")
    |> query.and(query.text(label)),
  ))
}

fn by_id(id: String) {
  query.element(matching: query.id(id))
}

fn view_contains(simulation, text: String) -> Bool {
  simulation
  |> simulate.view
  |> element.to_string
  |> string.contains(text)
}

fn view_has_control_value(
  simulation,
  field_id: String,
  expected_value: String,
) -> Bool {
  simulation
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("input")
    |> query.and(query.id(field_id))
    |> query.and(query.attribute("value", expected_value)),
  ))
  |> result.is_ok
}

fn view_has_textarea_value(
  simulation,
  field_id: String,
  expected_value: String,
) -> Bool {
  simulation
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("textarea")
    |> query.and(query.id(field_id))
    |> query.and(query.attribute("value", expected_value)),
  ))
  |> result.is_ok
}

fn view_has_select_accessible_name(
  simulation,
  select_id: String,
  accessible_name: String,
) -> Bool {
  simulation
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("select")
    |> query.and(query.id(select_id))
    |> query.and(query.attribute("aria-label", accessible_name)),
  ))
  |> result.is_ok
}

fn view_has_select_value(
  simulation,
  select_id: String,
  expected_value: String,
) -> Bool {
  simulation
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("select")
    |> query.and(query.id(select_id))
    |> query.and(query.attribute("value", expected_value)),
  ))
  |> result.is_ok
}
