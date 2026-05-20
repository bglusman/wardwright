import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lustre
import lustre/attribute.{
  attribute, class, disabled, id, name, placeholder, rows, selected, type_,
  value,
}
import lustre/element.{type Element, element, text}
import lustre/element/html
import lustre/event
import ui/badge
import ui/button
import ui/select as select_ui
import ui/table
import wardwright/lustre_shell
import wardwright/projection_core
import wardwright/state_machine_core

type PatternOption =
  #(String, String, String, String)

type ModelOption =
  #(String, String, String, String)

type FixtureOption =
  #(String, String, String, String, String, List(RetryResponse))

pub type PolicyAction =
  #(String, String, String)

pub type TraceEvent =
  #(String, String, String, String, String)

pub type RetryResponse =
  #(Int, String)

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
    fixture_id: String,
    user_input: String,
    model_response: String,
    retry_responses: List(RetryResponse),
    fixture_title: String,
    fixture_status: String,
    fixture_error: String,
    authoring_input: String,
    authoring_configured: Bool,
    authoring_model: String,
    authoring_route: String,
    authoring_status_label: String,
    authoring_response_status: String,
    authoring_response: String,
    authoring_draft_model: String,
    authoring_draft_summary: String,
    authoring_draft_artifact: String,
    authoring_draft_review_note: String,
    authoring_activation_status: String,
    authoring_activation_error: String,
    step: Int,
    simulation: Simulation,
  )
}

