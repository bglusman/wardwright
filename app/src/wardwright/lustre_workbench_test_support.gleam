import gleam/json
import gleam/result
import gleam/string
import lustre/dev/query
import lustre/dev/simulate
import lustre/element
import wardwright/lustre_workbench

pub fn selecting_policy_slice_updates_heading(
  pattern_id: String,
  expected_heading: String,
) -> Bool {
  start()
  |> change_select("pattern_id", pattern_id)
  |> view_contains(expected_heading)
}

pub fn initial_view_omits(unwanted_text: String) -> Bool {
  start()
  |> view_omits(unwanted_text)
}

pub fn selecting_policy_slice_exposes_state_graph(
  pattern_id: String,
  expected_transition: String,
) -> Bool {
  let simulation = start() |> change_select("pattern_id", pattern_id)

  view_contains(simulation, "State machine")
  && view_contains(simulation, expected_transition)
}

pub fn selecting_model_policy_slice_exposes_state_graph(
  model_id: String,
  pattern_id: String,
  expected_transition: String,
) -> Bool {
  let simulation =
    start()
    |> change_select("model_id", model_id)
    |> change_select("pattern_id", pattern_id)

  view_contains(simulation, "State machine")
  && view_contains(simulation, expected_transition)
}

pub fn selecting_model_policy_slice_hides_state_graph_transition(
  model_id: String,
  pattern_id: String,
  hidden_transition: String,
) -> Bool {
  let simulation =
    start()
    |> change_select("model_id", model_id)
    |> change_select("pattern_id", pattern_id)

  view_contains(simulation, "State machine")
  && !view_contains(simulation, hidden_transition)
}

pub fn advancing_playback_highlights_state(
  pattern_id: String,
  expected_state: String,
) -> Bool {
  start()
  |> change_select("pattern_id", pattern_id)
  |> simulate.click(on: query.element(matching: query.text("Next step")))
  |> view_has_active_state(expected_state)
}

pub fn selecting_model_updates_simulation(
  model_id: String,
  expected_text: String,
) -> Bool {
  start()
  |> change_select("model_id", model_id)
  |> view_contains(expected_text)
}

pub fn editing_then_submitting_runs_simulation(
  model_id: String,
  user_input: String,
  expected_text: String,
) -> Bool {
  start()
  |> change_select("model_id", model_id)
  |> simulate.input(on: by_id("user_input"), value: user_input)
  |> simulate.submit(on: query.element(matching: query.tag("form")), fields: [
    #("user_input", user_input),
  ])
  |> view_contains(expected_text)
}

pub fn selecting_model_exposes_retry_outputs(
  model_id: String,
  expected_text: String,
) -> Bool {
  start()
  |> change_select("model_id", model_id)
  |> view_contains(expected_text)
}

pub fn selecting_fixture_updates_simulation(
  pattern_id: String,
  model_id: String,
  fixture_id: String,
  expected_text: String,
) -> Bool {
  start()
  |> change_select("model_id", model_id)
  |> change_select("pattern_id", pattern_id)
  |> change_select("fixture_id", fixture_id)
  |> view_contains(expected_text)
}

pub fn selecting_fixture_controls_textarea(
  pattern_id: String,
  model_id: String,
  fixture_id: String,
  field_id: String,
  expected_value: String,
) -> Bool {
  start()
  |> change_select("model_id", model_id)
  |> change_select("pattern_id", pattern_id)
  |> change_select("fixture_id", fixture_id)
  |> view_has_control_value(field_id, expected_value)
}

pub fn editing_retry_output_updates_simulation(
  model_id: String,
  first_response: String,
  retry_response: String,
  expected_text: String,
) -> Bool {
  start()
  |> change_select("model_id", model_id)
  |> simulate.input(on: by_id("model_response"), value: first_response)
  |> simulate.input(on: by_id("retry_response_2"), value: retry_response)
  |> simulate.submit(on: query.element(matching: query.tag("form")), fields: [
    #("model_response", first_response),
    #("retry_response_2", retry_response),
  ])
  |> view_contains(expected_text)
}

pub fn editing_response_advances_path_to(
  pattern_id: String,
  model_id: String,
  model_response: String,
  expected_state: String,
) -> Bool {
  start()
  |> change_select("pattern_id", pattern_id)
  |> change_select("model_id", model_id)
  |> simulate.input(on: by_id("model_response"), value: model_response)
  |> simulate.click(on: query.element(matching: query.text("Next step")))
  |> view_has_active_state(expected_state)
}

pub fn editing_response_keeps_possible_transition(
  pattern_id: String,
  model_id: String,
  model_response: String,
  expected_transition: String,
) -> Bool {
  start()
  |> change_select("pattern_id", pattern_id)
  |> change_select("model_id", model_id)
  |> simulate.input(on: by_id("model_response"), value: model_response)
  |> view_contains(expected_transition)
}

fn start() {
  simulate.simple(
    init: lustre_workbench.init,
    update: lustre_workbench.update,
    view: lustre_workbench.view,
  )
  |> simulate.start(Nil)
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

fn by_id(id: String) {
  query.element(matching: query.id(id))
}

fn view_contains(simulation, text: String) -> Bool {
  simulation
  |> simulate.view
  |> element.to_string
  |> string.contains(text)
}

fn view_omits(simulation, text: String) -> Bool {
  !view_contains(simulation, text)
}

fn view_has_active_state(simulation, state: String) -> Bool {
  simulation
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("wardwright-state-graph")
    |> query.and(query.attribute("data-active-state", state)),
  ))
  |> result.is_ok
}

fn view_has_control_value(
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
