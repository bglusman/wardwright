import gleam/list
import gleam/string
import lustre
import lustre/attribute.{class}
import lustre/element.{type Element, map}
import lustre/element/html
import wardwright/lustre_model_access
import wardwright/lustre_shell
import wardwright/lustre_workbench

pub type Model {
  Model(
    page: lustre_shell.Page,
    workbench: lustre_workbench.Model,
    model_access: lustre_model_access.Model,
  )
}

pub type Msg {
  Navigate(lustre_shell.Page)
  WorkbenchMsg(lustre_workbench.Msg)
  ModelAccessMsg(lustre_model_access.Msg)
}

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(flags: String) -> Model {
  let page = selected_page(flags)
  let selected_model = selected_model(flags)

  Model(
    page: page,
    workbench: lustre_workbench.init(Nil),
    model_access: lustre_model_access.init(selected_model),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Navigate(page) -> Model(..model, page: page)
    WorkbenchMsg(msg) -> {
      let workbench = lustre_workbench.update(model.workbench, msg)

      Model(
        ..model,
        workbench: workbench,
        model_access: sync_model_access(model.model_access, msg),
      )
    }
    ModelAccessMsg(msg) -> {
      let model_access = lustre_model_access.update(model.model_access, msg)

      Model(
        ..model,
        workbench: sync_workbench(model.workbench, msg),
        model_access: model_access,
      )
    }
  }
}

fn sync_model_access(
  model_access: lustre_model_access.Model,
  msg: lustre_workbench.Msg,
) -> lustre_model_access.Model {
  case msg {
    lustre_workbench.ModelChanged(model_id) ->
      lustre_model_access.init(model_id)
    _ -> model_access
  }
}

fn sync_workbench(
  workbench: lustre_workbench.Model,
  msg: lustre_model_access.Msg,
) -> lustre_workbench.Model {
  case msg {
    lustre_model_access.ModelChanged(model_id) ->
      lustre_workbench.update(
        workbench,
        lustre_workbench.ModelChanged(model_id),
      )
    _ -> workbench
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("admin-app")], [
    html.style([], styles()),
    lustre_shell.admin_sidebar(
      model.page,
      "Admin",
      sidebar_controls(model),
      Navigate,
    ),
    case model.page {
      lustre_shell.Workbench ->
        map(lustre_workbench.workspace(model.workbench), WorkbenchMsg)
      lustre_shell.ModelAccess ->
        map(lustre_model_access.workspace(model.model_access), ModelAccessMsg)
    },
  ])
}

fn sidebar_controls(model: Model) -> List(Element(Msg)) {
  case model.page {
    lustre_shell.Workbench ->
      model.workbench
      |> lustre_workbench.sidebar_controls
      |> list.map(fn(control) { map(control, WorkbenchMsg) })
    lustre_shell.ModelAccess ->
      model.model_access
      |> lustre_model_access.sidebar_controls
      |> list.map(fn(control) { map(control, ModelAccessMsg) })
  }
}

fn selected_page(flags: String) -> lustre_shell.Page {
  case string.starts_with(flags, "model_access") {
    True -> lustre_shell.ModelAccess
    False -> lustre_shell.Workbench
  }
}

fn selected_model(flags: String) -> String {
  case string.split(flags, ":") {
    ["model_access", model_id] -> model_id
    _ -> ""
  }
}

fn styles() -> String {
  lustre_workbench.styles() <> lustre_model_access.styles() <> "
  .admin-app {
    min-height: 100vh;
    display: grid;
    grid-template-columns: minmax(260px, 320px) minmax(0, 1fr);
    background: var(--background);
    color: var(--foreground);
  }
  "
}