pub type Msg {
  PatternChanged(String)
  ModelChanged(String)
  FixtureChanged(String)
  UserInputChanged(String)
  ModelResponseChanged(String)
  RetryResponseChanged(Int, String)
  FixtureTitleChanged(String)
  SaveFixture
  AuthoringInputChanged(String)
  AskAuthoring
  SubmitAuthoring(List(#(String, String)))
  ActivateAuthoringDraft
  ClearAuthoring
  RunSimulation
  SubmitSimulation(List(#(String, String)))
  StepBack
  StepForward
  ResetTurn
}

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "pattern_options")
fn external_pattern_options(model_id: String) -> List(PatternOption)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "model_options")
fn external_model_options() -> List(ModelOption)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "fixture_options")
fn external_fixture_options(
  pattern_id: String,
  model_id: String,
) -> List(FixtureOption)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_pattern_id")
fn external_default_pattern_id(model_id: String) -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_model_id")
fn external_default_model_id() -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_user_input")
fn external_default_user_input(model_id: String) -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "default_model_response")
fn external_default_model_response(model_id: String) -> String

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "retry_response_slots")
fn external_retry_response_slots(model_id: String) -> Int

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "projection_summary")
fn external_projection_summary(
  pattern_id: String,
  model_id: String,
) -> #(String, String, String, Bool, List(projection_core.StateTransition))

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "run_simulation")
fn external_run_simulation(
  pattern_id: String,
  model_id: String,
  user_input: String,
  model_response: String,
  retry_responses: List(RetryResponse),
) -> #(
  String,
  String,
  String,
  String,
  Bool,
  Bool,
  List(PolicyAction),
  List(TraceEvent),
  List(String),
  String,
  String,
)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "save_fixture")
fn external_save_fixture(
  pattern_id: String,
  model_id: String,
  title: String,
  user_input: String,
  model_response: String,
  retry_responses: List(RetryResponse),
) -> #(Bool, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "authoring_status")
fn external_authoring_status(
  model_id: String,
) -> #(Bool, String, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "ask_authoring_agent")
fn external_ask_authoring_agent(
  model_id: String,
  pattern_id: String,
  message: String,
) -> #(String, String, String, String, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreWorkbenchData", "activate_authoring_draft")
fn external_activate_authoring_draft(
  artifact_json: String,
) -> #(Bool, String, String)

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(_flags: Nil) -> Model {
  let model_id = external_default_model_id()
  let pattern_id = external_default_pattern_id(model_id)
  let fixture_id = default_fixture_id(pattern_id, model_id)
  let #(user_input, model_response, retry_responses) =
    fixture_turn(pattern_id, model_id, fixture_id)
  let #(
    authoring_configured,
    authoring_model,
    authoring_route,
    authoring_status_label,
  ) = external_authoring_status(model_id)

  Model(
    pattern_id:,
    model_id:,
    fixture_id:,
    user_input:,
    model_response:,
    retry_responses:,
    fixture_title: "",
    fixture_status: "",
    fixture_error: "",
    authoring_input: "",
    authoring_configured:,
    authoring_model:,
    authoring_route:,
    authoring_status_label:,
    authoring_response_status: "",
    authoring_response: "",
    authoring_draft_model: "",
    authoring_draft_summary: "",
    authoring_draft_artifact: "",
    authoring_draft_review_note: "",
    authoring_activation_status: "",
    authoring_activation_error: "",
    step: 0,
    simulation: run_simulation(
      pattern_id,
      model_id,
      user_input,
      model_response,
      retry_responses,
    ),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    PatternChanged(pattern_id) -> {
      let fixture_id = default_fixture_id(pattern_id, model.model_id)
      let #(user_input, model_response, retry_responses) =
        fixture_turn(pattern_id, model.model_id, fixture_id)

      run_model(
        Model(
          ..model,
          pattern_id: pattern_id,
          fixture_id: fixture_id,
          user_input: user_input,
          model_response: model_response,
          retry_responses: retry_responses,
          fixture_status: "",
          fixture_error: "",
          step: 0,
        ),
      )
    }

    ModelChanged(model_id) -> {
      let pattern_id = external_default_pattern_id(model_id)
      let fixture_id = default_fixture_id(pattern_id, model_id)
      let #(user_input, model_response, retry_responses) =
        fixture_turn(pattern_id, model_id, fixture_id)
      let #(
        authoring_configured,
        authoring_model,
        authoring_route,
        authoring_status_label,
      ) = external_authoring_status(model_id)

      run_model(
        Model(
          ..model,
          model_id: model_id,
          pattern_id: pattern_id,
          fixture_id: fixture_id,
          user_input: user_input,
          model_response: model_response,
          retry_responses: retry_responses,
          fixture_status: "",
          fixture_error: "",
          authoring_configured:,
          authoring_model:,
          authoring_route:,
          authoring_status_label:,
          step: 0,
        ),
      )
    }

    FixtureChanged(fixture_id) -> {
      let #(user_input, model_response, retry_responses) =
        fixture_turn(model.pattern_id, model.model_id, fixture_id)

      run_model(
        Model(
          ..model,
          fixture_id: fixture_id,
          user_input: user_input,
          model_response: model_response,
          retry_responses: retry_responses,
          fixture_status: "",
          fixture_error: "",
          step: 0,
        ),
      )
    }

    UserInputChanged(user_input) ->
      Model(..model, fixture_id: custom_fixture_id(), user_input: user_input)
      |> reset_and_run_model

    ModelResponseChanged(model_response) ->
      Model(
        ..model,
        fixture_id: custom_fixture_id(),
        model_response: model_response,
      )
      |> reset_and_run_model

    RetryResponseChanged(index, model_response) ->
      Model(
        ..model,
        fixture_id: custom_fixture_id(),
        retry_responses: update_retry_response(
          model.retry_responses,
          index,
          model_response,
        ),
      )
      |> reset_and_run_model

    FixtureTitleChanged(title) -> Model(..model, fixture_title: title)

    SaveFixture -> {
      let #(ok, message, fixture_id) =
        external_save_fixture(
          model.pattern_id,
          model.model_id,
          model.fixture_title,
          model.user_input,
          model.model_response,
          model.retry_responses,
        )

      case ok {
        True ->
          run_model(
            Model(
              ..model,
              fixture_id: fixture_id,
              fixture_status: message,
              fixture_error: "",
            ),
          )
        False -> Model(..model, fixture_status: "", fixture_error: message)
      }
    }

    AuthoringInputChanged(input) -> Model(..model, authoring_input: input)

    AskAuthoring | SubmitAuthoring(_) -> {
      case model.authoring_configured {
        False -> model
        True ->
          case string.trim(model.authoring_input) {
            "" -> model
            prompt -> {
              let #(
                status,
                content,
                draft_model,
                draft_summary,
                draft_artifact,
                draft_review_note,
              ) =
                external_ask_authoring_agent(
                  model.model_id,
                  model.pattern_id,
                  prompt,
                )

              Model(
                ..model,
                authoring_input: "",
                authoring_response_status: status,
                authoring_response: content,
                authoring_draft_model: draft_model,
                authoring_draft_summary: draft_summary,
                authoring_draft_artifact: draft_artifact,
                authoring_draft_review_note: draft_review_note,
                authoring_activation_status: "",
                authoring_activation_error: "",
              )
            }
          }
      }
    }

    ActivateAuthoringDraft -> {
      case string.trim(model.authoring_draft_artifact) {
        "" ->
          Model(
            ..model,
            authoring_activation_status: "",
            authoring_activation_error: "No draft artifact is available to activate.",
          )
        artifact_json -> {
          let #(ok, message, activated_model_id) =
            external_activate_authoring_draft(artifact_json)

          case ok {
            False ->
              Model(
                ..model,
                authoring_activation_status: "",
                authoring_activation_error: message,
              )
            True -> {
              let model_id = blank_default(activated_model_id, model.model_id)
              let pattern_id = external_default_pattern_id(model_id)
              let fixture_id = default_fixture_id(pattern_id, model_id)
              let #(user_input, model_response, retry_responses) =
                fixture_turn(pattern_id, model_id, fixture_id)
              let #(
                authoring_configured,
                authoring_model,
                authoring_route,
                authoring_status_label,
              ) = external_authoring_status(model_id)

              run_model(
                Model(
                  ..model,
                  model_id:,
                  pattern_id:,
                  fixture_id:,
                  user_input:,
                  model_response:,
                  retry_responses:,
                  authoring_configured:,
                  authoring_model:,
                  authoring_route:,
                  authoring_status_label:,
                  authoring_draft_artifact: "",
                  authoring_draft_summary: "",
                  authoring_draft_review_note: "",
                  authoring_activation_status: message,
                  authoring_activation_error: "",
                  step: 0,
                ),
              )
            }
          }
        }
      }
    }

    ClearAuthoring ->
      Model(
        ..model,
        authoring_input: "",
        authoring_response_status: "",
        authoring_response: "",
        authoring_draft_model: "",
        authoring_draft_summary: "",
        authoring_draft_artifact: "",
        authoring_draft_review_note: "",
        authoring_activation_status: "",
        authoring_activation_error: "",
      )

    RunSimulation | SubmitSimulation(_) -> run_model(Model(..model, step: 0))

    StepBack -> Model(..model, step: int.max(model.step - 1, 0))

    StepForward ->
      Model(..model, step: int.min(model.step + 1, max_step(model.simulation)))

    ResetTurn -> {
      let fixture_id = reset_fixture_id(model)
      let #(user_input, model_response, retry_responses) =
        fixture_turn(model.pattern_id, model.model_id, fixture_id)

      run_model(
        Model(
          ..model,
          fixture_id: fixture_id,
          user_input: user_input,
          model_response: model_response,
          retry_responses: retry_responses,
          fixture_status: "",
          fixture_error: "",
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
      model.retry_responses,
    ),
  )
}

