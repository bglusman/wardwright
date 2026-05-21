import gleam/list
import gleam/string
import lustre
import lustre/attribute.{
  attribute, class, disabled, id, name, placeholder, rows, selected, type_,
  value,
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

type TranscriptEvent =
  #(String, String, String, String, String, String)

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
    transcript_session_id: String,
    transcript_status: String,
    transcript_error: String,
    selected_fork_point: String,
    policy_overlay_json: String,
    transcript_events: List(TranscriptEvent),
    fork_replay_status: String,
    fork_replay_error: String,
    fork_replay_facts: List(ReplayFact),
    fork_continue_status: String,
    fork_continue_error: String,
    fork_continue_facts: List(ReplayFact),
    counterfactual_status: String,
    counterfactual_error: String,
    counterfactual_facts: List(ReplayFact),
    storage_note: String,
  )
}

pub type Msg {
  ReceiptChanged(String)
  PatternChanged(String)
  ScenarioTitleChanged(String)
  ImportReceipt
  ReplayReceipt
  RunCounterfactualDemo
  LoadTranscript
  SelectForkPoint(String)
  PolicyOverlayChanged(String)
  ReplayToForkPoint
  ForkAndContinue
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

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "counterfactual_facts")
fn external_counterfactual_facts() -> List(ReplayFact)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_policy_overlay_json")
fn external_default_policy_overlay_json() -> String

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "load_transcript_for_receipt")
fn external_load_transcript_for_receipt(
  receipt_id: String,
) -> #(Bool, String, String, String, List(TranscriptEvent))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "replay_to_fork_point")
fn external_replay_to_fork_point(
  session_id: String,
  fork_point: String,
) -> #(Bool, String, List(ReplayFact))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "fork_and_continue_from_point")
fn external_fork_and_continue_from_point(
  session_id: String,
  fork_point: String,
  policy_overlay_json: String,
) -> #(Bool, String, List(ReplayFact))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "run_counterfactual_demo")
fn external_run_counterfactual_demo() -> #(
  Bool,
  String,
  String,
  List(ReplayFact),
)

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
    transcript_session_id: "",
    transcript_status: "",
    transcript_error: "",
    selected_fork_point: "",
    policy_overlay_json: external_default_policy_overlay_json(),
    transcript_events: [],
    fork_replay_status: "",
    fork_replay_error: "",
    fork_replay_facts: [],
    fork_continue_status: "",
    fork_continue_error: "",
    fork_continue_facts: [],
    counterfactual_status: "",
    counterfactual_error: "",
    counterfactual_facts: external_counterfactual_facts(),
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
        transcript_session_id: "",
        transcript_status: "",
        transcript_error: "",
        selected_fork_point: "",
        policy_overlay_json: external_default_policy_overlay_json(),
        transcript_events: [],
        fork_replay_status: "",
        fork_replay_error: "",
        fork_replay_facts: [],
        fork_continue_status: "",
        fork_continue_error: "",
        fork_continue_facts: [],
        counterfactual_status: "",
        counterfactual_error: "",
        counterfactual_facts: external_counterfactual_facts(),
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

    RunCounterfactualDemo -> {
      let #(ok, message, receipt_id, facts) = external_run_counterfactual_demo()

      case ok {
        True ->
          Model(
            ..model,
            receipt_id: receipt_id,
            transcript_session_id: "",
            transcript_status: "",
            transcript_error: "",
            selected_fork_point: "",
            policy_overlay_json: external_default_policy_overlay_json(),
            transcript_events: [],
            fork_replay_status: "",
            fork_replay_error: "",
            fork_replay_facts: [],
            fork_continue_status: "",
            fork_continue_error: "",
            fork_continue_facts: [],
            counterfactual_status: message,
            counterfactual_error: "",
            counterfactual_facts: facts,
          )
        False ->
          Model(
            ..model,
            counterfactual_status: "",
            counterfactual_error: message,
            counterfactual_facts: external_counterfactual_facts(),
          )
      }
    }

    LoadTranscript -> {
      let #(ok, message, session_id, fork_point, events) =
        external_load_transcript_for_receipt(model.receipt_id)

      case ok {
        True ->
          Model(
            ..model,
            transcript_session_id: session_id,
            transcript_status: message,
            transcript_error: "",
            selected_fork_point: fork_point,
            transcript_events: events,
            fork_replay_status: "",
            fork_replay_error: "",
            fork_replay_facts: [],
            fork_continue_status: "",
            fork_continue_error: "",
            fork_continue_facts: [],
          )
        False ->
          Model(
            ..model,
            transcript_session_id: "",
            transcript_status: "",
            transcript_error: message,
            selected_fork_point: "",
            policy_overlay_json: external_default_policy_overlay_json(),
            transcript_events: [],
            fork_replay_status: "",
            fork_replay_error: "",
            fork_replay_facts: [],
            fork_continue_status: "",
            fork_continue_error: "",
            fork_continue_facts: [],
          )
      }
    }

    SelectForkPoint(fork_point) ->
      Model(
        ..model,
        selected_fork_point: fork_point,
        fork_replay_status: "",
        fork_replay_error: "",
        fork_replay_facts: [],
        fork_continue_status: "",
        fork_continue_error: "",
        fork_continue_facts: [],
      )

    PolicyOverlayChanged(policy_overlay_json) ->
      Model(
        ..model,
        policy_overlay_json: policy_overlay_json,
        fork_continue_status: "",
        fork_continue_error: "",
        fork_continue_facts: [],
      )

    ReplayToForkPoint -> {
      let #(ok, message, facts) =
        external_replay_to_fork_point(
          model.transcript_session_id,
          model.selected_fork_point,
        )

      case ok {
        True ->
          Model(
            ..model,
            fork_replay_status: message,
            fork_replay_error: "",
            fork_replay_facts: facts,
          )
        False ->
          Model(
            ..model,
            fork_replay_status: "",
            fork_replay_error: message,
            fork_replay_facts: [],
          )
      }
    }

    ForkAndContinue -> {
      let #(ok, message, facts) =
        external_fork_and_continue_from_point(
          model.transcript_session_id,
          model.selected_fork_point,
          model.policy_overlay_json,
        )

      case ok {
        True ->
          Model(
            ..model,
            fork_continue_status: message,
            fork_continue_error: "",
            fork_continue_facts: facts,
          )
        False ->
          Model(
            ..model,
            fork_continue_status: "",
            fork_continue_error: message,
            fork_continue_facts: [],
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
    transcript_card(model),
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
        text("Pick a fork point before the unsafe tool call."),
      ]),
      html.li([], [text("Apply a policy overlay, then continue the fork.")]),
      html.li([], [
        text("Compare original and forked outcomes with receipt evidence."),
      ]),
    ]),
    html.div([class("button-row")], [
      button.button(
        [
          button.variant(button.Default),
          type_("button"),
          event.on_click(RunCounterfactualDemo),
        ],
        [text("Run deterministic demo")],
      ),
      button.button(
        [
          button.variant(button.Ghost),
          type_("button"),
          event.on_click(LoadTranscript),
        ],
        [text("Load selected receipt")],
      ),
    ]),
    status_text(model.counterfactual_status, model.counterfactual_error),
    counterfactual_facts(model),
    html.small([class("debugger-note")], [
      text(
        "The demo runs a scripted failed agent session through Wardwright, records a transcript, replays to the unsafe edit cursor, forks with a read-before-edit policy overlay, and continues deterministically. Free-form cursor selection and policy editing are still not wired. Selected receipt: "
        <> blank_default(model.receipt_id, "none selected")
        <> ".",
      ),
    ]),
  ])
}

