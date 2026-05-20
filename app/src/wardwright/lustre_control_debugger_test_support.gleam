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
  |> click_button("Import receipt")
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
    |> click_button("Replay receipt")

  view_contains(simulation, "without calling a provider")
  && view_contains(simulation, expected_status)
  && view_contains(simulation, expected_model)
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