fn reset_and_run_model(model: Model) -> Model {
  run_model(Model(..model, step: 0))
}

fn run_simulation(
  pattern_id: String,
  model_id: String,
  user_input: String,
  model_response: String,
  retry_responses: List(RetryResponse),
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
    state_events,
    _config_model_id,
    _config_version,
  ) =
    external_run_simulation(
      pattern_id,
      model_id,
      user_input,
      model_response,
      retry_responses,
    )
  let #(pattern_title, pattern_promise) = selected_pattern(pattern_id)
  let #(
    engine_id,
    artifact_label,
    state_initial,
    state_default_projection,
    state_transitions,
  ) = external_projection_summary(pattern_id, model_id)

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
      state_events,
    ),
  )
}

fn replay_state_machine(
  initial_state: String,
  default_projection: Bool,
  transitions: List(projection_core.StateTransition),
  events: List(String),
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
    lustre_shell.sidebar(lustre_shell.Workbench, "Workbench", [
      labeled_select(
        "Registered model",
        "model_id",
        model.model_id,
        model_options(model.model_id),
        ModelChanged,
      ),
    ]),
    workspace(model),
  ])
}

pub fn workspace(model: Model) -> Element(Msg) {
  html.main([class("workspace")], [
    html.header([class("topbar")], [
      html.div([], [
        html.h1([], [text(model.model_id)]),
        html.p([], [
          text(
            model.simulation.pattern_title
            <> ": "
            <> model.simulation.pattern_promise,
          ),
        ]),
      ]),
    ]),
    simulator_form(model),
    authoring_panel(model),
    results_grid(model),
    trace_panel(model),
  ])
}

pub fn sidebar_controls(model: Model) -> List(Element(Msg)) {
  [
    labeled_select(
      "Registered model",
      "model_id",
      model.model_id,
      model_options(model.model_id),
      ModelChanged,
    ),
  ]
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

fn pattern_options(
  model_id: String,
  selected_id: String,
) -> List(Element(Msg)) {
  external_pattern_options(model_id)
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
  selected_pattern_from(pattern_id, external_pattern_options(""))
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
    let #(option_id, _, _, access) = option
    select_ui.option(
      [selected(option_id == selected_id)],
      option_id <> " - " <> access,
      option_id,
    )
  })
}

fn fixture_options(
  pattern_id: String,
  model_id: String,
  selected_id: String,
) -> List(Element(Msg)) {
  let loaded_options =
    external_fixture_options(pattern_id, model_id)
    |> list.map(fn(option) {
      let #(option_id, title, _, _, _, _) = option

      select_ui.option([selected(option_id == selected_id)], title, option_id)
    })

  case selected_id == custom_fixture_id() {
    True -> [
      select_ui.option(
        [selected(True)],
        "Custom edited turn",
        custom_fixture_id(),
      ),
      ..loaded_options
    ]

    False -> loaded_options
  }
}

