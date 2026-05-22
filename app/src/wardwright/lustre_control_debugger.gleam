import gleam/int
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

type ModelOption =
  #(String, String)

type ExampleOption =
  #(String, String, String)

type HarnessAdapterOption =
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
    example_id: String,
    transcript_session_id: String,
    transcript_status: String,
    transcript_error: String,
    selected_fork_point: String,
    policy_overlay_json: String,
    continuation_mode: String,
    continuation_model_id: String,
    continuation_model_api_key: String,
    harness_adapter_id: String,
    harness_export_status: String,
    harness_export_error: String,
    harness_export_facts: List(ReplayFact),
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
  ExampleChanged(String)
  RecordExampleSession
  LoadTranscript
  SelectForkPoint(String)
  PolicyOverlayChanged(String)
  ContinuationModeChanged(String)
  ContinuationModelChanged(String)
  ContinuationModelApiKeyChanged(String)
  HarnessAdapterChanged(String)
  ExportHarnessTrace
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

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "model_options")
fn external_model_options() -> List(ModelOption)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_live_model_id")
fn external_default_live_model_id() -> String

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "harness_adapter_options")
fn external_harness_adapter_options() -> List(HarnessAdapterOption)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_harness_adapter_id")
fn external_default_harness_adapter_id() -> String

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "export_harness_trace")
fn external_export_harness_trace(
  session_id: String,
  adapter_id: String,
) -> #(Bool, String, List(ReplayFact))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "counterfactual_example_options")
fn external_counterfactual_example_options() -> List(ExampleOption)

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_counterfactual_example_id")
fn external_default_counterfactual_example_id() -> String

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "default_policy_overlay_json_for_example")
fn external_default_policy_overlay_json_for_example(
  example_id: String,
) -> String

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
  continuation_mode: String,
  live_model_id: String,
  model_api_key: String,
) -> #(Bool, String, List(ReplayFact))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "run_counterfactual_example")
fn external_run_counterfactual_example(
  example_id: String,
) -> #(Bool, String, String, List(ReplayFact))

