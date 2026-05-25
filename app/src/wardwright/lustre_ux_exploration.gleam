import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{attribute, class, role, type_}
import lustre/element.{type Element, element, map, text}
import lustre/element/html
import lustre/event
import ui/tabs as tabs_ui
import wardwright/lustre_model_access

pub type Concept {
  ModelConfigCleanup
  CapabilityCommandCenter
  RouteTopologyMap
  GuidedChangeReview
  HolisticControlRoom
}

pub type Theme {
  Operations
  Studio
  Topology
  Review
}

pub type Model {
  Model(concept: Concept, theme: Theme, model_access: lustre_model_access.Model)
}

pub type Msg {
  ThemeChanged(Theme)
  ModelAccessMsg(lustre_model_access.Msg)
}

pub fn init(flags: String) -> Model {
  let #(concept, model_id) = parse_flags(flags)

  Model(
    concept:,
    theme: default_theme(concept),
    model_access: lustre_model_access.init(model_id),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    ThemeChanged(theme) -> Model(..model, theme:)
    ModelAccessMsg(msg) ->
      Model(
        ..model,
        model_access: lustre_model_access.update(model.model_access, msg),
      )
  }
}

pub fn workspace(model: Model) -> Element(Msg) {
  html.main([class("workspace ux-workspace " <> theme_class(model.theme))], [
    header(model),
    controls(model),
    concept_body(model),
  ])
}

pub fn sidebar_controls(model: Model) -> List(Element(Msg)) {
  let #(mode, guaranteed_tools, conditional_tools) =
    model.model_access.tool_advertisement

  [
    html.div([class("sidebar-footer")], [
      html.span([], [text("UX concept")]),
      html.strong([], [text(concept_label(model.concept))]),
      html.span([], [text("Visual theme")]),
      html.code([], [text(theme_label(model.theme))]),
      html.span([], [text("Selected model")]),
      html.code([], [text(model.model_access.model_id)]),
      html.span([], [text("Advertise")]),
      html.code([], [
        text(
          mode
          <> " / "
          <> int.to_string(guaranteed_tools)
          <> "+"
          <> int.to_string(conditional_tools),
        ),
      ]),
    ]),
  ]
}

fn header(model: Model) -> Element(Msg) {
  html.header([class("ux-header")], [
    html.div([], [
      html.p([class("eyebrow")], [text("Live UX exploration")]),
      html.h1([], [text(concept_label(model.concept))]),
      html.p([], [
        text(
          "These alternatives reuse live Wardwright model controls and data. Switch themes independently to compare layout and visual direction.",
        ),
      ]),
    ]),
    html.div([class("ux-header-actions")], [
      link_button(
        "/admin?view=model_access&model=" <> model.model_access.model_id,
        "Open production model page",
      ),
      link_button("/admin?model=" <> model.model_access.model_id, "Run lab"),
    ]),
  ])
}

fn controls(model: Model) -> Element(Msg) {
  html.section([class("ux-controls")], [
    html.div([class("ux-control-group")], [
      html.span([], [text("Layout concept")]),
      tabs_ui.tab_list([class("ux-tabs")], concept_links(model)),
    ]),
    html.div([class("ux-control-group")], [
      html.span([], [text("Visual theme")]),
      tabs_ui.tabs([], [
        tabs_ui.tab_list([class("ux-tabs")], theme_buttons(model.theme)),
      ]),
    ]),
  ])
}

fn concept_links(model: Model) -> List(Element(Msg)) {
  [
    concept_link(model, ModelConfigCleanup),
    concept_link(model, CapabilityCommandCenter),
    concept_link(model, RouteTopologyMap),
    concept_link(model, GuidedChangeReview),
    concept_link(model, HolisticControlRoom),
  ]
}

fn concept_link(model: Model, concept: Concept) -> Element(Msg) {
  element(
    "a",
    [
      class(case model.concept == concept {
        True -> "ux-tab active"
        False -> "ux-tab"
      }),
      role("tab"),
      attribute("aria-selected", bool_string(model.concept == concept)),
      attribute("href", concept_href(concept, model.model_access.model_id)),
    ],
    [text(concept_short_label(concept))],
  )
}

fn theme_buttons(selected_theme: Theme) -> List(Element(Msg)) {
  [
    theme_button(selected_theme, Operations),
    theme_button(selected_theme, Studio),
    theme_button(selected_theme, Topology),
    theme_button(selected_theme, Review),
  ]
}

