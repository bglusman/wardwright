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
import ui/table
import wardwright/projection_core
import wardwright/state_machine_core

type PatternOption =
  #(String, String, String, String)

type ModelOption =
  #(String, String, String, String)

pub type PolicyAction =
  #(String, String, String)

pub type TraceEvent =
  #(String, String, String, String)

pub type StateReplayStep =
  #(String, String, String, String, String, Bool)

pub type StateReplay {
  StateReplay(
    status: String,
    initial_state: String,
    final_state: String,
    transition_count: Int,
    state_ids: List(String),
    transitions: List(projection_core.StateTransition),
    steps: List(StateReplayStep),
  )
}

pub type Simulation {
  Simulation(
    pattern_title: String,
    pattern_promise: String,
    engine_id: String,
    artifact_label: String,
    selected_model: String,
    verdict: String,
    model_received_input: String,
    user_received_output: String,
    input_changed: Bool,
    output_changed: Bool,
    policy_actions: List(PolicyAction),
    trace_events: List(TraceEvent),
    state_replay: StateReplay,
  )
}

pub type Model {
  Model(
    pattern_id: String,
    model_id: String,
    user_input: String,
    model_response: String,
    step: Int,
    simulation: Simulation,
  )
}

pub type Msg {
  PatternChanged(String)
  ModelChanged(String)
  UserInputChanged(String)
  ModelResponseChanged(String)
  RunSimulation
  SubmitSimulation(List(#(String, String)))
  StepBack
  StepForward
  ResetTurn
}

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "pattern_options")
fn external_pattern_options() -> List(PatternOption)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "model_options")
fn external_model_options() -> List(ModelOption)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_pattern_id")
fn external_default_pattern_id() -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_model_id")
fn external_default_model_id() -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_user_input")
fn external_default_user_input(model_id: String) -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_model_response")
fn external_default_model_response(model_id: String) -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "run_simulation")
fn external_run_simulation(
  pattern_id: String,
  model_id: String,
  user_input: String,
  model_response: String,
) -> #(
  String,
  String,
  String,
  String,
  Bool,
  Bool,
  List(PolicyAction),
  List(TraceEvent),
  String,
  String,
)

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(_flags: Nil) -> Model {
  let pattern_id = external_default_pattern_id()
  let model_id = external_default_model_id()
  let user_input = external_default_user_input(model_id)
  let model_response = external_default_model_response(model_id)

  Model(
    pattern_id:,
    model_id:,
    user_input:,
    model_response:,
    step: 0,
    simulation: run_simulation(pattern_id, model_id, user_input, model_response),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    PatternChanged(pattern_id) ->
      run_model(Model(..model, pattern_id: pattern_id, step: 0))

    ModelChanged(model_id) -> {
      let user_input = external_default_user_input(model_id)
      let model_response = external_default_model_response(model_id)

      run_model(
        Model(
          ..model,
          model_id: model_id,
          user_input: user_input,
          model_response: model_response,
          step: 0,
        ),
      )
    }

    UserInputChanged(user_input) -> Model(..model, user_input: user_input)
    ModelResponseChanged(model_response) ->
      Model(..model, model_response: model_response)

    RunSimulation | SubmitSimulation(_) -> run_model(Model(..model, step: 0))

    StepBack -> Model(..model, step: int.max(model.step - 1, 0))

    StepForward ->
      Model(..model, step: int.min(model.step + 1, max_step(model.simulation)))

    ResetTurn -> {
      let user_input = external_default_user_input(model.model_id)
      let model_response = external_default_model_response(model.model_id)

      run_model(
        Model(
          ..model,
          user_input: user_input,
          model_response: model_response,
          step: 0,
        ),
      )
    }
  }
}

fn run_model(model: Model) -> Model {
  Model(
    ..model,
    simulation: run_simulation(
      model.pattern_id,
      model.model_id,
      model.user_input,
      model.model_response,
    ),
  )
}

