import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{attribute, class, role, type_}
import lustre/element.{type Element, element, map, text}
import lustre/element/html
import lustre/event
import ui/tabs as tabs_ui
import wardwright/lustre_control_debugger
import wardwright/lustre_model_access
import wardwright/lustre_workbench

pub type Concept {
  OpsConsole
  ModelBuilder
  GuidedLab
  CapabilityCatalog
}

pub type Theme {
  Operations
  Studio
  Topology
  Review
}

pub type Model {
  Model(
    concept: Concept,
    theme: Theme,
    workbench: lustre_workbench.Model,
    model_access: lustre_model_access.Model,
    control_debugger: lustre_control_debugger.Model,
  )
}

pub type Msg {
  ThemeChanged(Theme)
  WorkbenchMsg(lustre_workbench.Msg)
  ModelAccessMsg(lustre_model_access.Msg)
  ControlDebuggerMsg(lustre_control_debugger.Msg)
}

pub fn init(flags: String) -> Model {
  let #(concept, model_id) = parse_flags(flags)

  Model(
    concept:,
    theme: default_theme(concept),
    workbench: lustre_workbench.init(model_id),
    model_access: lustre_model_access.init(model_id),
    control_debugger: lustre_control_debugger.init(Nil),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    ThemeChanged(theme) -> Model(..model, theme:)
    WorkbenchMsg(msg) -> {
      let workbench = lustre_workbench.update(model.workbench, msg)

      Model(
        ..model,
        workbench:,
        model_access: sync_model_access(model.model_access, msg),
      )
    }
    ModelAccessMsg(msg) ->
      Model(
        ..model,
        workbench: sync_workbench(model.workbench, msg),
        model_access: lustre_model_access.update(model.model_access, msg),
      )
    ControlDebuggerMsg(msg) -> {
      let control_debugger =
        lustre_control_debugger.update(model.control_debugger, msg)

      Model(..model, control_debugger:)
    }
  }
}

fn sync_model_access(
  model_access: lustre_model_access.Model,
  msg: lustre_workbench.Msg,
) -> lustre_model_access.Model {
  case msg {
    lustre_workbench.ModelChanged(model_id) ->
      lustre_model_access.init(model_id)
    _ -> model_access
  }
}

fn sync_workbench(
  workbench: lustre_workbench.Model,
  msg: lustre_model_access.Msg,
) -> lustre_workbench.Model {
  case msg {
    lustre_model_access.ModelChanged(model_id) ->
      lustre_workbench.update(
        workbench,
        lustre_workbench.ModelChanged(model_id),
      )
    _ -> workbench
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
        ux_anchor_href(
          model.concept,
          model.model_access.model_id,
          "ux-model-config",
        ),
        "Model config",
      ),
      link_button(
        ux_anchor_href(
          model.concept,
          model.model_access.model_id,
          "ux-model-lab",
        ),
        "Model lab",
      ),
    ]),
  ])
}

fn controls(model: Model) -> Element(Msg) {
  let #(mode, guaranteed_tools, conditional_tools) =
    model.model_access.tool_advertisement

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
    html.div([class("ux-current-state")], [
      html.span([], [text("Model")]),
      html.code([], [text(model.model_access.model_id)]),
      html.span([], [text("Theme")]),
      html.code([], [text(theme_label(model.theme))]),
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
  ])
}

fn concept_links(model: Model) -> List(Element(Msg)) {
  [
    concept_link(model, OpsConsole),
    concept_link(model, ModelBuilder),
    concept_link(model, GuidedLab),
    concept_link(model, CapabilityCatalog),
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
    OpsConsole -> ops_console(model)
    ModelBuilder -> model_builder(model)
    GuidedLab -> guided_lab(model)
    CapabilityCatalog -> capability_catalog(model)
  }
}