fn policy_projection_select(model: Model) -> Element(Msg) {
  html.label([class("field projection-field"), attribute("for", "pattern_id")], [
    html.span([], [
      text("Policy projection"),
      html.span(
        [
          class("help-dot"),
          attribute(
            "title",
            "Projection chooses the policy lens for this model. The graph shows possible transitions for the selected model, then highlights the replay path driven by the current fixture and edits.",
          ),
        ],
        [text("?")],
      ),
    ]),
    select_ui.select(
      [
        id("pattern_id"),
        name("pattern_id"),
        value(model.pattern_id),
        event.on_change(PatternChanged),
      ],
      pattern_options(model.model_id, model.pattern_id),
    ),
  ])
}

fn simulator_form(model: Model) -> Element(Msg) {
  html.form([class("simulator"), event.on_submit(SubmitSimulation)], [
    html.div([class("form-header")], [
      html.div([], [
        html.strong([], [text("Selected model turn simulator")]),
      ]),
      html.div([class("simulator-toolbar")], [
        labeled_select(
          "Fixture",
          "fixture_id",
          model.fixture_id,
          fixture_options(model.pattern_id, model.model_id, model.fixture_id),
          FixtureChanged,
        ),
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
    retry_response_fields(model),
    fixture_save_panel(model),
  ])
}

fn fixture_save_panel(model: Model) -> Element(Msg) {
  html.div([class("fixture-save")], [
    html.label([class("field")], [
      html.span([], [text("Save fixture")]),
      html.input([
        id("fixture_title"),
        name("fixture_title"),
        placeholder("Reviewed retry turn"),
        value(model.fixture_title),
        event.on_input(FixtureTitleChanged),
      ]),
    ]),
    button.button(
      [
        button.variant(button.Ghost),
        type_("button"),
        event.on_click(SaveFixture),
      ],
      [text("Save current turn")],
    ),
    html.span([class("fixture-note")], [
      text(
        "Saved fixtures are available to every model on this projection; the source model is recorded.",
      ),
    ]),
    case model.fixture_status {
      "" -> html.span([], [])
      status -> html.strong([class("fixture-status")], [text(status)])
    },
    case model.fixture_error {
      "" -> html.span([], [])
      error -> html.strong([class("fixture-error")], [text(error)])
    },
  ])
}

fn authoring_panel(model: Model) -> Element(Msg) {
  html.section([class("authoring-panel")], [
    html.div([class("form-header")], [
      html.div([], [
        html.strong([], [text("Model authoring")]),
        html.p([], [
          text(
            "Draft and review model changes against the current model and projection.",
          ),
        ]),
      ]),
      html.div([class("authoring-meta")], [
        badge.badge(
          [badge.variant(authoring_badge_variant(model.authoring_configured))],
          [
            text(model.authoring_status_label),
          ],
        ),
        html.span([], [
          html.strong([], [text("Assistant model")]),
          text(" " <> blank_default(model.authoring_model, "not configured")),
        ]),
        html.span([], [
          html.strong([], [text("Route")]),
          text(" " <> blank_default(model.authoring_route, "direct")),
        ]),
      ]),
    ]),
    case model.authoring_configured {
      False -> authoring_setup_panel()
      True ->
        html.div([class("authoring-live")], [
          authoring_form(model),
          authoring_response(model),
        ])
    },
  ])
}

fn authoring_form(model: Model) -> Element(Msg) {
  html.form(
    [
      id("authoring_agent_form"),
      class("authoring-form"),
      event.on_submit(SubmitAuthoring),
    ],
    [
      html.label([class("field editor")], [
        html.span([], [text("Request")]),
        html.textarea(
          [
            id("authoring_agent_input"),
            name("authoring_agent_input"),
            rows(5),
            placeholder("Ask for a reviewable model draft"),
            value(model.authoring_input),
            event.on_input(AuthoringInputChanged),
          ],
          model.authoring_input,
        ),
      ]),
      html.div([class("actions")], [
        button.button(
          [
            button.variant(button.Default),
            type_("submit"),
            disabled(string.trim(model.authoring_input) == ""),
          ],
          [text("Ask agent")],
        ),
        button.button(
          [
            button.variant(button.Ghost),
            type_("button"),
            event.on_click(ClearAuthoring),
          ],
          [text("Clear")],
        ),
      ]),
    ],
  )
}

fn authoring_setup_panel() -> Element(Msg) {
  html.div([class("authoring-setup")], [
    html.strong([], [text("In-app authoring agent is not configured")]),
    html.p([], [
      text(
        "Configure the authoring agent environment and restart Wardwright to use the in-app assistant.",
      ),
    ]),
    html.ul([], [
      html.li([], [
        text("Enable it with "),
        html.code([], [text("WARDWRIGHT_AUTHORING_AGENT_ENABLED=1")]),
        text("."),
      ]),
      html.li([], [
        text(
          "Set either direct provider credentials or a Wardwright-routed authoring model.",
        ),
      ]),
      html.li([], [
        text("Restart the server after changing the configuration."),
      ]),
    ]),
    html.p([], [
      text(
        "You can also use your own agent against Wardwright through the MCP endpoint or CLI without enabling the in-page assistant.",
      ),
    ]),
  ])
}

fn authoring_response(model: Model) -> Element(Msg) {
  case model.authoring_response {
    "" ->
      html.div([class("authoring-empty")], [text("No authoring request yet.")])
    response ->
      html.div([class("authoring-response")], [
        html.div([class("panel-heading")], [
          html.span([], [text("Assistant response")]),
          badge.badge(
            [
              badge.variant(authoring_response_variant(
                model.authoring_response_status,
              )),
            ],
            [
              text(blank_default(model.authoring_response_status, "completed")),
            ],
          ),
        ]),
        html.pre([], [text(response)]),
        activation_status(model),
        case model.authoring_draft_summary {
          "" -> html.div([], [])
          summary ->
            html.div([class("authoring-draft")], [
              html.strong([], [
                text(blank_default(model.authoring_draft_model, "Draft")),
              ]),
              html.span([], [text(summary)]),
              html.small([], [
                text(blank_default(
                  model.authoring_draft_review_note,
                  "Review the artifact before activation.",
                )),
              ]),
              html.details(
                [class("authoring-draft-artifact"), attribute("open", "")],
                [
                  html.summary([], [text("Review draft artifact")]),
                  html.pre([], [text(model.authoring_draft_artifact)]),
                ],
              ),
              button.button(
                [
                  button.variant(button.Default),
                  type_("button"),
                  event.on_click(ActivateAuthoringDraft),
                ],
                [text("Approve and activate draft")],
              ),
            ])
        },
      ])
  }
}

fn activation_status(model: Model) -> Element(Msg) {
  case model.authoring_activation_status, model.authoring_activation_error {
    "", "" -> html.div([], [])
    status, "" -> html.strong([class("fixture-status")], [text(status)])
    "", error -> html.strong([class("fixture-error")], [text(error)])
    _, error -> html.strong([class("fixture-error")], [text(error)])
  }
}

fn retry_response_fields(model: Model) -> Element(Msg) {
  case model.retry_responses {
    [] -> html.div([], [])
    responses ->
      html.div([class("retry-grid")], list.map(responses, retry_response_field))
  }
}

fn retry_response_field(response: RetryResponse) -> Element(Msg) {
  let #(index, content) = response
  let attempt = int.to_string(index)

  text_area(
    "Retry output " <> attempt,
    "retry_response_" <> attempt,
    content,
    "Optional provider response for attempt " <> attempt,
    fn(value) { RetryResponseChanged(index, value) },
  )
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
        id(field_name),
        name(field_name),
        rows(6),
        placeholder(hint),
        value(content),
        event.on_input(to_msg),
      ],
      content,
    ),
  ])
}

