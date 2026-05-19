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

pub fn selecting_policy_slice_exposes_state_graph(
  pattern_id: String,
  expected_transition: String,
) -> Bool {
  let simulation = start() |> change_select("pattern_id", pattern_id)

  view_contains(simulation, "State machine")
  && view_contains(simulation, expected_transition)
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

fn view_has_active_state(simulation, state: String) -> Bool {
  simulation
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("wardwright-state-graph")
    |> query.and(query.attribute("data-active-state", state)),
  ))
  |> result.is_ok
}