fn ops_console(model: Model) -> Element(Msg) {
  let #(mode, guaranteed_tools, conditional_tools) =
    model.model_access.tool_advertisement

  html.section(
    [id_attr("ux-overview"), class("ux-concept ops-console-experience")],
    [
      html.section([class("ops-topline")], [
        score_card("Model", model.model_access.model_id),
        score_card("Access", access_label(model.model_access)),
        score_card("Advertise", mode),
        score_card("Tools", int.to_string(guaranteed_tools + conditional_tools)),
        score_card("Replay", model.model_access.vcr_mode),
      ]),
      html.section([class("ops-grid")], [
        html.aside([class("ops-watchlist")], [
          html.p([class("eyebrow")], [text("Admin workspace")]),
          html.h2([], [text("Production watchlist")]),
          watch_item("Route health", "No provider fallback active"),
          watch_item("Tool mediation", advertisement_label(model.model_access)),
          watch_item("Evidence gap", "Package smoke required before release"),
          watch_item(
            "Adapter posture",
            "Framework recipes separated from local agents",
          ),
          section_nav(model.concept, model.model_access),
        ]),
        html.div([class("ops-main")], [
          html.section([class("ux-layout ops-panels")], [
            html.div([class("ux-live-panel")], [
              map(
                lustre_model_access.model_summary(model.model_access),
                ModelAccessMsg,
              ),
            ]),
            html.div([class("ux-live-panel")], [
              map(
                lustre_model_access.server_tools_panel(model.model_access),
                ModelAccessMsg,
              ),
            ]),
            html.div([class("ux-live-panel wide")], [
              map(
                lustre_control_debugger.evidence_panel(model.control_debugger),
                ControlDebuggerMsg,
              ),
            ]),
          ]),
          end_to_end_modules(model),
        ]),
      ]),
    ],
  )
}

fn model_builder(model: Model) -> Element(Msg) {
  html.section(
    [id_attr("ux-overview"), class("ux-concept model-builder-experience")],
    [
      html.section([class("builder-shell")], [
        html.div([class("builder-toolbar")], [
          html.p([class("eyebrow")], [text("Admin workspace")]),
          html.h2([], [text("Route graph builder")]),
          html.p([], [
            text(
              "Model composition is the primary object. Select the promise, targets, tools, and proof nodes before editing any panel.",
            ),
          ]),
          section_nav(model.concept, model.model_access),
        ]),
        html.article([class("builder-canvas")], [
          route_node(
            "Stable model",
            model.model_access.model_id,
            "public contract",
          ),
          route_node(
            "Access gate",
            access_label(model.model_access),
            "caller policy",
          ),
          route_node("Policy lab", "draft + simulate", "behavior edits"),
          route_node(
            "Server tools",
            int.to_string(list.length(model.model_access.server_tools)),
            "Wardwright hosted",
          ),
          route_node(
            "Receipt replay",
            model.model_access.vcr_mode,
            "fidelity proof",
          ),
          route_node("Release proof", "checks", "promotion gate"),
          ..target_nodes(model.model_access.server_tool_targets)
        ]),
        html.aside([class("builder-inspector")], [
          html.h2([], [text("Node inspector")]),
          html.p([], [
            text(
              "The selected model owns access, tool advertisement, target support, replay capture, adapter claims, and release evidence.",
            ),
          ]),
          html.div([class("ux-live-panel")], [
            map(
              lustre_model_access.server_tools_panel(model.model_access),
              ModelAccessMsg,
            ),
          ]),
        ]),
      ]),
      html.section([class("builder-below")], [
        html.div([class("ux-live-panel")], [
          map(
            lustre_model_access.model_summary(model.model_access),
            ModelAccessMsg,
          ),
        ]),
        html.div([class("ux-live-panel")], [
          map(
            lustre_model_access.access_policy_editor(model.model_access),
            ModelAccessMsg,
          ),
        ]),
      ]),
      end_to_end_modules(model),
    ],
  )
}

fn guided_lab(model: Model) -> Element(Msg) {
  html.section(
    [id_attr("ux-overview"), class("ux-concept guided-lab-experience")],
    [
      html.section([class("guided-shell")], [
        html.aside([class("guided-steps")], [
          html.p([class("eyebrow")], [text("Admin workspace")]),
          html.h2([], [text("Change runbook")]),
          review_step("1", "Pick model", model.model_access.model_id),
          review_step(
            "2",
            "Edit one risk",
            advertisement_label(model.model_access),
          ),
          review_step("3", "Simulate", "Run behavior cases"),
          review_step("4", "Replay", model.model_access.vcr_mode),
          review_step("5", "Promote", "Docs, browser, package smoke"),
        ]),
        html.div([class("guided-work")], [
          html.article([class("ux-masthead")], [
            html.h2([], [text("Current step: prove the change")]),
            html.p([], [
              text(
                "The main canvas keeps the exact controls needed for the active step visible; supporting surfaces are still reachable inside this same concept route.",
              ),
            ]),
            section_nav(model.concept, model.model_access),
          ]),
          html.div([class("ux-live-panel")], [
            map(
              lustre_workbench.embedded_model_lab(model.workbench),
              WorkbenchMsg,
            ),
          ]),
          html.div([class("ux-live-panel")], [
            map(
              lustre_model_access.server_tools_panel(model.model_access),
              ModelAccessMsg,
            ),
          ]),
        ]),
        html.aside([class("guided-proof")], [
          html.h2([], [text("Proof checklist")]),
          release_check_card(
            "Simulation",
            "Scenario must explain route behavior",
          ),
          release_check_card("Receipt replay", "Capture before changing claims"),
          release_check_card("Browser smoke", "Required for admin UX changes"),
          release_check_card("Package smoke", "Required before release tag"),
        ]),
      ]),
      end_to_end_modules(model),
    ],
  )
}

