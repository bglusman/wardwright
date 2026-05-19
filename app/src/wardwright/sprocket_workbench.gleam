import gleam/list
import gleam/option.{Some}
import sprocket/html/attributes as attr
import sprocket/html/elements as html
import sprocket/render
import sprocket/renderers/html as html_renderer

pub type WorkbenchStatus {
  Passed
  Warning
  Blocked
  Neutral
}

pub type StepState {
  Past
  Current
  Future
}

pub fn status_class(status: String) -> String {
  case classify_status(status) {
    Passed -> "ok"
    Warning -> "warn"
    Blocked -> "danger"
    Neutral -> "neutral"
  }
}

pub fn status_label(status: String) -> String {
  case classify_status(status) {
    Passed -> "Passed"
    Warning -> "Needs review"
    Blocked -> "Blocked"
    Neutral -> "Observed"
  }
}

pub fn step_state(index: Int, selected_step: Int) -> String {
  case index < selected_step, index == selected_step {
    True, _ -> step_state_label(Past)
    _, True -> step_state_label(Current)
    _, _ -> step_state_label(Future)
  }
}

pub fn summary_rows(
  pattern_title: String,
  mode_label: String,
  model_id: String,
  recipe_label: String,
  projection_schema: String,
  simulation_schema: String,
  artifact_hash: String,
  verdict: String,
  trace_count: Int,
  coverage_gap_count: Int,
) -> List(#(String, String, String)) {
  [
    #("Pattern", pattern_title, "neutral"),
    #("View", mode_label, "neutral"),
    #("Model", blank_default(model_id, "default model"), "neutral"),
    #("Recipe", blank_default(recipe_label, "direct pattern"), "neutral"),
    #("Projection", projection_schema, "neutral"),
    #("Simulation", simulation_schema, "neutral"),
    #("Artifact", artifact_hash, "neutral"),
    #("Verdict", status_label(verdict), status_class(verdict)),
    #("Trace events", int_to_string(trace_count), "neutral"),
    #(
      "Coverage gaps",
      int_to_string(coverage_gap_count),
      coverage_class(coverage_gap_count),
    ),
  ]
}

pub fn trace_rows(
  trace: List(#(String, String, String, String, String)),
  selected_step: Int,
) -> List(#(String, String, String, String, String, String, String)) {
  trace_rows_loop(trace, selected_step, 0, [])
}

pub fn option_rows(
  options: List(#(String, String, String)),
  selected_id: String,
) -> List(#(String, String, String, String)) {
  option_rows_loop(options, selected_id, [])
}

pub fn boundary_rows(
  user_input: String,
  model_received_input: String,
  model_response: String,
  user_received_output: String,
) -> List(#(String, String, String)) {
  [
    #("Caller input", blank_default(user_input, "(empty)"), "request"),
    #(
      "Model receives",
      blank_default(model_received_input, "(same as caller input)"),
      "request",
    ),
    #("Backend output", blank_default(model_response, "(empty)"), "response"),
    #(
      "User receives",
      blank_default(user_received_output, "(same as backend output)"),
      "response",
    ),
  ]
}

pub fn capability_rows(
  request_rewrites: Int,
  response_rewrites: Int,
  released_to_consumer: Bool,
  trigger_count: Int,
  scenario_count: Int,
  model_count: Int,
) -> List(#(String, String, String)) {
  [
    #(
      "Request rewrites",
      int_to_string(request_rewrites),
      count_class(request_rewrites),
    ),
    #(
      "Response rewrites",
      int_to_string(response_rewrites),
      count_class(response_rewrites),
    ),
    #(
      "Released",
      bool_label(released_to_consumer),
      release_class(released_to_consumer),
    ),
    #(
      "Stream triggers",
      int_to_string(trigger_count),
      count_class(trigger_count),
    ),
    #("Scenarios", int_to_string(scenario_count), "neutral"),
    #("Models", int_to_string(model_count), "neutral"),
  ]
}

