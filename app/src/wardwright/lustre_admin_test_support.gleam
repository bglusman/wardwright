import gleam/json
import gleam/string
import lustre/dev/query
import lustre/dev/simulate
import lustre/element
import wardwright/lustre_admin

pub fn selecting_model_access_model_syncs_workbench(
  model_id: String,
  expected_text: String,
) -> Bool {
  start()
  |> click_nav("Model access")
  |> change_select("model", model_id)
  |> click_nav("Workbench")
  |> view_contains(expected_text)
}

fn start() {
  simulate.simple(
    init: lustre_admin.init,
    update: lustre_admin.update,
    view: lustre_admin.view,
  )
  |> simulate.start("")
}

fn click_nav(simulation, label: String) {
  simulation
  |> simulate.click(on: query.element(
    matching: query.tag("button")
    |> query.and(query.text(label)),
  ))
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
