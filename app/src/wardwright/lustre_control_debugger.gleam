import gleam/list
import gleam/string
import lustre
import lustre/attribute.{
  attribute, class, id, name, placeholder, selected, type_, value,
}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event
import ui/badge
import ui/button
import ui/select as select_ui
import wardwright/lustre_shell

type PatternOption =
  #(String, String, String, String)

type ReceiptOption =
  #(String, String, String, String)

pub type Model {
  Model(
    receipt_id: String,
    pattern_id: String,
    scenario_title: String,
    import_status: String,
    import_error: String,
    imported_fixture_id: String,
    replay_status: String,
    replay_error: String,
    replay_schema: String,
    replay_original_status: String,
    replay_selected_model: String,
  )
}

pub type Msg {
  ReceiptChanged(String)
  PatternChanged(String)
  ScenarioTitleChanged(String)
  ImportReceipt
  ReplayReceipt
}

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "pattern_options")
fn external_pattern_options() -> List(PatternOption)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_pattern_id")
fn external_default_pattern_id() -> String

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "receipt_options")
fn external_receipt_options() -> List(ReceiptOption)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_receipt_id")
fn external_default_receipt_id() -> String

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "import_receipt_scenario")
fn external_import_receipt_scenario(
  pattern_id: String,
  receipt_id: String,
  title: String,
) -> #(Bool, String, String)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "replay_receipt")
fn external_replay_receipt(
  receipt_id: String,
) -> #(Bool, String, String, String, String)

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(_flags: Nil) -> Model {
  Model(
    receipt_id: external_default_receipt_id(),
    pattern_id: external_default_pattern_id(),
    scenario_title: "",
    import_status: "",
    import_error: "",
    imported_fixture_id: "",
    replay_status: "",
    replay_error: "",
    replay_schema: "",
    replay_original_status: "",
    replay_selected_model: "",
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    ReceiptChanged(receipt_id) ->
      Model(
        ..model,
        receipt_id: receipt_id,
        import_status: "",
        import_error: "",
        replay_status: "",
        replay_error: "",
      )

    PatternChanged(pattern_id) ->
      Model(
        ..model,
        pattern_id: pattern_id,
        import_status: "",
        import_error: "",
      )

    ScenarioTitleChanged(title) -> Model(..model, scenario_title: title)

    ImportReceipt -> {
      let #(ok, message, fixture_id) =
        external_import_receipt_scenario(
          model.pattern_id,
          model.receipt_id,
          model.scenario_title,
        )

      case ok {
        True ->
          Model(
            ..model,
            import_status: message,
            import_error: "",
            imported_fixture_id: fixture_id,
          )
        False -> Model(..model, import_status: "", import_error: message)
      }
    }

    ReplayReceipt -> {
      let #(ok, message, schema, original_status, selected_model) =
        external_replay_receipt(model.receipt_id)

      case ok {
        True ->
          Model(
            ..model,
            replay_status: message,
            replay_error: "",
            replay_schema: schema,
            replay_original_status: original_status,
            replay_selected_model: selected_model,
          )
        False -> Model(..model, replay_status: "", replay_error: message)
      }
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("control-debugger-app")], [
    html.style([], styles()),
    lustre_shell.sidebar(lustre_shell.ControlDebugger, "Control Debugger", []),
    workspace(model),
  ])
}

pub fn workspace(model: Model) -> Element(Msg) {
  html.main([class("workspace control-debugger-workspace")], [
    html.header([class("topbar")], [
      html.div([], [
        html.h1([], [text("Control debugger")]),
        html.p([], [
          text(
            "Turn recorded receipts into replay evidence and deterministic policy replay without resuming provider calls.",
          ),
        ]),
      ]),
    ]),
    panel(model),
  ])
}

pub fn panel(model: Model) -> Element(Msg) {
  html.section([class("control-debugger-panel")], [
    receipt_picker(model),
    html.div([class("debugger-actions")], [
      import_card(model),
      replay_card(model),
    ]),
  ])
}

fn receipt_picker(model: Model) -> Element(Msg) {
  html.article([class("panel debugger-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Recorded receipt")]),
        html.strong([], [text(blank_default(model.receipt_id, "none selected"))]),
      ]),
      badge.badge([badge.variant(badge.Outline)], [text("metadata only")]),
    ]),
    labeled_select(
      "Recent receipt",
      "control_receipt_id",
      model.receipt_id,
      receipt_options(model.receipt_id),
      ReceiptChanged,
    ),
    html.label([class("field")], [
      html.span([], [text("Receipt id")]),
      html.input([
        id("control_receipt_id_text"),
        name("control_receipt_id_text"),
        placeholder("rcpt_example"),
        value(model.receipt_id),
        event.on_input(ReceiptChanged),
      ]),
    ]),
  ])
}