fn theme_button(selected_theme: Theme, theme: Theme) -> Element(Msg) {
  tabs_ui.tab(
    [
      class(case selected_theme == theme {
        True -> "ux-tab active"
        False -> "ux-tab"
      }),
      tabs_ui.tab_selected(selected_theme == theme),
      type_("button"),
      event.on_click(ThemeChanged(theme)),
    ],
    [text(theme_label(theme))],
  )
}

fn concept_body(model: Model) -> Element(Msg) {
  case model.concept {
    ModelConfigCleanup -> model_config_cleanup(model.model_access)
    CapabilityCommandCenter -> capability_command_center(model.model_access)
    RouteTopologyMap -> route_topology_map(model.model_access)
    GuidedChangeReview -> guided_change_review(model.model_access)
    HolisticControlRoom -> holistic_control_room(model.model_access)
  }
}

fn model_config_cleanup(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  html.section([class("ux-layout config-cleanup")], [
    html.div([class("ux-live-panel")], [
      map(lustre_model_access.model_summary(model_access), ModelAccessMsg),
    ]),
    html.div([class("ux-live-panel")], [
      map(
        lustre_model_access.access_policy_editor(model_access),
        ModelAccessMsg,
      ),
    ]),
    html.div([class("ux-live-panel wide")], [
      map(lustre_model_access.server_tools_panel(model_access), ModelAccessMsg),
    ]),
  ])
}

fn capability_command_center(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  let #(mode, guaranteed_tools, conditional_tools) =
    model_access.tool_advertisement

  html.section([class("ux-layout capability-command")], [
    html.article([class("ux-masthead")], [
      html.p([class("eyebrow")], [text("Agent-visible contract")]),
      html.h2([], [text(model_access.model_id)]),
      html.p([], [
        text(
          "The first question is what an agent can rely on, then which target differences change that promise.",
        ),
      ]),
    ]),
    score_card("Advertise", mode),
    score_card("Guaranteed tools", int.to_string(guaranteed_tools)),
    score_card("Conditional tools", int.to_string(conditional_tools)),
    html.div([class("ux-live-panel wide")], [
      map(lustre_model_access.server_tools_panel(model_access), ModelAccessMsg),
    ]),
  ])
}

fn route_topology_map(model_access: lustre_model_access.Model) -> Element(Msg) {
  html.section([class("ux-layout topology-map")], [
    html.article([class("ux-route-map")], [
      route_node("Stable model", model_access.model_id, "contract"),
      route_node("Access", access_label(model_access), "caller gate"),
      route_node(
        "Server tools",
        int.to_string(list.length(model_access.server_tools)),
        "Wardwright hosted",
      ),
      route_node("Replay", model_access.vcr_mode, "evidence"),
      ..target_nodes(model_access.server_tool_targets)
    ]),
    html.div([class("ux-live-panel")], [
      map(lustre_model_access.model_summary(model_access), ModelAccessMsg),
    ]),
    html.div([class("ux-live-panel")], [
      map(lustre_model_access.server_tools_panel(model_access), ModelAccessMsg),
    ]),
  ])
}

fn guided_change_review(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  html.section([class("ux-layout guided-review")], [
    review_step("1", "Choose model contract", model_access.model_id),
    review_step("2", "Confirm access", access_label(model_access)),
    review_step(
      "3",
      "Confirm tool advertisement",
      advertisement_label(model_access),
    ),
    review_step("4", "Capture evidence", model_access.vcr_mode),
    html.div([class("ux-live-panel")], [
      map(
        lustre_model_access.access_policy_editor(model_access),
        ModelAccessMsg,
      ),
    ]),
    html.div([class("ux-live-panel")], [
      map(lustre_model_access.server_tools_panel(model_access), ModelAccessMsg),
    ]),
  ])
}

fn holistic_control_room(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  html.section([class("ux-layout control-room")], [
    html.article([class("ux-masthead wide")], [
      html.p([class("eyebrow")], [text("Whole-product workspace")]),
      html.h2([], [text("Control Room")]),
      html.p([], [
        text(
          "A single operator workspace can combine model contract, policy, tools, replay evidence, and release checks without hiding the current production controls.",
        ),
      ]),
    ]),
    html.div([class("ux-live-panel")], [
      map(lustre_model_access.model_summary(model_access), ModelAccessMsg),
    ]),
    html.div([class("ux-live-panel")], [
      map(
        lustre_model_access.access_policy_editor(model_access),
        ModelAccessMsg,
      ),
    ]),
    html.div([class("ux-live-panel wide")], [
      map(lustre_model_access.server_tools_panel(model_access), ModelAccessMsg),
    ]),
    html.article([class("ux-link-panel")], [
      html.h2([], [text("Evidence")]),
      html.p([], [
        text(
          "Open replay, run the lab, and compare package/browser smoke before promoting a change.",
        ),
      ]),
      link_button(
        "/admin?view=control_debugger&model=" <> model_access.model_id,
        "Open replay",
      ),
    ]),
  ])
}

