import gleam/json
import gleam/string
import lustre/dev/query
import lustre/dev/simulate
import lustre/element
import wardwright/lustre_admin

pub fn selecting_model_access_model_updates_workbench_href(
  model_id: String,
) -> Bool {
  start("model_access")
  |> change_select("model", model_id)
  |> view_contains("/admin?model=" <> model_id)
}

pub fn workbench_deep_link_uses_selected_model(
  model_id: String,
  expected_text: String,
) -> Bool {
  start("workbench:" <> model_id)
  |> view_contains(expected_text)
}

fn start(flags: String) {
  simulate.simple(
    init: lustre_admin.init,
    update: lustre_admin.update,
    view: lustre_admin.view,
  )
  |> simulate.start(flags)
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