pub fn document_html(
  css: String,
  summary_rows: List(#(String, String, String)),
  boundary_rows: List(#(String, String, String)),
  capability_rows: List(#(String, String, String)),
  trace_rows: List(#(String, String, String, String, String, String, String)),
  pattern_options: List(#(String, String, String, String)),
  mode_options: List(#(String, String, String, String)),
  model_options: List(#(String, String, String, String)),
  scenario_options: List(#(String, String, String, String)),
  simulation_title: String,
  expected_behavior: String,
  selected_step_label: String,
  prev_step_url: String,
  next_step_url: String,
  reset_step_url: String,
) -> String {
  let document =
    html.html([attr.lang("en")], [
      html.head([], [
        html.meta([attr.charset("utf-8")]),
        html.meta([
          attr.name("viewport"),
          attr.content("width=device-width, initial-scale=1"),
        ]),
        html.title("Wardwright Sprocket Workbench Spike"),
        html.style([], Some(css)),
      ]),
      html.body([], [
        html.main([attr.class("page")], [
          masthead(),
          html.section([attr.class("workspace")], [
            html.nav(
              [
                attr.class("rail"),
                attr.attribute("aria-label", "Workbench selectors"),
              ],
              [
                option_group("Patterns", pattern_options),
                option_group("Views", mode_options),
                option_group("Models", model_options),
                option_group("Scenarios", scenario_options),
              ],
            ),
            html.section([attr.class("canvas")], [
              html.div(
                [attr.class("summary-grid")],
                list.map(summary_rows, summary_card),
              ),
              html.section([attr.class("stage")], [
                html.div([attr.class("stage-main")], [
                  section_heading(
                    "Simulation boundary",
                    simulation_title,
                    expected_behavior,
                  ),
                  html.div(
                    [attr.class("boundary-grid")],
                    list.map(boundary_rows, boundary_card),
                  ),
                ]),
                html.aside([attr.class("stage-side")], [
                  html.h2([], [html.text("Runtime Effects")]),
                  html.dl(
                    [attr.class("capability-list")],
                    list.map(capability_rows, capability_row),
                  ),
                ]),
              ]),
              html.section([attr.class("trace-panel")], [
                trace_heading(
                  selected_step_label,
                  prev_step_url,
                  next_step_url,
                  reset_step_url,
                ),
                html.ol(
                  [attr.class("trace-list")],
                  list.map(trace_rows, trace_row),
                ),
              ]),
            ]),
          ]),
        ]),
      ]),
    ])

  render.render_element(document, html_renderer.html_renderer())
}

fn masthead() {
  html.header([attr.class("masthead")], [
    html.div([], [
      html.p([attr.class("eyebrow")], [
        html.text("Sprocket + Gleam runtime spike"),
      ]),
      html.h1([], [html.text("Policy Workbench, Re-modeled")]),
      html.p([attr.class("lede")], [
        html.text(
          "This page uses Sprocket elements and a typed Gleam view model over the same Wardwright projection and simulation records as the LiveView workbench.",
        ),
      ]),
    ]),
    html.aside([attr.class("runtime-note")], [
      html.strong([], [html.text("Dependency caveat")]),
      html.span([], [
        html.text(
          "This spike downgrades gleam_stdlib to 0.x so Sprocket 2.1.0 can compile. That makes it useful for evaluation, not ready to merge as product code.",
        ),
      ]),
    ]),
  ])
}

fn section_heading(eyebrow: String, title: String, detail: String) {
  html.div([attr.class("section-heading")], [
    html.p([attr.class("eyebrow")], [html.text(eyebrow)]),
    html.h2([], [html.text(title)]),
    html.p([], [html.text(detail)]),
  ])
}

fn trace_heading(
  step_label: String,
  prev_step_url: String,
  next_step_url: String,
  reset_step_url: String,
) {
  html.div([attr.class("section-heading row")], [
    html.div([], [
      html.p([attr.class("eyebrow")], [html.text(step_label)]),
      html.h2([], [html.text("Trace playback")]),
    ]),
    html.div([attr.class("step-controls")], [
      html.a([attr.href(prev_step_url)], [html.text("Back")]),
      html.a([attr.href(next_step_url)], [html.text("Next")]),
      html.a([attr.href(reset_step_url)], [html.text("Reset")]),
    ]),
  ])
}

fn option_group(title: String, rows: List(#(String, String, String, String))) {
  html.section([attr.class("selector-group")], [
    html.h2([], [html.text(title)]),
    html.div([], list.map(rows, option_link)),
  ])
}

fn option_link(row: #(String, String, String, String)) {
  let #(label, url, state, id) = row

  html.a(
    [
      attr.class("selector " <> state),
      attr.href(url),
      attr.attribute("data-option-id", id),
    ],
    [html.text(label)],
  )
}

fn summary_card(row: #(String, String, String)) {
  let #(label, value, status) = row

  html.article([attr.class("summary " <> status)], [
    html.p([], [html.text(label)]),
    html.strong([], [html.text(value)]),
  ])
}

fn boundary_card(row: #(String, String, String)) {
  let #(label, value, direction) = row

  html.article([attr.class("boundary " <> direction)], [
    html.h3([], [html.text(label)]),
    html.pre([], [html.text(value)]),
  ])
}

fn capability_row(row: #(String, String, String)) {
  let #(label, value, status) = row

  html.div([attr.class(status)], [
    html.dt([], [html.text(label)]),
    html.dd([], [html.text(value)]),
  ])
}

fn trace_row(row: #(String, String, String, String, String, String, String)) {
  let #(index, step_state, phase, event_type, label, detail, status) = row

  html.li([attr.class("trace-row " <> step_state <> " " <> status)], [
    html.span([attr.class("trace-index")], [html.text(index)]),
    html.div([], [
      html.p([], [
        html.strong([], [html.text(label)]),
        html.text(" "),
        html.span([], [html.text(phase <> " · " <> event_type)]),
      ]),
      html.small([], [html.text(detail)]),
    ]),
  ])
}

fn trace_rows_loop(
  trace: List(#(String, String, String, String, String)),
  selected_step: Int,
  index: Int,
  acc: List(#(String, String, String, String, String, String, String)),
) -> List(#(String, String, String, String, String, String, String)) {
  case trace {
    [] -> reverse(acc)
    [event, ..rest] -> {
      let #(phase, event_type, label, detail, status) = event
      let row = #(
        int_to_string(index + 1),
        step_state(index, selected_step),
        phase,
        event_type,
        label,
        detail,
        status_class(status),
      )

      trace_rows_loop(rest, selected_step, index + 1, [row, ..acc])
    }
  }
}

fn option_rows_loop(
  options: List(#(String, String, String)),
  selected_id: String,
  acc: List(#(String, String, String, String)),
) -> List(#(String, String, String, String)) {
  case options {
    [] -> reverse(acc)
    [option, ..rest] -> {
      let #(id, label, url) = option
      let state = case id == selected_id {
        True -> "selected"
        False -> "available"
      }

      option_rows_loop(rest, selected_id, [#(label, url, state, id), ..acc])
    }
  }
}

fn classify_status(status: String) -> WorkbenchStatus {
  case status {
    "pass" | "passed" | "ok" | "success" | "released" -> Passed
    "warn" | "warning" | "coverage_gap" | "review" -> Warning
    "block" | "blocked" | "fail" | "failed" | "error" -> Blocked
    _ -> Neutral
  }
}

fn step_state_label(state: StepState) -> String {
  case state {
    Past -> "past"
    Current -> "current"
    Future -> "future"
  }
}

fn count_class(count: Int) -> String {
  case count {
    0 -> "neutral"
    _ -> "warn"
  }
}

fn coverage_class(count: Int) -> String {
  case count {
    0 -> "ok"
    _ -> "warn"
  }
}

fn release_class(released: Bool) -> String {
  case released {
    True -> "ok"
    False -> "danger"
  }
}

fn bool_label(value: Bool) -> String {
  case value {
    True -> "yes"
    False -> "no"
  }
}

fn blank_default(value: String, default: String) -> String {
  case value {
    "" -> default
    _ -> value
  }
}

fn reverse(items: List(a)) -> List(a) {
  reverse_loop(items, [])
}

fn reverse_loop(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [item, ..rest] -> reverse_loop(rest, [item, ..acc])
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(value: Int) -> String