@external(erlang, "Elixir.WardwrightWeb.ControlDebuggerData", "storage_note")
fn external_storage_note() -> String

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(_flags: Nil) -> Model {
  let example_id = external_default_counterfactual_example_id()

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
    example_id: example_id,
    transcript_session_id: "",
    transcript_status: "",
    transcript_error: "",
    selected_fork_point: "",
    policy_overlay_json: external_default_policy_overlay_json_for_example(
      example_id,
    ),
    continuation_mode: "scripted_agent",
    continuation_model_id: external_default_live_model_id(),
    continuation_model_api_key: "",
    harness_adapter_id: external_default_harness_adapter_id(),
    harness_export_status: "",
    harness_export_error: "",
    harness_export_facts: [],
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
  |> reset_transcript_fork_and_counterfactual
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
      |> reset_transcript_fork_and_counterfactual

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

    ExampleChanged(example_id) ->
      Model(..model, example_id: example_id)
      |> reset_transcript_fork_and_counterfactual

    RecordExampleSession -> {
      let #(ok, message, receipt_id, facts) =
        external_run_counterfactual_example(model.example_id)

      case ok {
        True -> {
          let #(loaded, load_message, session_id, fork_point, events) =
            external_load_transcript_for_receipt(receipt_id)

          case loaded {
            True ->
              Model(
                ..reset_transcript_fork_and_counterfactual(model),
                receipt_id: receipt_id,
                transcript_session_id: session_id,
                transcript_status: load_message,
                transcript_error: "",
                selected_fork_point: fork_point,
                transcript_events: events,
                counterfactual_status: message,
                counterfactual_error: "",
                counterfactual_facts: facts,
              )
            False ->
              Model(
                ..reset_transcript_fork_and_counterfactual(model),
                receipt_id: receipt_id,
                transcript_error: load_message,
                counterfactual_status: message,
                counterfactual_error: "",
                counterfactual_facts: facts,
              )
          }
        }
        False ->
          Model(
            ..reset_transcript_fork_and_counterfactual(model),
            counterfactual_error: message,
          )
      }
    }

    LoadTranscript -> {
      let #(ok, message, session_id, fork_point, events) =
        external_load_transcript_for_receipt(model.receipt_id)

      case ok {
        True ->
          Model(
            ..reset_fork_results(model),
            transcript_session_id: session_id,
            transcript_status: message,
            transcript_error: "",
            selected_fork_point: fork_point,
            transcript_events: events,
          )
        False ->
          Model(
            ..reset_transcript_fork_and_counterfactual(model),
            transcript_error: message,
          )
      }
    }

    SelectForkPoint(fork_point) ->
      Model(..reset_fork_results(model), selected_fork_point: fork_point)

    PolicyOverlayChanged(policy_overlay_json) ->
      Model(
        ..reset_continue_results(model),
        policy_overlay_json: policy_overlay_json,
      )

    ContinuationModeChanged(continuation_mode) ->
      Model(
        ..reset_continue_results(model),
        continuation_mode: continuation_mode,
      )

    ContinuationModelChanged(model_id) ->
      Model(..reset_continue_results(model), continuation_model_id: model_id)

    ContinuationModelApiKeyChanged(api_key) ->
      Model(
        ..reset_continue_results(model),
        continuation_model_api_key: api_key,
      )

    HarnessAdapterChanged(adapter_id) ->
      Model(
        ..reset_harness_export_results(model),
        harness_adapter_id: adapter_id,
      )

    ExportHarnessTrace -> {
      let #(ok, message, facts) =
        external_export_harness_trace(
          model.transcript_session_id,
          model.harness_adapter_id,
        )

      case ok {
        True ->
          Model(
            ..model,
            harness_export_status: message,
            harness_export_error: "",
            harness_export_facts: facts,
          )
        False ->
          Model(
            ..model,
            harness_export_status: "",
            harness_export_error: message,
            harness_export_facts: [],
          )
      }
    }

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
          model.continuation_mode,
          model.continuation_model_id,
          model.continuation_model_api_key,
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

fn reset_transcript_fork_and_counterfactual(model: Model) -> Model {
  Model(
    ..model,
    transcript_session_id: "",
    transcript_status: "",
    transcript_error: "",
    selected_fork_point: "",
    policy_overlay_json: external_default_policy_overlay_json_for_example(
      model.example_id,
    ),
    continuation_mode: "scripted_agent",
    continuation_model_id: external_default_live_model_id(),
    continuation_model_api_key: "",
    harness_adapter_id: external_default_harness_adapter_id(),
    harness_export_status: "",
    harness_export_error: "",
    harness_export_facts: [],
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
}

fn reset_fork_results(model: Model) -> Model {
  Model(
    ..model,
    fork_replay_status: "",
    fork_replay_error: "",
    fork_replay_facts: [],
    fork_continue_status: "",
    fork_continue_error: "",
    fork_continue_facts: [],
    harness_export_status: "",
    harness_export_error: "",
    harness_export_facts: [],
  )
}

fn reset_continue_results(model: Model) -> Model {
  Model(
    ..model,
    fork_continue_status: "",
    fork_continue_error: "",
    fork_continue_facts: [],
  )
}

fn reset_harness_export_results(model: Model) -> Model {
  Model(
    ..model,
    harness_export_status: "",
    harness_export_error: "",
    harness_export_facts: [],
  )
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
            "Inspect recorded model sessions, explain what Wardwright decided, and save useful failures as simulator cases.",
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
      harness_adapter_card(model),
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
      text(
        model.storage_note
        <> " Full-session model traffic is listed here after a request carries session_id or run_id metadata.",
      ),
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
        text("Load a full-session trace for the selected receipt."),
      ]),
      html.li([], [
        text("Pick a fork point before the behavior you want to change."),
      ]),
      html.li([], [text("Apply a policy overlay, then continue the fork.")]),
      html.li([], [
        text("Compare original and forked outcomes with receipt evidence."),
      ]),
    ]),
    labeled_select(
      "Example session",
      "control_counterfactual_example",
      model.example_id,
      counterfactual_example_options(model.example_id),
      ExampleChanged,
    ),
    html.div([class("button-row")], [
      button.button(
        [
          button.variant(button.Default),
          type_("button"),
          event.on_click(RecordExampleSession),
        ],
        [text("Record example session")],
      ),
      button.button(
        [
          button.variant(button.Ghost),
          type_("button"),
          event.on_click(LoadTranscript),
        ],
        [text("Load trace for selected receipt")],
      ),
    ]),
    status_text(model.counterfactual_status, model.counterfactual_error),
    counterfactual_facts(model),
    html.small([class("debugger-note")], [
      text(
        "Examples run scripted failed sessions through Wardwright, record session traces with tool calls/results, replay to a selected behavior cursor, fork with an editable policy overlay, and continue deterministically. The trace inspector below can also continue the fork through a selected Wardwright model. Selected receipt: "
        <> blank_default(model.receipt_id, "none selected")
        <> ".",
      ),
    ]),
  ])
}