fn capability_catalog(model: Model) -> Element(Msg) {
  html.section(
    [id_attr("ux-overview"), class("ux-concept capability-catalog-experience")],
    [
      html.section([class("catalog-shell")], [
        html.article([class("catalog-hero")], [
          html.p([class("eyebrow")], [text("Admin workspace")]),
          html.h2([], [text("Capability catalog")]),
          html.p([], [
            text(
              "Browse Wardwright by promises agents can consume: models, server tools, provider tools, replay fidelity, adapters, and release evidence.",
            ),
          ]),
          section_nav(model.concept, model.model_access),
        ]),
        html.section([class("catalog-filters")], [
          score_card("Access", access_label(model.model_access)),
          score_card("Replay", model.model_access.vcr_mode),
          score_card(
            "Hosted tools",
            int.to_string(list.length(model.model_access.server_tools)),
          ),
          score_card(
            "Targets",
            int.to_string(list.length(model.model_access.server_tool_targets)),
          ),
        ]),
        html.section([class("catalog-grid")], [
          catalog_card(
            "Model contract",
            "Stable name, access policy, provider targets, and lifecycle posture.",
            access_label(model.model_access),
            ux_anchor_href(
              model.concept,
              model.model_access.model_id,
              "ux-model-config",
            ),
          ),
          catalog_card(
            "Agent-visible tools",
            "Guaranteed, conditional, blocked, hosted, and provider-side tool behavior.",
            advertisement_label(model.model_access),
            ux_anchor_href(
              model.concept,
              model.model_access.model_id,
              "ux-model-config",
            ),
          ),
          catalog_card(
            "Replay evidence",
            "Receipt replay and control debugger proof for changes.",
            model.model_access.vcr_mode,
            ux_anchor_href(
              model.concept,
              model.model_access.model_id,
              "ux-evidence",
            ),
          ),
          catalog_card(
            "Adapters",
            "Framework recipes separate from OpenCode and OpenClaw local adapters.",
            "support tiers",
            ux_anchor_href(
              model.concept,
              model.model_access.model_id,
              "ux-integrations",
            ),
          ),
          catalog_card(
            "Release gates",
            "Browser smoke, docs checks, package smoke, and adapter evidence.",
            "promotion proof",
            ux_anchor_href(
              model.concept,
              model.model_access.model_id,
              "ux-release",
            ),
          ),
          catalog_card(
            "Policy authoring",
            "Draft, simulate, and activate behavior changes with receipts nearby.",
            "lab workflow",
            ux_anchor_href(
              model.concept,
              model.model_access.model_id,
              "ux-policy-lab",
            ),
          ),
        ]),
        html.div([class("ux-live-panel")], [
          map(
            lustre_model_access.embedded_workspace(model.model_access),
            ModelAccessMsg,
          ),
        ]),
      ]),
      end_to_end_modules(model),
    ],
  )
}

fn section_nav(
  concept: Concept,
  model_access: lustre_model_access.Model,
) -> Element(Msg) {
  html.nav(
    [class("ux-section-nav"), attribute("aria-label", "Concept sections")],
    [
      section_link(
        "Overview",
        ux_anchor_href(concept, model_access.model_id, "ux-overview"),
      ),
      section_link(
        "Model lab",
        ux_anchor_href(concept, model_access.model_id, "ux-model-lab"),
      ),
      section_link(
        "Models & access",
        ux_anchor_href(concept, model_access.model_id, "ux-model-config"),
      ),
      section_link(
        "Policy lab",
        ux_anchor_href(concept, model_access.model_id, "ux-policy-lab"),
      ),
      section_link(
        "Evidence",
        ux_anchor_href(concept, model_access.model_id, "ux-evidence"),
      ),
      section_link(
        "Integrations",
        ux_anchor_href(concept, model_access.model_id, "ux-integrations"),
      ),
      section_link(
        "Release",
        ux_anchor_href(concept, model_access.model_id, "ux-release"),
      ),
    ],
  )
}