fn empty_retry_responses(model_id: String) -> List(RetryResponse) {
  retry_response_range(2, external_retry_response_slots(model_id) + 1)
}

fn custom_fixture_id() -> String {
  "custom"
}

fn default_fixture_id(pattern_id: String, model_id: String) -> String {
  case external_fixture_options(pattern_id, model_id) {
    [] -> "model-default"
    [option, ..] -> {
      let #(fixture_id, _, _, _, _, _) = option
      fixture_id
    }
  }
}

fn reset_fixture_id(model: Model) -> String {
  case model.fixture_id == custom_fixture_id() {
    True -> default_fixture_id(model.pattern_id, model.model_id)
    False -> model.fixture_id
  }
}

fn fixture_turn(
  pattern_id: String,
  model_id: String,
  fixture_id: String,
) -> #(String, String, List(RetryResponse)) {
  case selected_fixture(pattern_id, model_id, fixture_id) {
    #(user_input, model_response, retry_responses) -> #(
      user_input,
      model_response,
      retry_responses,
    )
  }
}

fn selected_fixture(
  pattern_id: String,
  model_id: String,
  fixture_id: String,
) -> #(String, String, List(RetryResponse)) {
  case fixture_id == custom_fixture_id() {
    True -> #(
      external_default_user_input(model_id),
      external_default_model_response(model_id),
      empty_retry_responses(model_id),
    )

    False ->
      selected_fixture_from(
        external_fixture_options(pattern_id, model_id),
        fixture_id,
        model_id,
      )
  }
}