fn harness_adapter_card(model: Model) -> Element(Msg) {
  html.article([class("panel debugger-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Agent harness export")]),
        html.strong([], [text("Best-effort continuation")]),
      ]),
      badge.badge([badge.variant(badge.Outline)], [text("adapter")]),
    ]),
    labeled_select(
      "Harness adapter",
      "control_harness_adapter_id",
      model.harness_adapter_id,
      harness_adapter_options(model.harness_adapter_id),
      HarnessAdapterChanged,
    ),
    button.button(
      [
        button.variant(button.Ghost),
        type_("button"),
        event.on_click(ExportHarnessTrace),
      ],
      [text("Prepare harness handoff")],
    ),
    html.small([class("debugger-note")], [
      text(
        "Exports the loaded session trace for another agent harness. OpenCode can receive a session JSON import; Claude, Codex, and Pi start as lower-fidelity prompt handoffs unless their native import surface is proven.",
      ),
    ]),
    status_text(model.harness_export_status, model.harness_export_error),
    harness_export_facts(model),
  ])
}

fn transcript_card(model: Model) -> Element(Msg) {
  html.article([class("panel transcript-card")], [
    html.div([class("panel-heading")], [
      html.div([], [
        html.span([], [text("Session trace inspector")]),
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
        [text("Load trace")],
      ),
    ]),
    html.small([class("debugger-note")], [
      text(
        "Use this for recorded example sessions or real full-session receipts from Wardwright gateway traffic. A trace can include model messages, tool calls, tool results, policy decisions, and receipts.",
      ),
    ]),
    status_text(model.transcript_status, model.transcript_error),
    transcript_overview(model),
    transcript_events(model),
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
          "No event selected yet. Load a session trace and choose where replay should stop.",
        ),
      ])
    fork_point ->
      html.small([class("debugger-note")], [
        text(
          "Replay stops before this event; fork and continue starts from the same cursor: "
          <> fork_point
          <> ".",
        ),
      ])
  }
}

fn selected_fork_workbench(model: Model) -> Element(Msg) {
  html.section([class("fork-workbench")], [
    html.div([class("fork-workbench-heading")], [
      html.div([], [
        html.span([], [text("Actions for selected event")]),
        html.strong([], [text(blank_default(model.selected_fork_point, "none"))]),
      ]),
      fork_point_summary(model),
    ]),
    selected_event_context(model),
    html.div([class("fork-action-grid")], [
      replay_action_panel(model),
      continue_action_panel(model),
    ]),
  ])
}

fn selected_event_context(model: Model) -> Element(Msg) {
  case selected_event(model.transcript_events, model.selected_fork_point) {
    Ok(event_row) -> {
      let #(fork_point, sequence, event_type, label, detail, recommendation) =
        event_row

      html.div([class("selected-event-context")], [
        html.div([], [
          html.span([], [text("Selected trace event")]),
          html.strong([], [text("#" <> sequence <> " " <> label)]),
          html.small([], [text(event_type <> " at " <> fork_point)]),
        ]),
        html.div([], [
          html.span([], [text("Recorded evidence")]),
          html.strong([], [text(detail)]),
          html.small([], [text(recommendation)]),
        ]),
        html.div([], [
          html.span([], [text("What changes")]),
          html.strong([], [text(continuation_scope(model.continuation_mode))]),
          html.small([], [
            text(
              "Replay uses recorded evidence only; fork and continue may call the selected runner.",
            ),
          ]),
        ]),
      ])
    }
    Error(_) -> html.div([], [])
  }
}

fn replay_action_panel(model: Model) -> Element(Msg) {
  html.div([class("fork-action-card")], [
    html.div([class("fork-action-heading")], [
      html.strong([], [text("Replay selected point")]),
      html.small([], [text("No provider call")]),
    ]),
    button.button(
      [
        button.variant(button.Ghost),
        type_("button"),
        event.on_click(ReplayToForkPoint),
        disabled(model.selected_fork_point == ""),
      ],
      [text("Replay to fork point")],
    ),
    status_text(model.fork_replay_status, model.fork_replay_error),
    replay_point_facts(model),
  ])
}