fn run_simulation(
  pattern_id: String,
  model_id: String,
  user_input: String,
  model_response: String,
) -> Simulation {
  let #(
    selected_model,
    verdict,
    model_received_input,
    user_received_output,
    input_changed,
    output_changed,
    policy_actions,
    trace_events,
    config_model_id,
    config_version,
  ) = external_run_simulation(pattern_id, model_id, user_input, model_response)
  let #(pattern_title, pattern_promise) = selected_pattern(pattern_id)
  let #(
    engine_id,
    artifact_label,
    state_initial,
    state_default_projection,
    state_transitions,
  ) =
    projection_core.derive_summary(pattern_id, config_model_id, config_version)

  Simulation(
    pattern_title:,
    pattern_promise:,
    engine_id:,
    artifact_label:,
    selected_model:,
    verdict:,
    model_received_input:,
    user_received_output:,
    input_changed:,
    output_changed:,
    policy_actions:,
    trace_events:,
    state_replay: replay_state_machine(
      state_initial,
      state_default_projection,
      state_transitions,
    ),
  )
}

fn replay_state_machine(
  initial_state: String,
  default_projection: Bool,
  transitions: List(projection_core.StateTransition),
) -> StateReplay {
  case default_projection, transitions {
    True, [] ->
      StateReplay(
        status: "default_projection",
        initial_state: initial_state,
        final_state: initial_state,
        transition_count: 0,
        state_ids: [initial_state],
        transitions: [],
        steps: [],
      )
    _, _ -> {
      let events =
        transitions
        |> list.map(fn(transition) {
          let #(_, event, _, _, _) = transition
          event
        })
      let #(status, final_state, steps) =
        state_machine_core.simulate(initial_state, transitions, events)

      StateReplay(
        status: status,
        initial_state: initial_state,
        final_state: final_state,
        transition_count: list.length(transitions),
        state_ids: states_from_transitions(initial_state, transitions),
        transitions: transitions,
        steps: steps,
      )
    }
  }
}

fn states_from_transitions(
  initial_state: String,
  transitions: List(projection_core.StateTransition),
) -> List(String) {
  transitions
  |> collect_transition_states(add_unique([], initial_state))
  |> list.reverse
}

fn collect_transition_states(
  transitions: List(projection_core.StateTransition),
  states: List(String),
) -> List(String) {
  case transitions {
    [] -> states
    [transition, ..rest] -> {
      let #(from, _, to, _, _) = transition

      collect_transition_states(
        rest,
        states |> add_unique(from) |> add_unique(to),
      )
    }
  }
}

fn add_unique(states: List(String), state: String) -> List(String) {
  case string.trim(state) {
    "" -> states
    state_id ->
      case list.contains(states, state_id) {
        True -> states
        False -> [state_id, ..states]
      }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("lustre-workbench")], [
    html.style([], styles()),
    html.aside([class("rail")], [
      html.div([class("brand")], [
        html.span([class("mark")], [text("W")]),
        html.div([], [
          html.strong([], [text("Wardwright")]),
          html.span([], [text("Workbench")]),
        ]),
      ]),
      labeled_select(
        "Policy slice",
        "pattern_id",
        model.pattern_id,
        pattern_options(model.pattern_id),
        PatternChanged,
      ),
      labeled_select(
        "Registered model",
        "model_id",
        model.model_id,
        model_options(model.model_id),
        ModelChanged,
      ),
    ]),
    html.main([class("workspace")], [
      html.header([class("topbar")], [
        html.div([], [
          html.h1([], [text(model.simulation.pattern_title)]),
          html.p([], [text(model.simulation.pattern_promise)]),
        ]),
        html.div([class("status-stack")], [
          badge.badge([badge.variant(badge.Default)], [text("Lustre 5.7")]),
          badge.badge([badge.variant(badge.Secondary)], [
            text("Glizzy controls"),
          ]),
        ]),
      ]),
      simulator_form(model),
      results_grid(model),
      trace_panel(model),
    ]),
  ])
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

fn selected_pattern(pattern_id: String) -> #(String, String) {
  selected_pattern_from(pattern_id, external_pattern_options())
}

fn selected_pattern_from(
  pattern_id: String,
  options: List(PatternOption),
) -> #(String, String) {
  case options {
    [] -> #(pattern_id, "")
    [option, ..rest] -> {
      let #(option_id, title, _, promise) = option

      case option_id == pattern_id {
        True -> #(title, promise)
        False -> selected_pattern_from(pattern_id, rest)
      }
    }
  }
}

fn model_options(selected_id: String) -> List(Element(Msg)) {
  external_model_options()
  |> list.map(fn(option) {
    let #(option_id, _, route_type, access) = option
    select_ui.option(
      [selected(option_id == selected_id)],
      option_id <> " - " <> route_type <> " / " <> access,
      option_id,
    )
  })
}