fn section_link(label: String, href: String) -> Element(Msg) {
  element("a", [attribute("href", href)], [text(label)])
}

fn catalog_card(
  title: String,
  body: String,
  status: String,
  href: String,
) -> Element(Msg) {
  html.article([class("catalog-card")], [
    html.div([], [
      html.h2([], [text(title)]),
      html.p([], [text(body)]),
    ]),
    html.strong([], [text(status)]),
    link_button(href, "Open"),
  ])
}

fn watch_item(label: String, value: String) -> Element(Msg) {
  html.article([class("watch-item")], [
    html.span([], [text(label)]),
    html.strong([], [text(value)]),
  ])
}

fn end_to_end_modules(model: Model) -> Element(Msg) {
  html.section([class("ux-end-to-end")], [
    embedded_section(
      "ux-model-lab",
      "Model lab",
      "Run scenarios against the selected model contract.",
      [
        map(lustre_workbench.embedded_model_lab(model.workbench), WorkbenchMsg),
      ],
    ),
    embedded_section(
      "ux-model-config",
      "Models & access",
      "Configure the selected model contract, caller access, keys, lifecycle, replay capture, server tools, and tool-capable targets.",
      [
        map(
          lustre_model_access.embedded_workspace(model.model_access),
          ModelAccessMsg,
        ),
      ],
    ),
    embedded_section(
      "ux-policy-lab",
      "Policy lab",
      "Author, refine, activate, and re-simulate model behavior without leaving this concept experience.",
      [
        map(lustre_workbench.embedded_policy_lab(model.workbench), WorkbenchMsg),
      ],
    ),
    embedded_section(
      "ux-evidence",
      "Evidence",
      "Replay receipts, fork traces, save simulator cases, and prepare harness handoffs from the same selected-model workspace.",
      [
        map(
          lustre_control_debugger.evidence_panel(model.control_debugger),
          ControlDebuggerMsg,
        ),
      ],
    ),
    embedded_section(
      "ux-integrations",
      "Integrations",
      "Keep framework SDK recipes and local coding-agent adapters visible as separate support surfaces.",
      [
        map(lustre_control_debugger.adapter_status_card(), ControlDebuggerMsg),
      ],
    ),
    embedded_section(
      "ux-release",
      "Release readiness",
      "Promotion evidence stays in the concept route: browser smoke, docs checks, package installation smoke, and adapter evidence.",
      [
        release_check_card("Browser smoke", "Required before promotion"),
        release_check_card("Docs check", "Required when docs changed"),
        release_check_card("Package smoke", "Required for release artifacts"),
        release_check_card("Adapter evidence", "Claims must match probes"),
      ],
    ),
  ])
}

fn embedded_section(
  marker: String,
  title: String,
  body: String,
  children: List(Element(Msg)),
) -> Element(Msg) {
  html.section([id_attr(marker), class("ux-embedded-section")], [
    html.div([class("ux-embedded-heading")], [
      html.p([class("eyebrow")], [text("Admin surface")]),
      html.h2([], [text(title)]),
      html.p([], [text(body)]),
    ]),
    ..children
  ])
}