fn selected_fixture_from(
  options: List(FixtureOption),
  fixture_id: String,
  model_id: String,
) -> #(String, String, List(RetryResponse)) {
  case options {
    [] -> #(
      external_default_user_input(model_id),
      external_default_model_response(model_id),
      empty_retry_responses(model_id),
    )

    [option, ..rest] -> {
      let #(option_id, _, _, user_input, model_response, retry_responses) =
        option

      case option_id == fixture_id {
        True -> #(user_input, model_response, retry_responses)
        False -> selected_fixture_from(rest, fixture_id, model_id)
      }
    }
  }
}

fn retry_response_range(index: Int, final_index: Int) -> List(RetryResponse) {
  case index > final_index {
    True -> []
    False -> [#(index, ""), ..retry_response_range(index + 1, final_index)]
  }
}

fn update_retry_response(
  responses: List(RetryResponse),
  index: Int,
  model_response: String,
) -> List(RetryResponse) {
  responses
  |> list.map(fn(response) {
    let #(response_index, existing_response) = response

    case response_index == index {
      True -> #(response_index, model_response)
      False -> #(response_index, existing_response)
    }
  })
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
    state_machine_graph(model),
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

fn state_machine_graph(model: Model) -> Element(Msg) {
  let simulation = model.simulation
  let replay = simulation.state_replay
  let active_state = active_state_at(replay, model.step)

  html.article([class("panel state-graph")], [
    html.div([class("panel-heading")], [
      html.div([class("status-stack")], [
        html.span([], [text("State machine")]),
        badge.badge([badge.variant(badge.Outline)], [
          text(blank_default(replay.status, "unknown")),
        ]),
        badge.badge([badge.variant(badge.Secondary)], [
          text(step_label(model)),
        ]),
        badge.badge([badge.variant(badge.Outline)], [
          text(path_label(replay)),
        ]),
      ]),
      html.div([class("graph-toolbar")], [
        policy_projection_select(model),
        playback_actions(model),
      ]),
    ]),
    element(
      "wardwright-state-graph",
      [
        class("state-cytoscape"),
        attribute(
          "data-states",
          state_graph_states_json(replay, active_state, model.step),
        ),
        attribute(
          "data-transitions",
          state_graph_transitions_json(replay, model.step),
        ),
        attribute("data-active-state", active_state),
        attribute("data-final-state", replay.final_state),
        attribute("data-model-id", model.model_id),
      ],
      [],
    ),
    html.details([class("state-evidence")], [
      html.summary([], [text("Transition evidence")]),
      html.div(
        [class("edge-list")],
        state_edge_rows(replay.transitions, active_state),
      ),
    ]),
  ])
}

fn state_graph_states_json(
  replay: StateReplay,
  active_state: String,
  step: Int,
) -> String {
  let visited_states = visited_state_ids(replay, step)

  replay.state_ids
  |> json.array(fn(state) {
    json.object([
      #("id", json.string(state)),
      #("label", json.string(state_label(state))),
      #("active", json.bool(state == active_state)),
      #("terminal", json.bool(state == replay.final_state)),
      #("visited", json.bool(list.contains(visited_states, state))),
    ])
  })
  |> json.to_string
}

fn state_graph_transitions_json(replay: StateReplay, step: Int) -> String {
  let path_steps = path_steps_at(replay.steps, step)
  let current_step = current_path_step(replay, step)

  replay.transitions
  |> list.index_map(fn(transition, index) {
    let #(from, event, to, action_name, node_id) = transition

    json.object([
      #("id", json.string("edge-" <> int.to_string(index))),
      #("from", json.string(from)),
      #("to", json.string(to)),
      #("event", json.string(blank_default(event, "event"))),
      #("action", json.string(blank_default(action_name, "pass"))),
      #("node", json.string(blank_default(node_id, "node"))),
      #("short_label", json.string(short_edge_label(event, action_name))),
      #("path", json.bool(transition_in_steps(transition, path_steps))),
      #(
        "current",
        json.bool(transition_matches_current(transition, current_step)),
      ),
      #(
        "detail",
        json.string(
          blank_default(event, "event")
          <> " / "
          <> blank_default(action_name, "pass")
          <> " / "
          <> blank_default(node_id, "node"),
        ),
      ),
    ])
  })
  |> json.array(fn(transition) { transition })
  |> json.to_string
}

fn path_label(replay: StateReplay) -> String {
  case replay.steps {
    [] -> "Path: none"
    _ -> "Path: " <> replay.initial_state <> " -> " <> replay.final_state
  }
}

