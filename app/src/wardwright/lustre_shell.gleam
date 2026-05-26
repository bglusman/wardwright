import lustre/attribute.{attribute, class}
import lustre/element.{type Element, element, text}
import lustre/element/html

pub type Page {
  Workbench
  ModelAccess
  ControlDebugger
  UXExploration
}

pub fn sidebar(
  active_page: Page,
  subtitle: String,
  children: List(Element(msg)),
) -> Element(msg) {
  html.aside([class("rail")], [
    html.div([class("brand")], [
      html.span([class("mark")], [text("W")]),
      html.div([], [
        html.strong([], [text("Wardwright")]),
        html.span([], [text(subtitle)]),
      ]),
    ]),
    element("nav", [class("rail-nav")], [
      rail_link(
        "Model lab",
        "Simulate turns and inspect behavior.",
        "/admin",
        active_page == Workbench,
      ),
      rail_link(
        "Models & access",
        "Configure models, provider keys, and local access.",
        "/admin?view=model_access",
        active_page == ModelAccess,
      ),
      rail_link(
        "Session replay",
        "Load receipts and replay model runs.",
        "/admin?view=control_debugger",
        active_page == ControlDebugger,
      ),
    ]),
    ..children
  ])
}

pub fn admin_sidebar(
  active_page: Page,
  selected_model: String,
  subtitle: String,
  children: List(Element(msg)),
) -> Element(msg) {
  html.aside([class("rail")], [
    html.div([class("brand")], [
      html.span([class("mark")], [text("W")]),
      html.div([], [
        html.strong([], [text("Wardwright")]),
        html.span([], [text(subtitle)]),
      ]),
    ]),
    element("nav", [class("rail-nav")], [
      rail_admin_link(
        "Model lab",
        "Simulate turns and inspect behavior.",
        admin_href(Workbench, selected_model),
        active_page == Workbench,
      ),
      rail_admin_link(
        "Models & access",
        "Configure models, provider keys, and local access.",
        admin_href(ModelAccess, selected_model),
        active_page == ModelAccess,
      ),
      rail_admin_link(
        "Session replay",
        "Load receipts and replay model runs.",
        admin_href(ControlDebugger, selected_model),
        active_page == ControlDebugger,
      ),
      rail_admin_link(
        "UX concepts",
        "Compare live admin arrangements.",
        admin_href(UXExploration, selected_model),
        active_page == UXExploration,
      ),
    ]),
    ..children
  ])
}

fn rail_link(
  label: String,
  description: String,
  href: String,
  active: Bool,
) -> Element(msg) {
  element(
    "a",
    [
      class(case active {
        True -> "active"
        False -> ""
      }),
      attribute("href", href),
    ],
    [
      html.strong([], [text(label)]),
      html.span([], [text(description)]),
    ],
  )
}

fn rail_admin_link(
  label: String,
  description: String,
  href: String,
  active: Bool,
) -> Element(msg) {
  element(
    "a",
    [
      class(case active {
        True -> "active"
        False -> ""
      }),
      attribute("href", href),
    ],
    [
      html.strong([], [text(label)]),
      html.span([], [text(description)]),
    ],
  )
}

fn admin_href(page: Page, selected_model: String) -> String {
  let model_query = case selected_model {
    "" -> ""
    _ -> "&model=" <> selected_model
  }

  case page {
    Workbench ->
      case selected_model {
        "" -> "/admin"
        _ -> "/admin?model=" <> selected_model
      }
    ModelAccess -> "/admin?view=model_access" <> model_query
    ControlDebugger -> "/admin?view=control_debugger" <> model_query
    UXExploration ->
      case selected_model {
        "" -> "/admin/ux-exploration"
        _ -> "/admin/ux-exploration?model=" <> selected_model
      }
  }
}

pub fn styles() -> String {
  "
  *, *::before, *::after {
    box-sizing: border-box;
  }
  .rail {
    position: sticky;
    top: 0;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 18px;
    height: 100vh;
    overflow-y: auto;
    padding: 24px;
    border-right: 1px solid var(--border);
    background: #fbfcfd;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
  }
  .brand div, .field {
    min-width: 0;
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
  .brand strong {
    font-size: 17px;
    overflow-wrap: anywhere;
  }
  .brand span, .field > span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
  }
  .rail-nav {
    display: grid;
    gap: 6px;
  }
  .rail-nav a, .rail-nav button {
    display: grid;
    gap: 3px;
    width: 100%;
    padding: 10px 12px;
    border: 1px solid transparent;
    border-radius: 8px;
    background: transparent;
    color: inherit;
    font: inherit;
    text-align: left;
    text-decoration: none;
    cursor: pointer;
    min-width: 0;
  }
  .rail-nav a:hover, .rail-nav a.active,
  .rail-nav button:hover, .rail-nav button.active {
    border-color: var(--border);
    background: #eef6f5;
  }
  .rail-nav strong {
    font-size: 13px;
    overflow-wrap: anywhere;
  }
  .rail-nav span {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.35;
  }
  .sidebar-footer {
    position: sticky;
    bottom: 0;
    margin-top: auto;
    display: grid;
    gap: 6px;
    padding: 14px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  @media (max-width: 860px) {
    .rail {
      position: static;
      width: 100%;
      height: auto;
      max-width: 100vw;
      padding: 18px;
    }
  }
  "
}
