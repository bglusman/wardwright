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
        text(concept_header_copy(model.concept)),
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
  experience_frame(
    model_access,
    "config-cleanup-experience",
    "Progressive model management",
    "Lead with the current model promise, then reveal access, tools, replay, and lifecycle controls in the order an operator usually needs them.",
    "Operators get task lanes for model contract, access, tool exposure, replay, integrations, and release evidence without leaving the selected model.",
    [
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
          map(
            lustre_model_access.server_tools_panel(model_access),
            ModelAccessMsg,
          ),
        ]),
      ]),
    ],
  )
}

fn capability_command_center(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  let #(mode, guaranteed_tools, conditional_tools) =
    model_access.tool_advertisement

  experience_frame(
    model_access,
    "capability-command-experience",
    "Capability command center",
    "Put the agent-visible contract above implementation detail so operators can tell what is guaranteed, conditional, or blocked before editing config.",
    "Every module starts from what downstream agents can rely on, then drills into route targets, tool mediation, replay evidence, and adapter support.",
    [
      html.section([class("ux-layout capability-command")], [
        score_card("Advertise", mode),
        score_card("Guaranteed tools", int.to_string(guaranteed_tools)),
        score_card("Conditional tools", int.to_string(conditional_tools)),
        score_card("Model", model_access.model_id),
        html.div([class("ux-live-panel wide")], [
          map(
            lustre_model_access.server_tools_panel(model_access),
            ModelAccessMsg,
          ),
        ]),
      ]),
    ],
  )
}

fn route_topology_map(model_access: lustre_model_access.Model) -> Element(Msg) {
  experience_frame(
    model_access,
    "topology-map-experience",
    "Topology-first operations",
    "Show Wardwright as a graph of promises, routes, targets, tools, and evidence so composition risks are visible before a model is changed.",
    "The selected model stays at the center while raw targets, caller gates, hosted tools, replay proof, adapters, and release checks remain adjacent.",
    [
      html.section([class("ux-layout topology-map")], [
        html.article([class("ux-route-map")], [
          route_node("Stable model", model_access.model_id, "contract"),
          route_node("Model lab", "simulate", "test behavior"),
          route_node("Access", access_label(model_access), "caller gate"),
          route_node(
            "Server tools",
            int.to_string(list.length(model_access.server_tools)),
            "Wardwright hosted",
          ),
          route_node("Replay", model_access.vcr_mode, "evidence"),
          route_node("Adapters", "recipes", "framework + local agents"),
          route_node("Release", "checks", "browser + package smoke"),
          ..target_nodes(model_access.server_tool_targets)
        ]),
        html.div([class("ux-live-panel")], [
          map(lustre_model_access.model_summary(model_access), ModelAccessMsg),
        ]),
        html.div([class("ux-live-panel")], [
          map(
            lustre_model_access.server_tools_panel(model_access),
            ModelAccessMsg,
          ),
        ]),
      ]),
    ],
  )
}

fn guided_change_review(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  experience_frame(
    model_access,
    "guided-review-experience",
    "Guided change review",
    "Turn risky admin work into an evidence-gated flow: understand the promise, change one thing, prove behavior, then promote.",
    "Operators move through contract, access, tool advertisement, simulation, receipt replay, and promotion proof before a release-sensitive change lands.",
    [
      html.section([class("ux-layout guided-review")], [
        review_step("1", "Choose model contract", model_access.model_id),
        review_step("2", "Confirm access", access_label(model_access)),
        review_step(
          "3",
          "Confirm tool advertisement",
          advertisement_label(model_access),
        ),
        review_step("4", "Run simulation", "Model lab scenario evidence"),
        review_step("5", "Replay receipt", model_access.vcr_mode),
        review_step("6", "Promote", "Package and browser smoke required"),
        html.div([class("ux-live-panel")], [
          map(
            lustre_model_access.access_policy_editor(model_access),
            ModelAccessMsg,
          ),
        ]),
        html.div([class("ux-live-panel")], [
          map(
            lustre_model_access.server_tools_panel(model_access),
            ModelAccessMsg,
          ),
        ]),
      ]),
    ],
  )
}

