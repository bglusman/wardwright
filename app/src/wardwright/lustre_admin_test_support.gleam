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

pub fn ux_exploration_uses_live_model_controls(
  concept_id: String,
  model_id: String,
  expected_text: String,
) -> Bool {
  start("ux_exploration:" <> concept_id <> ":" <> model_id)
  |> view_contains(expected_text)
}

pub fn ux_exploration_theme_switch_updates_sidebar(
  model_id: String,
  theme_label: String,
) -> Bool {
  start("ux_exploration:holistic-control-room:" <> model_id)
  |> simulate.click(on: query.element(
    matching: query.tag("button")
    |> query.and(query.text(theme_label)),
  ))
  |> view_contains("<code>" <> theme_label <> "</code>")
}

pub fn ux_exploration_exposes_full_admin_recovery_links(
  concept_id: String,
  model_id: String,
) -> Bool {
  let view =
    start("ux_exploration:" <> concept_id <> ":" <> model_id)
    |> simulate.view
    |> element.to_string

  string.contains(view, "/admin?model=" <> model_id)
  && contains_href(view, "/admin?view=model_access&model=" <> model_id)
  && contains_href(view, "/admin?view=control_debugger&model=" <> model_id)
  && string.contains(view, "#ux-integrations")
  && string.contains(view, "#ux-release")
}

fn contains_href(view: String, href: String) -> Bool {
  string.contains(view, href)
  || string.contains(view, string.replace(href, "&", "&amp;"))
}

pub fn ux_exploration_toggles_server_tool(
  concept_id: String,
  model_id: String,
  action_label: String,
  expected_text: String,
) -> Bool {
  start("ux_exploration:" <> concept_id <> ":" <> model_id)
  |> simulate.click(on: query.element(
    matching: query.tag("button")
    |> query.and(query.text(action_label)),
  ))
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
