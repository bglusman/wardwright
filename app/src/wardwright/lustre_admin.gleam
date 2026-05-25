import gleam/list
import gleam/string
import lustre
import lustre/attribute.{class}
import lustre/element.{type Element, map}
import lustre/element/html
import wardwright/lustre_control_debugger
import wardwright/lustre_model_access
import wardwright/lustre_shell
import wardwright/lustre_ux_exploration
import wardwright/lustre_workbench

pub type Model {
  Model(
    page: lustre_shell.Page,
    workbench: lustre_workbench.Model,
    model_access: lustre_model_access.Model,
    control_debugger: lustre_control_debugger.Model,
    ux_exploration: lustre_ux_exploration.Model,
  )
}

pub type Msg {
  WorkbenchMsg(lustre_workbench.Msg)
  ModelAccessMsg(lustre_model_access.Msg)
  ControlDebuggerMsg(lustre_control_debugger.Msg)
  UXExplorationMsg(lustre_ux_exploration.Msg)
}

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(flags: String) -> Model {
  let page = selected_page(flags)
  let selected_model = selected_model(flags)

  Model(
    page: page,
    workbench: lustre_workbench.init(selected_model),
    model_access: lustre_model_access.init(selected_model),
    control_debugger: lustre_control_debugger.init(Nil),
    ux_exploration: lustre_ux_exploration.init(flags),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
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
    ControlDebuggerMsg(msg) -> {
      let control_debugger =
        lustre_control_debugger.update(model.control_debugger, msg)

      Model(..model, control_debugger: control_debugger)
    }
    UXExplorationMsg(msg) -> {
      let ux_exploration =
        lustre_ux_exploration.update(model.ux_exploration, msg)

      Model(..model, ux_exploration: ux_exploration)
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
      current_model_id(model),
      "Admin",
      sidebar_controls(model),
    ),
    case model.page {
      lustre_shell.Workbench ->
        map(lustre_workbench.workspace(model.workbench), WorkbenchMsg)
      lustre_shell.ModelAccess ->
        map(lustre_model_access.workspace(model.model_access), ModelAccessMsg)
      lustre_shell.ControlDebugger ->
        map(
          lustre_control_debugger.workspace(model.control_debugger),
          ControlDebuggerMsg,
        )
      lustre_shell.UXExploration ->
        map(
          lustre_ux_exploration.workspace(model.ux_exploration),
          UXExplorationMsg,
        )
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
    lustre_shell.ControlDebugger -> []
    lustre_shell.UXExploration ->
      model.ux_exploration
      |> lustre_ux_exploration.sidebar_controls
      |> list.map(fn(control) { map(control, UXExplorationMsg) })
  }
}

fn current_model_id(model: Model) -> String {
  case model.page {
    lustre_shell.Workbench -> model.workbench.model_id
    lustre_shell.ModelAccess -> model.model_access.model_id
    lustre_shell.ControlDebugger -> model.workbench.model_id
    lustre_shell.UXExploration -> model.ux_exploration.model_access.model_id
  }
}

fn selected_page(flags: String) -> lustre_shell.Page {
  case flags {
    "control_debugger" -> lustre_shell.ControlDebugger
    "model_access" -> lustre_shell.ModelAccess
    "ux_exploration" -> lustre_shell.UXExploration
    _ ->
      case string.split(flags, ":") {
        ["model_access", _model_id] -> lustre_shell.ModelAccess
        ["control_debugger", _model_id] -> lustre_shell.ControlDebugger
        ["ux_exploration", _concept_id] -> lustre_shell.UXExploration
        ["ux_exploration", _concept_id, _model_id] -> lustre_shell.UXExploration
        _ -> lustre_shell.Workbench
      }
  }
}

fn selected_model(flags: String) -> String {
  case string.split(flags, ":") {
    ["model_access", model_id] -> model_id
    ["control_debugger", model_id] -> model_id
    ["workbench", model_id] -> model_id
    ["ux_exploration", _concept_id, model_id] -> model_id
    _ -> ""
  }
}

fn styles() -> String {
  lustre_workbench.styles()
  <> lustre_model_access.styles()
  <> lustre_control_debugger.styles()
  <> lustre_ux_exploration.styles()
  <> "
  .admin-app {
    min-height: 100vh;
    display: grid;
    grid-template-columns: minmax(260px, 320px) minmax(0, 1fr);
    background: var(--background);
    color: var(--foreground);
  }
  @media (max-width: 860px) {
    .admin-app {
      grid-template-columns: 1fr;
    }
  }
  "
}