fn holistic_control_room(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  experience_frame(
    model_access,
    "control-room-experience",
    "Holistic control room",
    "Give operators one command surface for model contracts, policy authoring, tools, replay evidence, integration posture, and release readiness.",
    "The broad overview keeps live configuration, policy work, replay evidence, integration posture, and release readiness in one selected-model workspace.",
    [
      html.section([class("ux-layout control-room")], [
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
          map(
            lustre_model_access.server_tools_panel(model_access),
            ModelAccessMsg,
          ),
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
      ]),
    ],
  )
}

fn experience_frame(
  model_access: lustre_model_access.Model,
  class_name: String,
  title: String,
  body: String,
  theory: String,
  children: List(Element(Msg)),
) -> Element(Msg) {
  html.section([class("ux-experience " <> class_name)], [
    app_spine(model_access),
    html.div([class("ux-experience-main")], [
      html.article([class("ux-masthead wide")], [
        html.p([class("eyebrow")], [text("Admin workspace")]),
        html.h2([], [text(title)]),
        html.p([], [text(body)]),
      ]),
      posture_card(theory),
      capability_deck(model_access),
      ..children
    ]),
    product_surface_strip(model_access),
  ])
}

fn app_spine(model_access: lustre_model_access.Model) -> Element(Msg) {
  html.aside([class("ux-app-spine")], [
    html.strong([], [text("Wardwright")]),
    html.span([], [text(model_access.model_id)]),
    spine_link("Overview", "#ux-overview"),
    spine_link("Model lab", "/admin?model=" <> model_access.model_id),
    spine_link(
      "Models & access",
      "/admin?view=model_access&model=" <> model_access.model_id,
    ),
    spine_link("Policy lab", "/admin?model=" <> model_access.model_id),
    spine_link(
      "Evidence",
      "/admin?view=control_debugger&model=" <> model_access.model_id,
    ),
    spine_link("Integrations", "#ux-integrations"),
    spine_link("Release", "#ux-release"),
  ])
}

fn spine_link(label: String, href: String) -> Element(Msg) {
  element("a", [attribute("href", href)], [text(label)])
}

fn posture_card(body: String) -> Element(Msg) {
  html.article([class("ux-posture-card")], [
    html.h2([], [text("Operating model")]),
    html.p([], [text(body)]),
  ])
}

fn capability_deck(model_access: lustre_model_access.Model) -> Element(Msg) {
  html.section([id_attr("ux-overview"), class("ux-capability-deck")], [
    capability_card(
      "Model lab",
      "Simulate turns and inspect policy behavior.",
      "Run scenarios",
      "/admin?model=" <> model_access.model_id,
    ),
    capability_card(
      "Models & access",
      "Manage contracts, access, keys, replay, and server tools.",
      access_label(model_access),
      "/admin?view=model_access&model=" <> model_access.model_id,
    ),
    capability_card(
      "Policy lab",
      "Author, compare, and activate changes with evidence.",
      "Draft + simulate",
      "/admin?model=" <> model_access.model_id,
    ),
    capability_card(
      "Session replay",
      "Load receipts, fork traces, and save evidence.",
      model_access.vcr_mode,
      "/admin?view=control_debugger&model=" <> model_access.model_id,
    ),
    capability_card(
      "Integrations",
      "Separate framework recipes from local coding-agent adapters.",
      "Adapters",
      "#ux-integrations",
    ),
    capability_card(
      "Release readiness",
      "Package, browser, docs, and adapter smoke evidence.",
      "Checks",
      "#ux-release",
    ),
  ])
}

fn capability_card(
  title: String,
  body: String,
  status: String,
  href: String,
) -> Element(Msg) {
  html.article([class("ux-capability-card")], [
    html.div([], [
      html.h2([], [text(title)]),
      html.p([], [text(body)]),
    ]),
    html.strong([], [text(status)]),
    link_button(href, "Open"),
  ])
}