fn simulator_form(model: Model) -> Element(Msg) {
  html.form([class("simulator"), event.on_submit(SubmitSimulation)], [
    html.div([class("form-header")], [
      html.div([], [
        html.strong([], [text("Selected model turn simulator")]),
      ]),
      html.div([class("actions")], [
        button.button(
          [
            button.variant(button.Ghost),
            type_("button"),
            event.on_click(ResetTurn),
          ],
          [text("Reset")],
        ),
        button.button([button.variant(button.Default), type_("submit")], [
          text("Run simulation"),
        ]),
      ]),
    ]),
    html.div([class("turn-grid")], [
      text_area(
        "User input",
        "user_input",
        model.user_input,
        "Try: please moo for me",
        UserInputChanged,
      ),
      text_area(
        "Raw model output / stream",
        "model_response",
        model.model_response,
        "Type the model output to evaluate",
        ModelResponseChanged,
      ),
    ]),
  ])
}

fn text_area(
  label: String,
  field_name: String,
  content: String,
  hint: String,
  to_msg: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([class("field editor")], [
    html.span([], [text(label)]),
    html.textarea(
      [
        name(field_name),
        rows(6),
        placeholder(hint),
        event.on_input(to_msg),
      ],
      content,
    ),
  ])
}

fn results_grid(model: Model) -> Element(Msg) {
  let simulation = model.simulation

  html.section([class("results")], [
    html.article([class(changed_class(simulation.input_changed))], [
      html.div([class("panel-heading")], [
        html.span([], [text("Provider input")]),
        badge.badge([badge.variant(status_variant(simulation.input_changed))], [
          text(change_label(simulation.input_changed)),
        ]),
      ]),
      html.pre([], [text(simulation.model_received_input)]),
    ]),
    html.article([class(changed_class(simulation.output_changed))], [
      html.div([class("panel-heading")], [
        html.span([], [text("User output")]),
        badge.badge([badge.variant(status_variant(simulation.output_changed))], [
          text(change_label(simulation.output_changed)),
        ]),
      ]),
      html.pre([], [text(simulation.user_received_output)]),
    ]),
    html.article([class("panel facts")], [
      html.div([class("fact")], [
        html.span([], [text("Selected upstream")]),
        html.strong([], [text(blank_default(simulation.selected_model, "none"))]),
      ]),
      html.div([class("fact")], [
        html.span([], [text("Engine")]),
        html.strong([], [text(simulation.engine_id)]),
      ]),
      html.div([class("fact")], [
        html.span([], [text("Policy artifact")]),
        html.code([], [text(simulation.artifact_label)]),
      ]),
      html.div([class("fact")], [
        html.span([], [text("Verdict")]),
        html.strong([], [text(simulation.verdict)]),
      ]),
    ]),
    policy_action_table(simulation.policy_actions),
    state_machine_graph(
      simulation.state_replay,
      active_state_at(simulation.state_replay, model.step),
    ),
    state_machine_table(simulation.state_replay),
  ])
}

fn policy_action_table(actions: List(PolicyAction)) -> Element(Msg) {
  table.table([class("policy-table")], [
    table.table_header([], [
      table.table_header_row([], [
        table.table_column_header([], [text("Rule")]),
        table.table_column_header([], [text("Action")]),
        table.table_column_header([], [text("Message")]),
      ]),
    ]),
    table.table_body([], action_rows(actions)),
  ])
}

fn action_rows(actions: List(PolicyAction)) -> List(Element(Msg)) {
  case actions {
    [] -> [
      table.table_row([], [
        table.table_cell([attribute("colspan", "3")], [
          text("No request policy action changed this turn."),
        ]),
      ]),
    ]
    _ ->
      actions
      |> list.map(fn(action) {
        let #(rule_id, action_name, message) = action
        table.table_row([], [
          table.table_cell([], [text(blank_default(rule_id, "policy"))]),
          table.table_cell([], [text(blank_default(action_name, "pass"))]),
          table.table_cell([], [text(blank_default(message, "applied"))]),
        ])
      })
  }
}

