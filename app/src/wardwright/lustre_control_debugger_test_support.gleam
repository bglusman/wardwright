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
    |> click_button("Run deterministic demo")

  view_contains(simulation, "Ran deterministic counterfactual demo.")
  && view_contains(simulation, "Original session")
  && view_contains(simulation, "Fork cursor")
  && view_contains(simulation, "Replay provider call")
  && view_contains(simulation, "Comparison accepted")
  && view_contains(simulation, "read-before-edit")
  && view_contains(simulation, "Selected receipt: rcpt_")
}

pub fn loading_transcript_from_demo_receipt_shows_fork_points() -> Bool {
  let simulation =
    start()
    |> click_button("Run deterministic demo")
    |> click_button("Load transcript")

  view_contains(simulation, "Loaded 9 transcript event(s)")
  && view_contains(simulation, "Transcript inspector")
  && view_contains(simulation, "Tool call: edit_file")
  && view_contains(simulation, "Suggested fork point")
  && view_contains(simulation, "before mutating app.txt")
}

pub fn replaying_to_loaded_fork_point_shows_no_provider_call() -> Bool {
  let simulation =
    start()
    |> click_button("Run deterministic demo")
    |> click_button("Load transcript")
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
    |> click_button("Run deterministic demo")
    |> click_button("Load transcript")
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

pub fn invalid_policy_overlay_blocks_fork() -> Bool {
  let simulation =
    start()
    |> click_button("Run deterministic demo")
    |> click_button("Load transcript")
    |> input("control_policy_overlay_json", "{")
    |> click_button("Fork and continue")

  view_contains(simulation, "Policy overlay JSON is invalid")
}

pub fn invalid_policy_overlay_shape_blocks_fork() -> Bool {
  let simulation =
    start()
    |> click_button("Run deterministic demo")
    |> click_button("Load transcript")
    |> input("control_policy_overlay_json", "{\"id\":\"custom\"}")
    |> click_button("Fork and continue")

  view_contains(
    simulation,
    "Policy overlay must include requires_prior_read_for as a non-empty string list.",
  )
}

pub fn custom_policy_overlay_changes_applied_rule() -> Bool {
  let simulation =
    start()
    |> click_button("Run deterministic demo")
    |> click_button("Load transcript")
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