fn product_surface_strip(
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  html.section([class("ux-product-surfaces")], [
    surface_card(
      "Provider runtime",
      "Route target support, context-window differences, provider tool-call support, and server-tool mediation stay visible as model-level risk.",
      "Inspect in Models & access",
      "/admin?view=model_access&model=" <> model_access.model_id,
      "",
    ),
    surface_card(
      "Integrations",
      "Framework recipes remain separate from OpenCode and OpenClaw local coding-agent adapters so support claims stay explicit.",
      "Review adapter recipes",
      "#ux-integrations",
      "ux-integrations",
    ),
    surface_card(
      "Evidence",
      "Receipt replay, simulator cases, and counterfactual forks provide the proof path before config changes are promoted.",
      "Open replay",
      "/admin?view=control_debugger&model=" <> model_access.model_id,
      "",
    ),
    surface_card(
      "Release readiness",
      "Browser smoke, docs checks, package installation smoke, and adapter evidence are treated as visible product state.",
      "Review checks",
      "#ux-release",
      "ux-release",
    ),
  ])
}

fn surface_card(
  title: String,
  body: String,
  action: String,
  href: String,
  marker: String,
) -> Element(Msg) {
  let attrs = case marker {
    "" -> [class("ux-surface-card")]
    _ -> [id_attr(marker), class("ux-surface-card")]
  }

  html.article(attrs, [
    html.h2([], [text(title)]),
    html.p([], [text(body)]),
    link_button(href, action),
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

fn id_attr(id: String) {
  attribute("id", id)
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

fn concept_header_copy(concept: Concept) -> String {
  case concept {
    ModelConfigCleanup ->
      "A progressive-disclosure version of the full admin: preserve the left navigation spine, but stage model, access, tools, replay, integrations, and release checks around the current operator task."
    CapabilityCommandCenter ->
      "A capability-first version of the full admin: every surface starts from what agents can rely on, then lets operators drill into route, tool, evidence, and integration detail."
    RouteTopologyMap ->
      "A topology-first version of the full admin: model contracts, raw targets, tools, replay, adapters, and release evidence are arranged as a system map."
    GuidedChangeReview ->
      "A workflow-first version of the full admin: risky changes move through explicit review steps with live controls embedded where proof is needed."
    HolisticControlRoom ->
      "A command-center version of the full admin: broad situational awareness first, with model configuration, policy work, replay evidence, integrations, and release readiness in one coherent workspace."
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
    --ux-radius: 8px;
    --ux-gap: 16px;
    --ux-pad: 16px;
    --ux-shadow: 0 1px 0 rgba(24, 32, 42, 0.04);
  }
  .ux-workspace.theme-studio {
    --ux-panel-soft: #fff8ea;
    --ux-accent: #8b4f00;
    --ux-accent-2: #7b3b5f;
    --ux-radius: 18px;
    --ux-gap: 20px;
    --ux-pad: 20px;
    --ux-shadow: 0 10px 26px rgba(70, 52, 20, 0.10);
  }
  .ux-workspace.theme-topology {
    --ux-panel-soft: #eef5ff;
    --ux-accent: #245a82;
    --ux-accent-2: #16605a;
    --ux-radius: 4px;
    --ux-gap: 12px;
    --ux-pad: 14px;
    --ux-shadow: none;
  }
  .ux-workspace.theme-review {
    --ux-panel-soft: #f4f2ff;
    --ux-accent: #5541a5;
    --ux-accent-2: #915930;
    --ux-radius: 12px;
    --ux-gap: 18px;
    --ux-pad: 18px;
    --ux-shadow: 0 0 0 3px rgba(85, 65, 165, 0.08);
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
    gap: var(--ux-gap);
    align-items: start;
  }
  .ux-experience {
    display: grid;
    grid-template-columns: minmax(190px, 230px) minmax(0, 1fr);
    gap: var(--ux-gap);
    min-width: 0;
  }
  .ux-experience-main {
    display: grid;
    gap: var(--ux-gap);
    min-width: 0;
  }
  .ux-app-spine {
    position: sticky;
    top: 18px;
    display: grid;
    align-content: start;
    gap: 8px;
    min-width: 0;
    padding: var(--ux-pad);
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background: var(--ux-panel-soft);
    box-shadow: var(--ux-shadow);
  }
  .ux-app-spine strong {
    color: var(--ux-accent);
    font-size: 16px;
  }
  .ux-app-spine span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
    overflow-wrap: anywhere;
  }
  .ux-app-spine a {
    display: block;
    padding: 8px 10px;
    border-radius: calc(var(--ux-radius) * 0.7);
    color: var(--ux-ink);
    font-size: 13px;
    font-weight: 800;
    text-decoration: none;
  }
  .ux-app-spine a:hover {
    background: #fff;
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
  .capability-command-experience .ux-capability-deck {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
  .topology-map-experience {
    grid-template-columns: minmax(0, 1fr);
  }
  .topology-map-experience .ux-app-spine {
    position: static;
    grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
  }
  .guided-review-experience {
    grid-template-columns: minmax(240px, 0.34fr) minmax(0, 1fr);
  }
  .guided-review-experience .ux-app-spine a {
    border-left: 3px solid var(--ux-accent);
  }
  .control-room-experience .ux-capability-deck {
    grid-template-columns: repeat(6, minmax(130px, 1fr));
  }
  .wide {
    grid-column: 1 / -1;
  }
  .ux-live-panel > .panel {
    height: 100%;
    border-color: var(--ux-line);
    background: var(--ux-panel);
    border-radius: var(--ux-radius);
    box-shadow: var(--ux-shadow);
  }
  .ux-product-surfaces {
    grid-column: 1 / -1;
    display: grid;
    grid-template-columns: repeat(4, minmax(150px, 1fr));
    gap: var(--ux-gap);
  }
  .ux-masthead, .ux-score-card, .ux-link-panel, .ux-route-map, .ux-review-step, .ux-posture-card, .ux-capability-card, .ux-surface-card {
    min-width: 0;
    padding: var(--ux-pad);
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background: var(--ux-panel-soft);
    box-shadow: var(--ux-shadow);
  }
  .ux-masthead {
    display: grid;
    gap: 8px;
  }
  .ux-posture-card {
    display: grid;
    gap: 6px;
    border-color: color-mix(in srgb, var(--ux-accent), var(--ux-line) 60%);
    background: #fff;
  }
  .ux-capability-deck {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--ux-gap);
  }
  .ux-capability-card {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 10px;
    align-items: start;
    background: #fff;
  }
  .ux-capability-card .ux-link-button {
    grid-column: 1 / -1;
    width: fit-content;
  }
  .ux-capability-card strong {
    color: var(--ux-accent);
    font-size: 12px;
  }
  .ux-surface-card {
    display: grid;
    gap: 10px;
    background: #fff;
  }
  .ux-surface-card .ux-link-button {
    width: fit-content;
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
  .theme-studio .ux-tab, .theme-studio .ux-link-button {
    border-radius: 999px;
    min-height: 42px;
  }
  .theme-studio .ux-capability-card,
  .theme-studio .ux-surface-card {
    border: 0;
    background: linear-gradient(180deg, #fff, var(--ux-panel-soft));
  }
  .theme-topology .ux-tab, .theme-topology .ux-link-button {
    border-radius: 3px;
    min-height: 34px;
    padding: 6px 10px;
    text-transform: uppercase;
  }
  .theme-topology .ux-app-spine,
  .theme-topology .ux-route-node,
  .theme-topology .ux-score-card strong {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace;
  }
  .theme-review .ux-tab, .theme-review .ux-link-button {
    border-radius: 10px;
    border-width: 2px;
  }
  .theme-review .ux-capability-card,
  .theme-review .ux-surface-card,
  .theme-review .ux-review-step {
    border-left: 5px solid var(--ux-accent);
  }
  .theme-topology .ux-live-panel > .panel,
  .theme-topology .ux-masthead,
  .theme-topology .ux-score-card,
  .theme-topology .ux-link-panel,
  .theme-topology .ux-route-map,
  .theme-topology .ux-review-step,
  .theme-topology .ux-posture-card,
  .theme-topology .ux-capability-card,
  .theme-topology .ux-surface-card,
  .theme-topology .ux-app-spine {
    border-style: dashed;
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
    .ux-header, .ux-experience, .config-cleanup, .guided-review, .control-room, .capability-command, .topology-map, .ux-capability-deck, .ux-product-surfaces, .capability-command-experience .ux-capability-deck, .control-room-experience .ux-capability-deck {
      grid-template-columns: minmax(0, 1fr);
    }
    .ux-app-spine {
      position: static;
    }
  }
  "
}