fn release_check_card(label: String, status: String) -> Element(Msg) {
  html.article([class("ux-release-check")], [
    html.strong([], [text(label)]),
    html.span([], [text(status)]),
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
    ["ux_exploration"] -> #(OpsConsole, "")
    _ -> #(OpsConsole, "")
  }
}

fn concept_from_id(id: String) -> Concept {
  case id {
    "ops-console" -> OpsConsole
    "model-builder" -> ModelBuilder
    "guided-lab" -> GuidedLab
    "capability-catalog" -> CapabilityCatalog
    "model-config-cleanup" -> OpsConsole
    "capability-command-center" -> CapabilityCatalog
    "route-topology-map" -> ModelBuilder
    "guided-change-review" -> GuidedLab
    "holistic-control-room" -> OpsConsole
    _ -> OpsConsole
  }
}

fn concept_id(concept: Concept) -> String {
  case concept {
    OpsConsole -> "ops-console"
    ModelBuilder -> "model-builder"
    GuidedLab -> "guided-lab"
    CapabilityCatalog -> "capability-catalog"
  }
}

fn concept_label(concept: Concept) -> String {
  case concept {
    OpsConsole -> "Ops Console"
    ModelBuilder -> "Model Builder"
    GuidedLab -> "Guided Lab"
    CapabilityCatalog -> "Capability Catalog"
  }
}

fn concept_header_copy(concept: Concept) -> String {
  case concept {
    OpsConsole ->
      "Production-operations UX: status, risk, evidence gaps, and live model controls are arranged for repeated monitoring and incident response."
    ModelBuilder ->
      "Canvas-first UX: the route graph and model composition are primary, with configuration exposed as node inspector detail."
    GuidedLab ->
      "Workflow-first UX: risky changes move through a runbook from edit to simulation, replay, and promotion evidence."
    CapabilityCatalog ->
      "Catalog-first UX: agent-visible promises, tools, adapters, replay fidelity, and release gates are organized as browsable capabilities."
  }
}

fn concept_short_label(concept: Concept) -> String {
  case concept {
    OpsConsole -> "Ops"
    ModelBuilder -> "Builder"
    GuidedLab -> "Lab"
    CapabilityCatalog -> "Catalog"
  }
}

fn concept_href(concept: Concept, model_id: String) -> String {
  let base = "/admin/ux-exploration/" <> concept_id(concept)

  case model_id {
    "" -> base
    _ -> base <> "?model=" <> model_id
  }
}

fn ux_anchor_href(
  concept: Concept,
  model_id: String,
  marker: String,
) -> String {
  concept_href(concept, model_id) <> "#" <> marker
}

fn default_theme(concept: Concept) -> Theme {
  case concept {
    OpsConsole -> Operations
    ModelBuilder -> Topology
    GuidedLab -> Review
    CapabilityCatalog -> Studio
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
    box-sizing: border-box;
    width: 100%;
    max-width: 100%;
    overflow-x: clip;
  }
  .ux-workspace * {
    box-sizing: border-box;
    min-width: 0;
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
    max-width: 100%;
  }
  .ux-header > * {
    min-width: 0;
  }
  .ux-header p {
    max-width: 760px;
  }
  .ux-header-actions, .ux-controls {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
    max-width: 100%;
  }
  .ux-control-group {
    display: grid;
    gap: 6px;
    max-width: 100%;
  }
  .ux-current-state {
    display: grid;
    grid-template-columns: repeat(3, auto minmax(90px, max-content));
    gap: 4px 8px;
    align-items: center;
    margin-left: auto;
    padding: 10px 12px;
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background: var(--ux-panel-soft);
    font-size: 12px;
  }
  .ux-current-state span {
    color: var(--muted-foreground);
    font-weight: 800;
    text-transform: uppercase;
  }
  .ux-current-state code {
    overflow-wrap: anywhere;
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
    max-width: 100%;
  }
  .ux-tab, .ux-link-button {
    display: inline-flex;
    max-width: 100%;
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
    text-align: center;
    overflow-wrap: anywhere;
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
  .ux-concept {
    display: grid;
    gap: calc(var(--ux-gap) * 1.5);
    min-width: 0;
  }
  .ux-section-nav {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }
  .ux-section-nav a {
    display: inline-flex;
    min-height: 32px;
    align-items: center;
    padding: 6px 10px;
    border: 1px solid var(--ux-line);
    border-radius: calc(var(--ux-radius) * 0.75);
    background: #fff;
    color: var(--ux-ink);
    font-size: 12px;
    font-weight: 800;
    text-decoration: none;
  }
  .ops-topline, .catalog-filters, .builder-below {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
    gap: var(--ux-gap);
  }
  .ops-grid {
    display: grid;
    grid-template-columns: minmax(250px, 0.32fr) minmax(0, 1fr);
    gap: var(--ux-gap);
    align-items: start;
  }
  .ops-watchlist {
    position: sticky;
    top: 18px;
    display: grid;
    gap: 12px;
    padding: var(--ux-pad);
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background: var(--ux-panel-soft);
    box-shadow: var(--ux-shadow);
  }
  .ops-main {
    display: grid;
    gap: var(--ux-gap);
  }
  .ops-panels {
    grid-template-columns: minmax(320px, 0.8fr) minmax(360px, 1.2fr);
  }
  .watch-item {
    display: grid;
    gap: 3px;
    padding: 10px 0;
    border-bottom: 1px solid var(--ux-line);
  }
  .watch-item span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .watch-item strong {
    color: var(--ux-ink);
    font-size: 13px;
    overflow-wrap: anywhere;
  }
  .builder-shell {
    display: grid;
    grid-template-columns: minmax(190px, 0.28fr) minmax(420px, 1fr) minmax(300px, 0.42fr);
    gap: var(--ux-gap);
    align-items: stretch;
  }
  .builder-toolbar, .builder-inspector, .catalog-hero, .guided-proof, .guided-steps {
    display: grid;
    align-content: start;
    gap: 12px;
    padding: var(--ux-pad);
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background: var(--ux-panel-soft);
    box-shadow: var(--ux-shadow);
  }
  .builder-canvas {
    min-height: 540px;
    display: grid;
    grid-template-columns: repeat(3, minmax(140px, 1fr));
    gap: 18px;
    align-content: center;
    padding: calc(var(--ux-pad) * 1.5);
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background:
      radial-gradient(circle at 18px 18px, color-mix(in srgb, var(--ux-accent), transparent 70%) 1px, transparent 2px),
      var(--ux-panel-soft);
    background-size: 36px 36px;
  }
  .guided-shell {
    display: grid;
    grid-template-columns: minmax(230px, 0.28fr) minmax(0, 1fr) minmax(230px, 0.28fr);
    gap: var(--ux-gap);
    align-items: start;
  }
  .guided-work {
    display: grid;
    gap: var(--ux-gap);
  }
  .catalog-shell {
    display: grid;
    gap: var(--ux-gap);
  }
  .catalog-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    gap: var(--ux-gap);
  }
  .catalog-card {
    display: grid;
    gap: 12px;
    min-width: 0;
    padding: var(--ux-pad);
    border: 1px solid var(--ux-line);
    border-radius: var(--ux-radius);
    background: #fff;
    box-shadow: var(--ux-shadow);
  }
  .catalog-card strong {
    color: var(--ux-accent);
    font-size: 12px;
    overflow-wrap: anywhere;
  }
  .catalog-card .ux-link-button {
    width: fit-content;
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
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
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
  .ux-live-panel {
    overflow-x: auto;
  }
  .ux-live-panel .server-tool-table {
    min-width: 720px;
  }
  .ux-product-surfaces {
    grid-column: 2 / -1;
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: var(--ux-gap);
  }
  .ux-end-to-end {
    grid-column: 1 / -1;
    display: grid;
    gap: calc(var(--ux-gap) * 1.5);
  }
  .topology-map-experience .ux-product-surfaces,
  .topology-map-experience .ux-end-to-end {
    grid-column: 1 / -1;
  }
  .ux-embedded-section {
    display: grid;
    gap: 12px;
  }
  .ux-embedded-heading {
    display: grid;
    gap: 4px;
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
    .ux-header, .ux-experience, .config-cleanup, .guided-review, .control-room, .capability-command, .topology-map, .ux-capability-deck, .ux-product-surfaces, .capability-command-experience .ux-capability-deck, .control-room-experience .ux-capability-deck, .ops-grid, .ops-panels, .builder-shell, .guided-shell {
      grid-template-columns: minmax(0, 1fr);
    }
    .builder-canvas {
      min-height: 360px;
      grid-template-columns: repeat(2, minmax(130px, 1fr));
    }
    .ops-watchlist {
      position: static;
    }
    .ux-product-surfaces,
    .ux-end-to-end {
      grid-column: 1 / -1;
    }
    .ux-app-spine {
      position: static;
    }
    .ux-current-state {
      width: 100%;
      margin-left: 0;
      grid-template-columns: auto minmax(0, 1fr);
    }
  }
  @media (max-width: 520px) {
    .ux-controls {
      display: grid;
      grid-template-columns: minmax(0, 1fr);
    }
    .ux-tabs {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
    .ux-tab {
      width: 100%;
    }
    .ux-current-state {
      font-size: 11px;
    }
    .builder-canvas {
      grid-template-columns: minmax(0, 1fr);
    }
    .ux-section-nav {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
    .ux-section-nav a {
      justify-content: center;
      text-align: center;
    }
  }
  "
}
