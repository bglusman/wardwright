import act.{type Action}
import gleam/list
import non_empty_list
import trie.{type Trie}

pub type Transition {
  Transition(
    from: String,
    event: String,
    to: String,
    action: String,
    rule_id: String,
  )
}

type Machine {
  Machine(
    initial_state: String,
    transition_count: Int,
    index: Trie(String, Transition),
  )
}

type Step {
  Step(
    from: String,
    event: String,
    to: String,
    action: String,
    rule_id: String,
    matched: Bool,
  )
}

type SimulationState {
  SimulationState(active_state: String, steps: List(Step))
}

type MachineError {
  BlankInitialState
  EmptyTransitionTable
  EmptyTransitionField(field: String)
  DuplicateTransition(from: String, event: String)
}

pub fn transition_table_status(
  initial_state: String,
  transition_rows: List(#(String, String, String, String, String)),
) -> #(String, Int) {
  case build_machine(initial_state, transition_rows) {
    Ok(machine) -> #("ok", machine.transition_count)
    Error(error) -> #(error_status(error), 0)
  }
}

pub fn simulate(
  initial_state: String,
  transition_rows: List(#(String, String, String, String, String)),
  events: List(String),
) -> #(String, String, List(#(String, String, String, String, String, Bool))) {
  case build_machine(initial_state, transition_rows) {
    Ok(machine) -> {
      let final_state = run_simulation(machine, events)
      #(
        "ok",
        final_state.active_state,
        list.map(final_state.steps, step_to_row),
      )
    }
    Error(error) -> #(error_status(error), initial_state, [])
  }
}

fn build_machine(
  initial_state: String,
  transition_rows: List(#(String, String, String, String, String)),
) -> Result(Machine, MachineError) {
  case initial_state {
    "" -> Error(BlankInitialState)
    _ -> {
      let transitions = list.map(transition_rows, transition_from_row)

      case non_empty_list.from_list(transitions) {
        Error(_) -> Error(EmptyTransitionTable)
        Ok(non_empty_transitions) ->
          case validate_transition_fields(transitions) {
            Error(error) -> Error(error)
            Ok(_) ->
              case index_transitions(non_empty_transitions) {
                Error(error) -> Error(error)
                Ok(index) ->
                  Ok(Machine(
                    initial_state: initial_state,
                    transition_count: non_empty_list.length(
                      non_empty_transitions,
                    ),
                    index: index,
                  ))
              }
          }
      }
    }
  }
}

fn transition_from_row(
  row: #(String, String, String, String, String),
) -> Transition {
  let #(from, event, to, action, rule_id) = row
  Transition(from: from, event: event, to: to, action: action, rule_id: rule_id)
}

fn validate_transition_fields(
  transitions: List(Transition),
) -> Result(Nil, MachineError) {
  case transitions {
    [] -> Ok(Nil)
    [transition, ..rest] ->
      case validate_transition(transition) {
        Ok(_) -> validate_transition_fields(rest)
        Error(error) -> Error(error)
      }
  }
}

fn validate_transition(transition: Transition) -> Result(Nil, MachineError) {
  case transition {
    Transition(from: "", ..) -> Error(EmptyTransitionField("from"))
    Transition(event: "", ..) -> Error(EmptyTransitionField("event"))
    Transition(to: "", ..) -> Error(EmptyTransitionField("to"))
    Transition(action: "", ..) -> Error(EmptyTransitionField("action"))
    Transition(rule_id: "", ..) -> Error(EmptyTransitionField("rule_id"))
    _ -> Ok(Nil)
  }
}

fn index_transitions(
  transitions: non_empty_list.NonEmptyList(Transition),
) -> Result(Trie(String, Transition), MachineError) {
  non_empty_list.fold(
    over: transitions,
    from: Ok(trie.new()),
    with: fn(acc, transition) {
      case acc {
        Error(error) -> Error(error)
        Ok(index) -> {
          let path = transition_path(transition)

          case trie.get(index, at: path) {
            Ok(_) ->
              Error(DuplicateTransition(
                from: transition.from,
                event: transition.event,
              ))
            Error(_) ->
              Ok(trie.insert(into: index, at: path, value: transition))
          }
        }
      }
    },
  )
}

fn transition_path(transition: Transition) -> List(String) {
  [transition.from, transition.event]
}

fn run_simulation(machine: Machine, events: List(String)) -> SimulationState {
  let initial_state =
    SimulationState(active_state: machine.initial_state, steps: [])

  events
  |> list.map(fn(event) { apply_event(machine, event) })
  |> act.each
  |> act.exec(with: initial_state)
  |> chronological_steps
}

fn apply_event(
  machine: Machine,
  event: String,
) -> Action(Nil, SimulationState) {
  act.update_state(fn(state: SimulationState) {
    let step = next_step(machine, state.active_state, event)
    SimulationState(active_state: step.to, steps: [step, ..state.steps])
  })
}

fn next_step(machine: Machine, active_state: String, event: String) -> Step {
  case trie.get(machine.index, at: [active_state, event]) {
    Ok(transition) ->
      Step(
        from: active_state,
        event: event,
        to: transition.to,
        action: transition.action,
        rule_id: transition.rule_id,
        matched: True,
      )
    Error(_) ->
      Step(
        from: active_state,
        event: event,
        to: active_state,
        action: "no_op",
        rule_id: "",
        matched: False,
      )
  }
}

fn chronological_steps(state: SimulationState) -> SimulationState {
  SimulationState(
    active_state: state.active_state,
    steps: list.reverse(state.steps),
  )
}

fn step_to_row(step: Step) -> #(String, String, String, String, String, Bool) {
  #(step.from, step.event, step.to, step.action, step.rule_id, step.matched)
}

fn error_status(error: MachineError) -> String {
  case error {
    BlankInitialState -> "blank_initial_state"
    EmptyTransitionTable -> "empty_transition_table"
    EmptyTransitionField(field) -> "empty_transition_field:" <> field
    DuplicateTransition(from, event) ->
      "duplicate_transition:" <> from <> ":" <> event
  }
}