fn state_machine_graph(
  replay: StateReplay,
  active_state: String,
) -> Element(Msg) {
  html.article([class("panel state-graph")], [
    html.div([class("panel-heading")], [
      html.span([], [text("State machine")]),
      badge.badge([badge.variant(badge.Outline)], [
        text(blank_default(replay.status, "unknown")),
      ]),
    ]),
    html.div(
      [class("state-track")],
      replay.state_ids
        |> list.map(fn(state) {
          html.div(
            [
              class(state_node_class(state, active_state, replay.final_state)),
              attribute("data-state", state),
              attribute("data-active", bool_string(state == active_state)),
            ],
            [
              html.strong([], [text(state_label(state))]),
              html.span([], [text(state)]),
            ],
          )
        }),
    ),
    html.div(
      [class("edge-list")],
      state_edge_rows(replay.transitions, active_state),
    ),
  ])
}

fn state_edge_rows(
  transitions: List(projection_core.StateTransition),
  active_state: String,
) -> List(Element(Msg)) {
  case transitions {
    [] -> [
      html.div([class("state-edge")], [
        html.strong([], [text("Default projection")]),
        html.span([], [text("No transition table is needed for this policy.")]),
      ]),
    ]
    _ ->
      transitions
      |> list.map(fn(transition) {
        let #(from, event, to, action_name, node_id) = transition

        html.div([class(state_edge_class(from, to, active_state))], [
          html.strong([], [
            text(
              blank_default(from, "none") <> " -> " <> blank_default(to, "none"),
            ),
          ]),
          html.span([], [
            text(
              blank_default(event, "event")
              <> " / "
              <> blank_default(action_name, "pass")
              <> " / "
              <> blank_default(node_id, "node"),
            ),
          ]),
        ])
      })
  }
}

fn state_machine_table(replay: StateReplay) -> Element(Msg) {
  table.table([class("state-table")], [
    table.table_header([], [
      table.table_header_row([], [
        table.table_column_header([], [text("Gleam replay")]),
        table.table_column_header([], [
          text(blank_default(replay.status, "unknown")),
        ]),
        table.table_column_header([], [
          text("Final: " <> blank_default(replay.final_state, "none")),
        ]),
      ]),
      table.table_header_row([], [
        table.table_column_header([], [text("Event")]),
        table.table_column_header([], [text("From -> to")]),
        table.table_column_header([], [
          text(int.to_string(replay.transition_count) <> " transitions"),
        ]),
      ]),
    ]),
    table.table_body([], state_rows(replay.steps)),
  ])
}

fn state_rows(transitions: List(StateReplayStep)) -> List(Element(Msg)) {
  case transitions {
    [] -> [
      table.table_row([], [
        table.table_cell([attribute("colspan", "3")], [
          text("Default single-state policy."),
        ]),
      ]),
    ]
    _ ->
      transitions
      |> list.map(fn(transition) {
        let #(from, event, to, action_name, node_id, matched) = transition

        table.table_row([], [
          table.table_cell([], [text(blank_default(event, "event"))]),
          table.table_cell([], [
            text(
              blank_default(from, "none") <> " -> " <> blank_default(to, "none"),
            ),
          ]),
          table.table_cell([], [
            text(
              blank_default(action_name, "pass")
              <> " / "
              <> blank_default(node_id, "node")
              <> " / "
              <> matched_label(matched),
            ),
          ]),
        ])
      })
  }
}

fn trace_panel(model: Model) -> Element(Msg) {
  let simulation = model.simulation
  let playback_count = max_step(simulation) + 1
  let #(phase, label, detail, severity) =
    active_trace_event(simulation, model.step)

  html.section([class("trace-panel")], [
    html.div([class("trace-header")], [
      html.div([], [
        html.strong([], [text("Trace playback")]),
        html.span([], [
          text(
            "Step "
            <> int.to_string(model.step + 1)
            <> " of "
            <> int.to_string(int.max(playback_count, 1)),
          ),
        ]),
      ]),
      html.div([class("actions")], [
        button.button(
          [
            button.variant(button.Outline),
            type_("button"),
            disabled(model.step == 0),
            event.on_click(StepBack),
          ],
          [text("Back")],
        ),
        button.button(
          [
            button.variant(button.Default),
            type_("button"),
            disabled(model.step >= max_step(simulation)),
            event.on_click(StepForward),
          ],
          [text("Next step")],
        ),
      ]),
    ]),
    html.article([class("active-event " <> severity_class(severity))], [
      badge.badge([badge.variant(badge.Outline)], [
        text(blank_default(phase, "phase")),
      ]),
      html.strong([], [text(blank_default(label, "No trace event"))]),
      html.p([], [
        text(blank_default(
          detail,
          "Run the simulation to refresh trace evidence.",
        )),
      ]),
    ]),
  ])
}