fn score_card(label: String, value: String) -> Element(Msg) {
  html.article([class("ux-score-card")], [
    html.span([], [text(label)]),
    html.strong([], [text(value)]),
  ])
}

fn route_node(label: String, value: String, detail: String) -> Element(Msg) {
  html.div([class("ux-route-node")], [
    html.span([], [text(label)]),
    html.strong([], [text(value)]),
    html.small([], [text(detail)]),
  ])
}

fn target_nodes(targets) -> List(Element(Msg)) {
  targets
  |> list.map(fn(target) {
    let #(target_model, kind, support) = target
    route_node(target_model, kind, support)
  })
}

fn review_step(number: String, label: String, value: String) -> Element(Msg) {
  html.article([class("ux-review-step")], [
    html.span([class("ux-step-number")], [text(number)]),
    html.div([], [
      html.h2([], [text(label)]),
      html.p([], [text(value)]),
    ]),
  ])
}

fn link_button(href: String, label: String) -> Element(Msg) {
  element("a", [class("ux-link-button"), attribute("href", href)], [text(label)])
}

fn access_label(model_access: lustre_model_access.Model) -> String {
  case model_access.requires_api_key {
    True -> "keyed"
    False -> model_access.unkeyed_access
  }
}

fn advertisement_label(model_access: lustre_model_access.Model) -> String {
  let #(mode, guaranteed_tools, conditional_tools) =
    model_access.tool_advertisement

  mode
  <> " / guaranteed "
  <> int.to_string(guaranteed_tools)
  <> " / conditional "
  <> int.to_string(conditional_tools)
}

fn parse_flags(flags: String) -> #(Concept, String) {
  case string.split(flags, ":") {
    ["ux_exploration", concept_id, model_id] -> #(
      concept_from_id(concept_id),
      model_id,
    )
    ["ux_exploration", concept_id] -> #(concept_from_id(concept_id), "")
    ["ux_exploration"] -> #(HolisticControlRoom, "")
    _ -> #(HolisticControlRoom, "")
  }
}

fn concept_from_id(id: String) -> Concept {
  case id {
    "model-config-cleanup" -> ModelConfigCleanup
    "capability-command-center" -> CapabilityCommandCenter
    "route-topology-map" -> RouteTopologyMap
    "guided-change-review" -> GuidedChangeReview
    "holistic-control-room" -> HolisticControlRoom
    _ -> HolisticControlRoom
  }
}

fn concept_id(concept: Concept) -> String {
  case concept {
    ModelConfigCleanup -> "model-config-cleanup"
    CapabilityCommandCenter -> "capability-command-center"
    RouteTopologyMap -> "route-topology-map"
    GuidedChangeReview -> "guided-change-review"
    HolisticControlRoom -> "holistic-control-room"
  }
}

fn concept_label(concept: Concept) -> String {
  case concept {
    ModelConfigCleanup -> "Current Model Config Cleanup"
    CapabilityCommandCenter -> "Capability Command Center"
    RouteTopologyMap -> "Route Topology Map"
    GuidedChangeReview -> "Guided Change Review"
    HolisticControlRoom -> "Holistic Control Room"
  }
}

fn concept_short_label(concept: Concept) -> String {
  case concept {
    ModelConfigCleanup -> "Config"
    CapabilityCommandCenter -> "Capability"
    RouteTopologyMap -> "Topology"
    GuidedChangeReview -> "Review"
    HolisticControlRoom -> "Control Room"
  }
}

fn concept_href(concept: Concept, model_id: String) -> String {
  let base = "/admin/ux-exploration/" <> concept_id(concept)

  case model_id {
    "" -> base
    _ -> base <> "?model=" <> model_id
  }
}

fn default_theme(concept: Concept) -> Theme {
  case concept {
    ModelConfigCleanup -> Operations
    CapabilityCommandCenter -> Studio
    RouteTopologyMap -> Topology
    GuidedChangeReview -> Review
    HolisticControlRoom -> Operations
  }
}