fn transcript_card(model: Model) -> Element(Msg) {
  html.article([class("panel transcript-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Transcript inspector")]),
        html.strong([], [text(transcript_heading(model))]),
      ]),
      badge.badge([badge.variant(badge.Outline)], [text("fork points")]),
    ]),
    html.div([class("button-row")], [
      button.button(
        [
          button.variant(button.Default),
          type_("button"),
          event.on_click(LoadTranscript),
        ],
        [text("Load transcript")],
      ),
      button.button(
        [
          button.variant(button.Ghost),
          type_("button"),
          event.on_click(ReplayToForkPoint),
          disabled(model.selected_fork_point == ""),
        ],
        [text("Replay to fork point")],
      ),
      button.button(
        [
          button.variant(button.Default),
          type_("button"),
          event.on_click(ForkAndContinue),
          disabled(model.selected_fork_point == ""),
        ],
        [text("Fork and continue")],
      ),
    ]),
    status_text(model.transcript_status, model.transcript_error),
    fork_point_summary(model),
    transcript_events(model),
    policy_overlay_editor(model),
    status_text(model.fork_replay_status, model.fork_replay_error),
    replay_point_facts(model),
    status_text(model.fork_continue_status, model.fork_continue_error),
    fork_continue_facts(model),
  ])
}

fn transcript_heading(model: Model) -> String {
  case model.transcript_session_id {
    "" -> "Choose a receipt, then load its session"
    session_id -> session_id
  }
}

fn fork_point_summary(model: Model) -> Element(Msg) {
  case model.selected_fork_point {
    "" ->
      html.small([class("debugger-note")], [
        text(
          "No fork point selected yet. Load a transcript to choose where replay should stop.",
        ),
      ])
    fork_point ->
      html.small([class("debugger-note")], [
        text("Selected fork point: before event " <> fork_point <> "."),
      ])
  }
}