fn active_trace_event(simulation: Simulation, step: Int) -> TraceEvent {
  case simulation.trace_events |> list.drop(step) |> list.first {
    Ok(event) -> event
    Error(_) -> #("", "No trace event", "", "pass")
  }
}

fn active_state_at(replay: StateReplay, step: Int) -> String {
  case replay.steps {
    [] -> replay.final_state
    _ ->
      case step <= 0 {
        True -> replay.initial_state
        False ->
          case replay.steps |> list.drop(step - 1) |> list.first {
            Ok(step_row) -> {
              let #(_, _, to, _, _, _) = step_row
              to
            }
            Error(_) -> replay.final_state
          }
      }
  }
}

fn max_step(simulation: Simulation) -> Int {
  int.max(
    int.max(list.length(simulation.trace_events) - 1, 0),
    list.length(simulation.state_replay.steps),
  )
}

fn changed_class(changed: Bool) -> String {
  case changed {
    True -> "panel changed"
    False -> "panel"
  }
}

fn change_label(changed: Bool) -> String {
  case changed {
    True -> "rewritten"
    False -> "unchanged"
  }
}

fn matched_label(matched: Bool) -> String {
  case matched {
    True -> "matched"
    False -> "unmatched"
  }
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

fn state_label(state: String) -> String {
  state
  |> string.replace(each: "_", with: " ")
  |> string.replace(each: "-", with: " ")
}

fn state_node_class(
  state: String,
  active_state: String,
  final_state: String,
) -> String {
  "state-node"
  <> active_class(state == active_state)
  <> final_class(state == final_state)
}

fn state_edge_class(from: String, to: String, active_state: String) -> String {
  "state-edge" <> active_class(from == active_state || to == active_state)
}

fn active_class(active: Bool) -> String {
  case active {
    True -> " active"
    False -> ""
  }
}

fn final_class(final: Bool) -> String {
  case final {
    True -> " terminal"
    False -> ""
  }
}

fn status_variant(changed: Bool) -> badge.Variant {
  case changed {
    True -> badge.Secondary
    False -> badge.Outline
  }
}

fn blank_default(value: String, fallback: String) -> String {
  case string.trim(value) {
    "" -> fallback
    trimmed -> trimmed
  }
}

fn severity_class(severity: String) -> String {
  case severity {
    "warn" -> "warn"
    "fail" -> "fail"
    "block" -> "fail"
    _ -> "pass"
  }
}

fn styles() -> String {
  "
  .lustre-workbench {
    min-height: 100vh;
    display: grid;
    grid-template-columns: minmax(260px, 320px) minmax(0, 1fr);
    background: var(--background);
    color: var(--foreground);
  }
  .rail {
    display: flex;
    flex-direction: column;
    gap: 18px;
    padding: 24px;
    border-right: 1px solid var(--border);
    background: #fbfcfd;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .brand div, .field, .form-header div, .trace-header div {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .mark {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    border-radius: 8px;
    color: white;
    background: var(--primary);
    font-weight: 800;
  }
  .brand strong, .form-header strong, .trace-header strong {
    font-size: 17px;
  }
  .brand span, .form-header span, .trace-header span, .field > span, .fact span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
  }
  .field {
    gap: 8px;
  }
  .runtime-note {
    margin-top: auto;
  }
  .workspace {
    display: flex;
    flex-direction: column;
    gap: 18px;
    padding: 24px;
  }
  .topbar, .form-header, .trace-header, .panel-heading {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 14px;
  }
  h1 {
    margin: 0;
    font-size: 28px;
    line-height: 1.15;
  }
  p {
    margin: 0;
    color: #46525f;
    line-height: 1.45;
  }
  .status-stack, .actions {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
  }
  .simulator, .panel, .trace-panel {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 16px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--card);
  }
  .turn-grid, .results {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16px;
  }
  .results {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .editor textarea, textarea, select {
    width: 100%;
    border: 1px solid var(--input);
    border-radius: 8px;
    background: #fff;
    color: var(--foreground);
    font: inherit;
    line-height: 1.45;
  }
  textarea {
    min-height: 148px;
    padding: 12px;
    resize: vertical;
  }
  select {
    min-height: 42px;
    padding: 8px 34px 8px 10px;
  }
  button {
    min-height: 38px;
    border-radius: 8px;
    border: 1px solid transparent;
    padding: 8px 12px;
    cursor: pointer;
    font-weight: 750;
  }
  button:disabled {
    cursor: not-allowed;
    opacity: 0.45;
  }
  .bg-primary {
    background: var(--primary);
  }
  .text-primary-foreground {
    color: var(--primary-foreground);
  }
  .bg-secondary {
    background: var(--secondary);
  }
  .text-secondary-foreground {
    color: var(--secondary-foreground);
  }
  .border-input, .border {
    border-color: var(--border);
  }
  .bg-background {
    background: #fff;
  }
  .text-foreground {
    color: var(--foreground);
  }
  .hover\\:bg-accent:hover, button:hover {
    background: var(--accent);
    color: var(--accent-foreground);
  }
  .rounded-full {
    border-radius: 999px;
  }
  .text-xs {
    font-size: 12px;
  }
  .font-semibold {
    font-weight: 750;
  }
  .panel.changed {
    border-color: #d99a24;
    background: #fffaf0;
  }
  pre {
    min-height: 170px;
    margin: 0;
    overflow: auto;
    white-space: pre-wrap;
    border-radius: 8px;
    background: #0f1720;
    color: #edf7f4;
    padding: 12px;
    font-size: 13px;
    line-height: 1.5;
  }
  .facts {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .fact {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }
  .fact code, .fact strong {
    overflow-wrap: anywhere;
  }
  .state-graph {
    grid-column: 1 / -1;
  }
  .state-track {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(132px, 1fr));
    gap: 10px;
  }
  .state-node {
    min-width: 0;
    display: grid;
    gap: 5px;
    padding: 12px;
    border: 1px solid #cfd8e3;
    border-radius: 8px;
    background: #f8fafc;
  }
  .state-node strong {
    color: #1f2a37;
    font-size: 14px;
    line-height: 1.2;
    overflow-wrap: anywhere;
  }
  .state-node span {
    color: #66727f;
    font-size: 12px;
    font-weight: 750;
    overflow-wrap: anywhere;
  }
  .state-node.active {
    border-color: #16605a;
    background: #e6f4f2;
    box-shadow: inset 0 0 0 1px #16605a;
  }
  .state-node.terminal {
    border-style: double;
  }
  .edge-list {
    display: grid;
    gap: 8px;
  }
  .state-edge {
    display: grid;
    grid-template-columns: minmax(120px, 0.65fr) minmax(0, 1fr);
    gap: 10px;
    align-items: start;
    padding: 10px;
    border: 1px solid #e1e7ed;
    border-radius: 8px;
    background: #fff;
  }
  .state-edge.active {
    border-color: #9b6b18;
    background: #fff8e8;
  }
  .state-edge strong, .state-edge span {
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .state-edge span {
    color: #56636f;
    font-size: 12px;
    font-weight: 700;
  }
  .policy-table, .state-table {
    grid-column: 1 / -1;
    overflow: hidden;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  table {
    border-collapse: collapse;
  }
  th, td {
    border-bottom: 1px solid var(--border);
    padding: 10px;
    vertical-align: top;
  }
  th {
    background: #eef3f5;
    color: #4a5865;
    font-size: 12px;
    text-transform: uppercase;
  }
  .active-event {
    display: grid;
    gap: 8px;
    padding: 14px;
    border-radius: 8px;
    border: 1px solid var(--border);
    background: #fff;
  }
  .active-event.warn {
    border-color: #d99a24;
    background: #fff8e8;
  }
  .active-event.fail {
    border-color: var(--destructive);
    background: #fff2f0;
  }
  @media (max-width: 860px) {
    .lustre-workbench {
      grid-template-columns: 1fr;
    }
    .rail {
      border-right: 0;
      border-bottom: 1px solid var(--border);
    }
    .topbar, .form-header, .trace-header, .turn-grid, .results, .state-edge {
      grid-template-columns: 1fr;
      flex-direction: column;
    }
  }
  "
}
