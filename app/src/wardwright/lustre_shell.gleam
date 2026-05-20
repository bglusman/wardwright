import lustre/attribute.{attribute, class}
import lustre/element.{type Element, element, text}
import lustre/element/html
import lustre/event

pub type Page {
  Workbench
  ModelAccess
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
        "Workbench",
        "Run and inspect registered models.",
        "/admin",
        active_page == Workbench,
      ),
      rail_link(
        "Model access",
        "Configure model keys and access.",
        "/admin?view=model_access",
        active_page == ModelAccess,
      ),
      deprecated_rail_link(),
    ]),
    ..children
  ])
}

pub fn admin_sidebar(
  active_page: Page,
  subtitle: String,
  children: List(Element(msg)),
  to_msg: fn(Page) -> msg,
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
      rail_button(
        "Workbench",
        "Run and inspect registered models.",
        active_page == Workbench,
        to_msg(Workbench),
      ),
      rail_button(
        "Model access",
        "Configure model keys and access.",
        active_page == ModelAccess,
        to_msg(ModelAccess),
      ),
      deprecated_rail_link(),
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

fn rail_button(
  label: String,
  description: String,
  active: Bool,
  msg: msg,
) -> Element(msg) {
  element(
    "button",
    [
      class(case active {
        True -> "active"
        False -> ""
      }),
      attribute("type", "button"),
      event.on_click(msg),
    ],
    [
      html.strong([], [text(label)]),
      html.span([], [text(description)]),
    ],
  )
}

fn deprecated_rail_link() -> Element(msg) {
  element("a", [class("deprecated"), attribute("href", "/policies")], [
    html.strong([], [text("Legacy workbench (deprecated)")]),
    html.span([], [text("Previous policy view.")]),
  ])
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
  .rail-nav a.deprecated {
    margin-top: 4px;
    padding: 7px 10px;
    opacity: 0.72;
  }
  .rail-nav a.deprecated strong {
    font-size: 11px;
    font-weight: 700;
  }
  .rail-nav a.deprecated span {
    font-size: 10px;
    font-weight: 600;
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
      width: 100%;
      height: auto;
      max-width: 100vw;
      padding: 18px;
    }
  }
  "
}