fn transcript_events(model: Model) -> Element(Msg) {
  case model.transcript_events {
    [] ->
      html.div([class("transcript-empty")], [
        text("No transcript loaded."),
      ])
    events ->
      html.div(
        [class("transcript-events")],
        list.map(events, transcript_event(model.selected_fork_point)),
      )
  }
}

fn transcript_event(selected_fork_point: String) {
  fn(event_row: TranscriptEvent) -> Element(Msg) {
    let #(fork_point, sequence, event_type, label, detail, recommendation) =
      event_row

    html.button(
      [
        type_("button"),
        class(case selected_fork_point == fork_point {
          True -> "transcript-event selected"
          False -> "transcript-event"
        }),
        event.on_click(SelectForkPoint(fork_point)),
      ],
      [
        html.span([class("transcript-event-sequence")], [
          text("#" <> sequence),
        ]),
        html.span([class("transcript-event-main")], [
          html.strong([], [text(label)]),
          html.small([], [text(detail)]),
          html.small([class("transcript-event-recommendation")], [
            text(recommendation),
          ]),
        ]),
        html.span([class("transcript-event-type")], [text(event_type)]),
      ],
    )
  }
}

fn counterfactual_facts(model: Model) -> Element(Msg) {
  case model.counterfactual_facts {
    [] -> html.div([], [])
    facts -> html.dl([class("debugger-facts")], list.map(facts, fact))
  }
}

fn replay_facts(model: Model) -> Element(Msg) {
  case model.replay_facts {
    [] -> html.div([], [])
    facts -> html.dl([class("debugger-facts")], list.map(facts, fact))
  }
}

fn policy_overlay_editor(model: Model) -> Element(Msg) {
  html.label([class("field policy-overlay-field")], [
    html.span([], [text("Policy overlay JSON")]),
    html.textarea(
      [
        id("control_policy_overlay_json"),
        name("control_policy_overlay_json"),
        rows(8),
        value(model.policy_overlay_json),
        event.on_input(PolicyOverlayChanged),
      ],
      model.policy_overlay_json,
    ),
    html.small([class("debugger-note")], [
      text(
        "Fork and continue validates this overlay before applying it to the selected transcript point.",
      ),
    ]),
  ])
}

fn replay_point_facts(model: Model) -> Element(Msg) {
  case model.fork_replay_facts {
    [] -> html.div([], [])
    facts -> html.dl([class("debugger-facts")], list.map(facts, fact))
  }
}

fn fork_continue_facts(model: Model) -> Element(Msg) {
  case model.fork_continue_facts {
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
  .transcript-card {
    display: grid;
    gap: 14px;
  }
  .control-debugger-workspace .panel-heading {
    flex-wrap: wrap;
    gap: 8px;
  }
  .control-debugger-workspace .panel-heading > div {
    display: grid;
    gap: 4px;
    min-width: 0;
  }
  .control-debugger-workspace .panel-heading strong {
    display: block;
    line-height: 1.1;
    overflow-wrap: anywhere;
  }
  .debugger-note {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.4;
  }
  .debugger-facts {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(132px, 1fr));
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
    overflow-wrap: anywhere;
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
  .transcript-empty {
    padding: 14px;
    border: 1px dashed var(--border);
    border-radius: 8px;
    color: var(--muted-foreground);
    font-size: 13px;
    font-weight: 700;
  }
  .transcript-events {
    display: grid;
    gap: 8px;
  }
  .policy-overlay-field textarea {
    min-height: 150px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace;
    font-size: 12px;
    line-height: 1.45;
    resize: vertical;
  }
  .transcript-event {
    width: 100%;
    display: grid;
    grid-template-columns: 48px minmax(0, 1fr) minmax(110px, max-content);
    gap: 12px;
    align-items: start;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
    color: var(--foreground);
    text-align: left;
    cursor: pointer;
  }
  .transcript-event.selected {
    border-color: #16605a;
    box-shadow: 0 0 0 2px rgba(22, 96, 90, 0.14);
  }
  .transcript-event-sequence {
    color: var(--muted-foreground);
    font-weight: 800;
  }
  .transcript-event-main {
    display: grid;
    gap: 3px;
    min-width: 0;
  }
  .transcript-event-main small {
    color: var(--muted-foreground);
    font-weight: 700;
    overflow-wrap: anywhere;
  }
  .transcript-event-recommendation {
    color: #16605a !important;
  }
  .transcript-event-type {
    color: var(--muted-foreground);
    font-size: 11px;
    font-weight: 800;
    text-transform: uppercase;
    overflow-wrap: anywhere;
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
    .transcript-event {
      grid-template-columns: 1fr;
    }
  }
  "
}
