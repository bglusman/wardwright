import gleam/list
import gleam/string
import lustre
import lustre/attribute.{
  attribute, class, disabled, id, name, placeholder, selected, type_, value,
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

type ReplayFact =
  #(String, String)

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
    replay_facts: List(ReplayFact),
    storage_note: String,
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
) -> #(Bool, String, List(ReplayFact))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "storage_note")
fn external_storage_note() -> String

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
    replay_facts: [],
    storage_note: external_storage_note(),
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
        replay_facts: [],
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
      let #(ok, message, facts) = external_replay_receipt(model.receipt_id)

      case ok {
        True ->
          Model(
            ..model,
            replay_status: message,
            replay_error: "",
            replay_facts: facts,
          )
        False ->
          Model(
            ..model,
            replay_status: "",
            replay_error: message,
            replay_facts: [],
          )
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
            "Inspect recorded agent calls, explain what Wardwright decided, and save useful failures as simulator cases.",
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
      counterfactual_card(model),
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
      badge.badge([badge.variant(badge.Outline)], [text("receipt VCR")]),
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
    html.small([class("debugger-note")], [
      text(model.storage_note),
    ]),
  ])
}

fn import_card(model: Model) -> Element(Msg) {
  html.article([class("panel debugger-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Create simulator case")]),
        html.strong([], [text("Save receipt evidence")]),
      ]),
      badge.badge([badge.variant(badge.Secondary)], [text("scenario")]),
    ]),
    labeled_select(
      "Workbench pattern",
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
      [text("Save scenario")],
    ),
    html.small([class("debugger-note")], [
      text(
        "This creates a pinned simulator case from recorded trace facts. The saved case uses the simulator case store shown above.",
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
        html.strong([], [text("Explain what happened")]),
      ]),
      badge.badge([badge.variant(badge.Outline)], [text("no provider call")]),
    ]),
    button.button(
      [
        button.variant(button.Ghost),
        type_("button"),
        event.on_click(ReplayReceipt),
      ],
      [text("Explain receipt")],
    ),
    html.small([class("debugger-note")], [
      text(
        "Replay checks stored policy and route facts. Full-session receipts can also carry payloads for later live or simulated replay; the receipt store above is where those payloads live.",
      ),
    ]),
    status_text(model.replay_status, model.replay_error),
    replay_facts(model),
  ])
}

fn counterfactual_card(model: Model) -> Element(Msg) {
  html.article([class("panel debugger-card counterfactual-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Counterfactual fork")]),
        html.strong([], [text("Replay, change policy, continue")]),
      ]),
      badge.badge([badge.variant(badge.Secondary)], [text("contract")]),
    ]),
    html.ol([class("debugger-steps")], [
      html.li([], [
        text("Load a full-session transcript for the selected receipt."),
      ]),
      html.li([], [
        text("Pick the failed event cursor before the unsafe tool call."),
      ]),
      html.li([], [text("Apply a policy overlay, then continue the fork.")]),
      html.li([], [
        text("Compare original and forked outcomes with receipt evidence."),
      ]),
    ]),
    button.button(
      [
        button.variant(button.Ghost),
        type_("button"),
        disabled(True),
      ],
      [text("Fork from receipt")],
    ),
    html.small([class("debugger-note")], [
      text(
        "Not active yet. This needs opt-in transcript recording, append-only transcript storage, replay-to-cursor, fork, continuation, and comparison APIs. Selected receipt: "
        <> blank_default(model.receipt_id, "none selected")
        <> ".",
      ),
    ]),
  ])
}

fn replay_facts(model: Model) -> Element(Msg) {
  case model.replay_facts {
    [] -> html.div([], [])
    facts -> html.dl([class("debugger-facts")], list.map(facts, fact))
  }
}

fn fact(replay_fact: ReplayFact) -> Element(Msg) {
  let #(label, value_text) = replay_fact

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
    grid-template-columns: repeat(3, minmax(0, 1fr));
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
  .debugger-steps {
    display: grid;
    gap: 6px;
    margin: 0;
    padding-left: 18px;
    color: var(--muted-foreground);
    font-size: 13px;
    font-weight: 700;
    line-height: 1.35;
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