fn continue_action_panel(model: Model) -> Element(Msg) {
  html.div([class("fork-action-card continue-card")], [
    html.div([class("fork-action-heading")], [
      html.strong([], [text("Continue from selected point")]),
      html.small([], [text("Uses continuation mode")]),
    ]),
    continuation_controls(model),
    policy_overlay_editor(model),
    button.button(
      [
        button.variant(button.Default),
        type_("button"),
        event.on_click(ForkAndContinue),
        disabled(model.selected_fork_point == ""),
      ],
      [text("Fork and continue")],
    ),
    status_text(model.fork_continue_status, model.fork_continue_error),
    fork_continue_facts(model),
  ])
}

fn transcript_overview(model: Model) -> Element(Msg) {
  case model.transcript_events {
    [] -> html.div([], [])
    events ->
      html.div([class("transcript-overview")], [
        html.div([], [
          html.span([], [text("Events")]),
          html.strong([], [text(int.to_string(list.length(events)))]),
        ]),
        html.div([], [
          html.span([], [text("Selected")]),
          html.strong([], [
            text(selected_event_heading(events, model.selected_fork_point)),
          ]),
        ]),
        html.small([class("debugger-note")], [
          text(
            "Click a timeline event to move the replay cursor. The replay and continuation controls open directly under the selected event.",
          ),
        ]),
      ])
  }
}

fn selected_event_heading(
  events: List(TranscriptEvent),
  selected_fork_point: String,
) -> String {
  case selected_fork_point {
    "" -> "none"
    cursor ->
      case selected_event(events, cursor) {
        Ok(event_row) -> {
          let #(_, sequence, _, label, _, _) = event_row
          "#" <> sequence <> " " <> label
        }
        Error(_) -> "cursor not in transcript"
      }
  }
}

fn selected_event(
  events: List(TranscriptEvent),
  selected_fork_point: String,
) -> Result(TranscriptEvent, Nil) {
  list.find(events, fn(event_row) {
    let #(fork_point, _, _, _, _, _) = event_row
    fork_point == selected_fork_point
  })
}

fn transcript_events(model: Model) -> Element(Msg) {
  case model.transcript_events {
    [] ->
      html.div([class("transcript-empty")], [
        text(transcript_empty_message(model)),
      ])
    events ->
      html.div(
        [class("transcript-events")],
        list.map(events, transcript_event(model)),
      )
  }
}

fn transcript_empty_message(model: Model) -> String {
  case model.transcript_error {
    "" ->
      case model.transcript_status {
        "" ->
          "No session trace loaded yet. Record an example session or choose a full-session receipt, then load its trace."
        _ -> "Trace loaded, but it did not contain any events."
      }
    _ ->
      "Trace did not load. Check the message above and choose a receipt with full-session recording."
  }
}

fn transcript_event(model: Model) {
  fn(event_row: TranscriptEvent) -> Element(Msg) {
    let #(fork_point, sequence, event_type, label, detail, recommendation) =
      event_row

    html.div([class("transcript-event-shell")], [
      html.button(
        [
          type_("button"),
          class(case model.selected_fork_point == fork_point {
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
      ),
      case model.selected_fork_point == fork_point {
        True -> selected_fork_workbench(model)
        False -> html.div([], [])
      },
    ])
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
        "Fork and continue validates this overlay before applying it to the selected trace point.",
      ),
    ]),
  ])
}