fn visited_state_ids(replay: StateReplay, step: Int) -> List(String) {
  path_steps_at(replay.steps, step)
  |> collect_visited_state_ids([replay.initial_state])
  |> list.reverse
}

fn collect_visited_state_ids(
  steps: List(StateReplayStep),
  states: List(String),
) -> List(String) {
  case steps {
    [] -> states
    [step, ..rest] -> {
      let #(_, _, to, _, _, matched) = step

      case matched {
        True -> collect_visited_state_ids(rest, add_unique(states, to))
        False -> collect_visited_state_ids(rest, states)
      }
    }
  }
}

fn path_steps_at(
  steps: List(StateReplayStep),
  step_count: Int,
) -> List(StateReplayStep) {
  case step_count <= 0 {
    True -> []
    False ->
      case steps {
        [] -> []
        [step, ..rest] -> [step, ..path_steps_at(rest, step_count - 1)]
      }
  }
}

fn current_path_step(
  replay: StateReplay,
  step: Int,
) -> Result(StateReplayStep, Nil) {
  case step <= 0 {
    True -> Error(Nil)
    False ->
      case replay.steps |> list.drop(step - 1) |> list.first {
        Ok(step_row) -> Ok(step_row)
        Error(_) -> Error(Nil)
      }
  }
}

fn transition_in_steps(
  transition: projection_core.StateTransition,
  steps: List(StateReplayStep),
) -> Bool {
  case steps {
    [] -> False
    [step, ..rest] ->
      case transition_matches_step(transition, step) {
        True -> True
        False -> transition_in_steps(transition, rest)
      }
  }
}

fn transition_matches_current(
  transition: projection_core.StateTransition,
  current_step: Result(StateReplayStep, Nil),
) -> Bool {
  case current_step {
    Ok(step) -> transition_matches_step(transition, step)
    Error(_) -> False
  }
}

fn transition_matches_step(
  transition: projection_core.StateTransition,
  step: StateReplayStep,
) -> Bool {
  let #(from, event, to, action_name, node_id) = transition
  let #(step_from, step_event, step_to, step_action, step_node, matched) = step

  matched
  && from == step_from
  && event == step_event
  && to == step_to
  && action_name == step_action
  && node_id == step_node
}