fn theme_label(theme: Theme) -> String {
  case theme {
    Operations -> "Operations"
    Studio -> "Studio"
    Topology -> "Topology"
    Review -> "Review"
  }
}

fn theme_class(theme: Theme) -> String {
  case theme {
    Operations -> "theme-operations"
    Studio -> "theme-studio"
    Topology -> "theme-topology"
    Review -> "theme-review"
  }
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

pub fn styles() -> String {
  "
  .ux-workspace {
    --ux-panel: #ffffff;
    --ux-panel-soft: #f7fbfc;
    --ux-ink: #18202a;
    --ux-accent: #16605a;
    --ux-accent-2: #245a82;
    --ux-line: #d7dde3;
  }
  .ux-workspace.theme-studio {
    --ux-panel-soft: #fff8ea;
    --ux-accent: #8b4f00;
    --ux-accent-2: #7b3b5f;
  }
  .ux-workspace.theme-topology {
    --ux-panel-soft: #eef5ff;
    --ux-accent: #245a82;
    --ux-accent-2: #16605a;
  }
  .ux-workspace.theme-review {
    --ux-panel-soft: #f4f2ff;
    --ux-accent: #5541a5;
    --ux-accent-2: #915930;
  }
  .ux-header {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 16px;
    align-items: end;
  }
  .ux-header p {
    max-width: 760px;
  }
  .ux-header-actions, .ux-controls {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
  }
  .ux-control-group {
    display: grid;
    gap: 6px;
  }
  .ux-control-group > span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .ux-tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    border: 0;
  }
  .ux-tab, .ux-link-button {
    display: inline-flex;
    min-height: 38px;
    align-items: center;
    justify-content: center;
    padding: 8px 12px;
    border: 1px solid var(--ux-line);
    border-radius: 8px;
    background: #fff;
    color: var(--ux-ink);
    font-size: 13px;
    font-weight: 800;
    text-decoration: none;
  }
  .ux-tab.active, .ux-link-button {
    border-color: var(--ux-accent);
    background: var(--ux-accent);
    color: #fff;
  }
  .ux-layout {
    display: grid;
    gap: 16px;
    align-items: start;
  }
  .config-cleanup, .guided-review, .control-room {
    grid-template-columns: minmax(280px, 0.9fr) minmax(360px, 1.1fr);
  }
  .capability-command {
    grid-template-columns: minmax(0, 1fr) repeat(3, minmax(140px, 0.25fr));
  }
  .topology-map {
    grid-template-columns: minmax(360px, 1fr) minmax(320px, 0.7fr);
  }
  .wide {
    grid-column: 1 / -1;
  }
  .ux-live-panel > .panel {
    height: 100%;
    border-color: var(--ux-line);
    background: var(--ux-panel);
  }
  .ux-masthead, .ux-score-card, .ux-link-panel, .ux-route-map, .ux-review-step {
    min-width: 0;
    padding: 16px;
    border: 1px solid var(--ux-line);
    border-radius: 8px;
    background: var(--ux-panel-soft);
  }
  .ux-masthead {
    display: grid;
    gap: 8px;
  }
  .ux-score-card {
    display: grid;
    align-content: center;
    gap: 8px;
  }
  .ux-score-card span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
  }
  .ux-score-card strong {
    color: var(--ux-accent);
    font-size: 28px;
    overflow-wrap: anywhere;
  }
  .ux-route-map {
    min-height: 420px;
    display: grid;
    grid-template-columns: repeat(2, minmax(150px, 1fr));
    gap: 12px;
    background:
      linear-gradient(var(--ux-line) 1px, transparent 1px),
      linear-gradient(90deg, var(--ux-line) 1px, transparent 1px),
      var(--ux-panel-soft);
    background-size: 28px 28px;
  }
  .ux-route-node {
    display: grid;
    gap: 4px;
    align-content: start;
    min-width: 0;
    padding: 12px;
    border: 1px solid var(--ux-line);
    border-radius: 8px;
    background: #fff;
  }
  .ux-route-node span, .ux-route-node small {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
  }
  .ux-route-node strong {
    color: var(--ux-accent-2);
    overflow-wrap: anywhere;
  }
  .ux-review-step {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    gap: 12px;
    align-items: start;
  }
  .ux-step-number {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 999px;
    background: var(--ux-accent);
    color: #fff;
    font-weight: 900;
  }
  @media (max-width: 980px) {
    .ux-header, .config-cleanup, .guided-review, .control-room, .capability-command, .topology-map {
      grid-template-columns: minmax(0, 1fr);
    }
  }
  "
}