fn continuation_controls(model: Model) -> Element(Msg) {
  html.div([class("continuation-controls")], [
    labeled_select(
      "Continuation mode",
      "control_continuation_mode",
      model.continuation_mode,
      continuation_mode_options(model.continuation_mode),
      ContinuationModeChanged,
    ),
    labeled_select(
      "Live Wardwright model",
      "control_live_model_id",
      model.continuation_model_id,
      live_model_options(model.continuation_model_id),
      ContinuationModelChanged,
    ),
    html.label([class("field")], [
      html.span([], [text("Model API key")]),
      html.input([
        id("control_live_model_api_key"),
        name("control_live_model_api_key"),
        placeholder("optional for keyed models"),
        type_("password"),
        value(model.continuation_model_api_key),
        event.on_input(ContinuationModelApiKeyChanged),
      ]),
    ]),
    html.small([class("debugger-note continuation-note")], [
      text(
        "Continuation mode only changes Fork and continue. Replay selected point never calls a provider. The model API key is used for this continuation request and is not saved.",
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

fn harness_export_facts(model: Model) -> Element(Msg) {
  case model.harness_export_facts {
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

fn counterfactual_example_options(selected_id: String) -> List(Element(Msg)) {
  external_counterfactual_example_options()
  |> list.map(fn(option) {
    let #(example_id, label, detail) = option
    select_ui.option(
      [selected(example_id == selected_id)],
      label <> " - " <> detail,
      example_id,
    )
  })
}

fn continuation_mode_options(selected_id: String) -> List(Element(Msg)) {
  [
    select_ui.option(
      [selected(selected_id == "scripted_agent")],
      "Deterministic scripted continuation",
      "scripted_agent",
    ),
    select_ui.option(
      [selected(selected_id == "wardwright_model")],
      "Live Wardwright model continuation",
      "wardwright_model",
    ),
  ]
}

fn harness_adapter_options(selected_id: String) -> List(Element(Msg)) {
  external_harness_adapter_options()
  |> list.map(fn(option) {
    let #(adapter_id, label, fidelity, status) = option
    select_ui.option(
      [selected(adapter_id == selected_id)],
      label <> " - " <> fidelity <> " - " <> status,
      adapter_id,
    )
  })
}

fn continuation_scope(continuation_mode: String) -> String {
  case continuation_mode {
    "wardwright_model" -> "continues through a Wardwright model"
    _ -> "continues with deterministic scripted steps"
  }
}

fn live_model_options(selected_id: String) -> List(Element(Msg)) {
  let options =
    external_model_options()
    |> list.map(fn(option) {
      let #(model_id, label) = option
      select_ui.option([selected(model_id == selected_id)], label, model_id)
    })

  case options {
    [] -> [
      select_ui.option([selected(True)], "No externally callable models", ""),
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
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
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
  .transcript-overview {
    display: grid;
    grid-template-columns: minmax(110px, max-content) minmax(180px, max-content) minmax(0, 1fr);
    gap: 12px;
    align-items: start;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #f8faf9;
  }
  .transcript-overview > div {
    display: grid;
    gap: 3px;
  }
  .transcript-overview span {
    color: var(--muted-foreground);
    font-size: 11px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .transcript-overview strong {
    overflow-wrap: anywhere;
  }
  .fork-workbench {
    display: grid;
    gap: 12px;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #f7fbfa;
  }
  .fork-workbench-heading {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(220px, 1.4fr);
    gap: 12px;
    align-items: start;
  }
  .fork-workbench-heading > div {
    display: grid;
    gap: 4px;
  }
  .fork-workbench-heading span,
  .fork-action-heading small {
    color: var(--muted-foreground);
    font-size: 11px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .fork-workbench-heading strong {
    overflow-wrap: anywhere;
  }
  .selected-event-context {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
    padding: 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  .selected-event-context > div {
    display: grid;
    gap: 4px;
    min-width: 0;
  }
  .selected-event-context span {
    color: var(--muted-foreground);
    font-size: 11px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .selected-event-context strong,
  .selected-event-context small {
    overflow-wrap: anywhere;
  }
  .selected-event-context small {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.35;
  }
  .fork-action-grid {
    display: grid;
    grid-template-columns: minmax(220px, 0.82fr) minmax(0, 1.18fr);
    gap: 12px;
    align-items: start;
  }
  .fork-action-card {
    display: grid;
    gap: 10px;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  .fork-action-heading {
    display: flex;
    justify-content: space-between;
    gap: 10px;
    align-items: baseline;
  }
  .continue-card .policy-overlay-field textarea {
    min-height: 120px;
  }
  .transcript-events {
    display: grid;
    gap: 8px;
  }
  .transcript-event-shell {
    display: grid;
    gap: 8px;
  }
  .transcript-event-shell .fork-workbench {
    margin-left: 60px;
  }
  .policy-overlay-field textarea {
    min-height: 150px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace;
    font-size: 12px;
    line-height: 1.45;
    resize: vertical;
  }
  .continuation-controls {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
    align-items: end;
  }
  .continuation-note {
    grid-column: 1 / -1;
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
    .control-debugger-app,
    .debugger-actions,
    .continuation-controls,
    .fork-action-grid,
    .fork-workbench-heading,
    .selected-event-context,
    .transcript-overview {
      grid-template-columns: 1fr;
    }
    .transcript-event {
      grid-template-columns: 1fr;
    }
    .transcript-event-shell .fork-workbench {
      margin-left: 0;
    }
  }
  "
}