fn short_edge_label(event: String, action_name: String) -> String {
  case string.trim(event) {
    "" -> blank_default(action_name, "transition")
    event_name -> event_name
  }
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
        table.table_column_header([], [text("Replay")]),
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
  let #(phase, label, detail, severity, _state_id) =
    active_trace_event(simulation, model.step)

  html.section([class("trace-panel")], [
    html.div([class("trace-header")], [
      html.div([], [
        html.strong([], [text("Trace playback")]),
        html.span([], [text(step_label(model))]),
      ]),
      playback_actions(model),
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

fn playback_actions(model: Model) -> Element(Msg) {
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
        disabled(model.step >= max_step(model.simulation)),
        event.on_click(StepForward),
      ],
      [text("Next step")],
    ),
  ])
}

fn step_label(model: Model) -> String {
  let playback_count = max_step(model.simulation) + 1

  "Step "
  <> int.to_string(model.step + 1)
  <> " of "
  <> int.to_string(int.max(playback_count, 1))
}

fn active_trace_event(simulation: Simulation, step: Int) -> TraceEvent {
  case simulation.trace_events |> list.drop(step) |> list.first {
    Ok(event) -> event
    Error(_) -> #("", "No trace event", "", "pass", "")
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

fn state_label(state: String) -> String {
  state
  |> string.replace(each: "::", with: " / ")
  |> string.replace(each: "_", with: " ")
  |> string.replace(each: "-", with: " ")
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

fn status_variant(changed: Bool) -> badge.Variant {
  case changed {
    True -> badge.Secondary
    False -> badge.Outline
  }
}

fn authoring_badge_variant(configured: Bool) -> badge.Variant {
  case configured {
    True -> badge.Secondary
    False -> badge.Outline
  }
}

fn authoring_response_variant(status: String) -> badge.Variant {
  case status {
    "error" -> badge.Destructive
    "not_configured" -> badge.Outline
    _ -> badge.Secondary
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

pub fn styles() -> String {
  lustre_shell.styles() <> "
  .lustre-workbench {
    min-height: 100vh;
    display: grid;
    grid-template-columns: minmax(260px, 320px) minmax(0, 1fr);
    background: var(--background);
    color: var(--foreground);
  }
  .form-header strong, .trace-header strong {
    font-size: 17px;
  }
  .form-header span, .trace-header span, .fact span, .authoring-meta span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
  }
  .field {
    gap: 8px;
  }
  .projection-field > span {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .help-dot {
    display: inline-grid;
    place-items: center;
    width: 18px;
    height: 18px;
    border: 1px solid var(--border);
    border-radius: 999px;
    background: #fff;
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 900;
    cursor: help;
  }
  .runtime-note {
    margin-top: auto;
  }
  .workspace {
    display: flex;
    flex-direction: column;
    gap: 18px;
    min-width: 0;
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
    overflow-wrap: anywhere;
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
  .form-header .actions {
    flex-direction: row;
  }
  .simulator-toolbar {
    display: grid !important;
    grid-template-columns: minmax(260px, 420px) max-content;
    gap: 12px;
    align-items: end;
    min-width: 0;
  }
  .graph-toolbar {
    display: grid;
    grid-template-columns: minmax(240px, 380px) max-content;
    gap: 12px;
    align-items: end;
    min-width: min(100%, 560px);
  }
  .simulator, .authoring-panel, .panel, .trace-panel {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 16px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--card);
  }
  .fixture-save {
    display: grid;
    grid-template-columns: minmax(220px, 320px) max-content minmax(240px, 1fr);
    gap: 10px;
    align-items: end;
    padding-top: 4px;
  }
  .fixture-note, .fixture-status, .fixture-error {
    align-self: center;
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.35;
  }
  .fixture-status {
    color: var(--primary);
  }
  .fixture-error {
    color: var(--destructive);
  }
  .authoring-panel {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .authoring-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    min-width: 0;
  }
  .authoring-meta span {
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 5px 8px;
    background: #fff;
    overflow-wrap: anywhere;
  }
  .authoring-form {
    display: grid;
    gap: 10px;
  }
  .authoring-live {
    display: grid;
    gap: 14px;
  }
  .authoring-response, .authoring-empty, .authoring-setup {
    display: grid;
    gap: 10px;
    border: 1px solid #dbe5ed;
    border-radius: 8px;
    background: #f8fbfd;
    padding: 12px;
  }
  .authoring-empty, .authoring-setup {
    color: var(--muted-foreground);
    font-size: 13px;
    line-height: 1.45;
  }
  .authoring-empty {
    font-weight: 700;
  }
  .authoring-setup strong {
    color: var(--foreground);
  }
  .authoring-setup p, .authoring-setup ul {
    margin: 0;
  }
  .authoring-setup ul {
    padding-left: 18px;
  }
  .authoring-setup code {
    color: var(--foreground);
    font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  }
  .authoring-response pre {
    margin: 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    color: #354554;
  }
  .authoring-draft {
    display: grid;
    gap: 4px;
    border: 1px solid #b9d9c9;
    border-radius: 8px;
    background: #f0fbf5;
    padding: 10px;
  }
  .authoring-draft span {
    color: #435261;
    font-size: 12px;
    line-height: 1.4;
  }
  .authoring-draft small {
    color: #53616f;
    line-height: 1.4;
  }
  .authoring-draft-artifact {
    border-top: 1px solid #d6eadf;
    padding-top: 8px;
  }
  .authoring-draft-artifact summary {
    cursor: pointer;
    font-weight: 700;
    color: #1d3f2d;
  }
  .authoring-draft-artifact pre {
    max-height: 280px;
    overflow: auto;
    margin-top: 8px;
    padding: 10px;
    border-radius: 6px;
    background: #ffffff;
    border: 1px solid #d6eadf;
  }
  .turn-grid, .results {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16px;
  }
  .results {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .editor textarea, textarea, select, input {
    width: 100%;
    max-width: 100%;
    min-width: 0;
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
    overflow: hidden;
    text-overflow: ellipsis;
    padding: 8px 34px 8px 10px;
  }
  input {
    min-height: 40px;
    padding: 8px 10px;
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
  .state-cytoscape {
    display: block;
    min-height: 460px;
  }
  .state-evidence {
    border: 1px solid #e1e7ed;
    border-radius: 8px;
    background: #fbfcfd;
  }
  .state-evidence summary {
    cursor: pointer;
    padding: 10px 12px;
    color: #46525f;
    font-size: 12px;
    font-weight: 800;
  }
  .edge-list {
    display: grid;
    gap: 8px;
    padding: 0 12px 12px;
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
    width: 100%;
    max-width: 100%;
    table-layout: fixed;
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
    overflow-wrap: anywhere;
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
    .workspace {
      padding: 18px;
    }
    .rail {
      border-right: 0;
      border-bottom: 1px solid var(--border);
    }
    .topbar, .form-header, .trace-header, .turn-grid, .results, .state-edge, .simulator-toolbar, .graph-toolbar, .fixture-save, .authoring-meta {
      grid-template-columns: 1fr;
      flex-direction: column;
      min-width: 0;
    }
  }
  "
}
