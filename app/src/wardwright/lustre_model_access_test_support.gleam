import gleam/int
import gleam/json
import gleam/result
import gleam/string
import lustre/dev/query
import lustre/dev/simulate
import lustre/element
import wardwright/lustre_model_access

pub fn initial_view_contains(expected_text: String) -> Bool {
  start()
  |> view_contains(expected_text)
}

pub fn initial_model_view_contains(
  model_id: String,
  expected_text: String,
) -> Bool {
  start_with_model(model_id)
  |> view_contains(expected_text)
}

pub fn creating_key_shows_secret(model_id: String, label: String) -> Bool {
  start()
  |> change_select("model", model_id)
  |> simulate.input(on: by_id("key_label"), value: label)
  |> simulate.submit(
    on: query.element(matching: query.id("create-model-key-form")),
    fields: [
      #("key_label", label),
    ],
  )
  |> view_contains("wwk_")
}

pub fn revoking_key_removes_it(model_id: String, _key_id: String) -> Bool {
  start()
  |> change_select("model", model_id)
  |> simulate.click(on: query.element(
    matching: query.tag("button")
    |> query.and(query.text("Revoke")),
  ))
  |> view_contains("No API keys have been created for this model.")
}

pub fn saving_access_updates_mode(
  model_id: String,
  requires_api_key: String,
  unkeyed_access: String,
  expected_text: String,
) -> Bool {
  start()
  |> change_select("model", model_id)
  |> simulate.submit(
    on: query.element(matching: query.id("model-access-form")),
    fields: [
      #("requires_api_key", requires_api_key),
      #("unkeyed_access", unkeyed_access),
    ],
  )
  |> view_contains(expected_text)
}

pub fn selecting_model_shows(model_id: String, expected_text: String) -> Bool {
  start()
  |> change_select("model", model_id)
  |> view_contains(expected_text)
}

fn start() {
  start_with_model("")
}

fn start_with_model(model_id: String) {
  simulate.simple(
    init: lustre_model_access.init,
    update: lustre_model_access.update,
    view: lustre_model_access.view,
  )
  |> simulate.start(model_id)
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

pub fn view_has_key_count(count: Int) -> Bool {
  start()
  |> simulate.view
  |> query.find(matching: query.element(
    matching: query.tag("dd")
    |> query.and(query.text(int.to_string(count))),
  ))
  |> result.is_ok
}