fn import_card(model: Model) -> Element(Msg) {
  html.article([class("panel debugger-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Fork from receipt")]),
        html.strong([], [text("Import replay evidence")]),
      ]),
      badge.badge([badge.variant(badge.Secondary)], [text("scenario")]),
    ]),
    labeled_select(
      "Policy projection",
      "control_pattern_id",
      model.pattern_id,
      pattern_options(model.pattern_id),
      PatternChanged,
    ),
    html.label([class("field")], [
      html.span([], [text("Scenario title")]),
      html.input([
        id("control_scenario_title"),
        name("control_scenario_title"),
        placeholder("Forked receipt replay"),
        value(model.scenario_title),
        event.on_input(ScenarioTitleChanged),
      ]),
    ]),
    button.button(
      [
        button.variant(button.Default),
        type_("button"),
        event.on_click(ImportReceipt),
      ],
      [text("Import receipt")],
    ),
    html.small([class("debugger-note")], [
      text(
        "The imported scenario preserves recorded facts. It does not claim the provider would make the same future choices after a policy change.",
      ),
    ]),
    status_text(model.import_status, model.import_error),
  ])
}

fn replay_card(model: Model) -> Element(Msg) {
  html.article([class("panel debugger-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("VCR replay")]),
        html.strong([], [text("Deterministic metadata replay")]),
      ]),
      badge.badge([badge.variant(badge.Outline)], [text("no provider call")]),
    ]),
    button.button(
      [
        button.variant(button.Ghost),
        type_("button"),
        event.on_click(ReplayReceipt),
      ],
      [text("Replay receipt")],
    ),
    html.small([class("debugger-note")], [
      text(
        "Replay v0 checks the recorded policy, route, and final metadata. Live counterfactual replay is a later contract.",
      ),
    ]),
    status_text(model.replay_status, model.replay_error),
    replay_facts(model),
  ])
}

fn replay_facts(model: Model) -> Element(Msg) {
  case
    model.replay_schema == ""
    && model.replay_original_status == ""
    && model.replay_selected_model == ""
  {
    True -> html.div([], [])
    False ->
      html.dl([class("debugger-facts")], [
        fact("Schema", model.replay_schema),
        fact("Original status", model.replay_original_status),
        fact("Selected model", model.replay_selected_model),
      ])
  }
}

fn fact(label: String, value_text: String) -> Element(Msg) {
  html.div([], [
    html.dt([], [text(label)]),
    html.dd([], [text(blank_default(value_text, "unknown"))]),
  ])
}

fn status_text(status: String, error: String) -> Element(Msg) {
  case status, error {
    "", "" -> html.span([], [])
    _, "" -> html.strong([class("fixture-status")], [text(status)])
    "", _ -> html.strong([class("fixture-error")], [text(error)])
    _, _ -> html.strong([class("fixture-error")], [text(error)])
  }
}

fn labeled_select(
  label: String,
  control_id: String,
  selected_id: String,
  options: List(Element(Msg)),
  to_msg: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([class("field"), attribute("for", control_id)], [
    html.span([], [text(label)]),
    select_ui.select(
      [
        attribute("aria-label", label),
        id(control_id),
        name(control_id),
        value(selected_id),
        event.on_change(to_msg),
      ],
      options,
    ),
  ])
}

fn pattern_options(selected_id: String) -> List(Element(Msg)) {
  external_pattern_options()
  |> list.map(fn(option) {
    let #(option_id, title, category, _) = option
    select_ui.option(
      [selected(option_id == selected_id)],
      title <> " - " <> category,
      option_id,
    )
  })
}

fn receipt_options(selected_id: String) -> List(Element(Msg)) {
  let options =
    external_receipt_options()
    |> list.map(fn(option) {
      let #(receipt_id, label, model_id, status) = option
      select_ui.option(
        [selected(receipt_id == selected_id)],
        label <> " - " <> model_id <> " - " <> status,
        receipt_id,
      )
    })

  case options {
    [] -> [
      select_ui.option([selected(True)], "No receipts recorded yet", ""),
    ]
    _ -> options
  }
}

fn blank_default(value_text: String, fallback: String) -> String {
  case string.trim(value_text) {
    "" -> fallback
    trimmed -> trimmed
  }
}

pub fn styles() -> String {
  lustre_shell.styles() <> "
  .control-debugger-app {
    min-height: 100vh;
    display: grid;
    grid-template-columns: minmax(260px, 320px) minmax(0, 1fr);
    background: var(--background);
    color: var(--foreground);
  }
  .control-debugger-workspace {
    gap: 18px;
  }
  .control-debugger-panel {
    display: grid;
    gap: 14px;
  }
  .debugger-actions {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
  }
  .debugger-card {
    display: grid;
    gap: 12px;
  }
  .debugger-note {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.4;
  }
  .debugger-facts {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 8px;
    margin: 0;
  }
  .debugger-facts div {
    display: grid;
    gap: 4px;
    padding: 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  .debugger-facts dt {
    color: var(--muted-foreground);
    font-size: 11px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .debugger-facts dd {
    margin: 0;
    font-weight: 800;
  }
  .fixture-status {
    color: #16605a;
    font-size: 13px;
  }
  .fixture-error {
    color: var(--destructive);
    font-size: 13px;
  }
  @media (max-width: 860px) {
    .control-debugger-app, .debugger-actions {
      grid-template-columns: 1fr;
    }
  }
  "
}
