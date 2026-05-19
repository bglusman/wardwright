import gleam/bool
import gleam/int
import gleam/list
import lustre
import lustre/attribute.{
  attribute, checked, class, id, name, placeholder, selected, type_, value,
}
import lustre/element.{type Element, element, text}
import lustre/element/html
import lustre/event
import ui/button
import ui/select as select_ui

type ModelOption =
  #(String, String, String, String)

type KeyOption =
  #(String, String, String, String)

pub type Model {
  Model(
    model_id: String,
    requires_api_key: Bool,
    unkeyed_access: String,
    keys: List(KeyOption),
    key_label: String,
    created_key: String,
    status: String,
    error: String,
  )
}

pub type Msg {
  ModelChanged(String)
  KeyLabelChanged(String)
  CreateKey(List(#(String, String)))
  RevokeKey(String)
  SaveAccess(List(#(String, String)))
}

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "default_model_id")
fn external_default_model_id() -> String

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "model_options")
fn external_model_options() -> List(ModelOption)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "access_summary")
fn external_access_summary(model_id: String) -> #(String, Bool, String, Int)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "key_options")
fn external_key_options(model_id: String) -> List(KeyOption)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "create_key")
fn external_create_key(
  model_id: String,
  label: String,
) -> #(Bool, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "revoke_key")
fn external_revoke_key(key_id: String) -> #(Bool, String)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "save_access")
fn external_save_access(
  model_id: String,
  requires_api_key: Bool,
  unkeyed_access: String,
) -> #(Bool, String)

pub fn component() {
  lustre.simple(init, update, view)
}

pub fn init(selected_model_id: String) -> Model {
  let model_id = case selected_model_id {
    "" -> external_default_model_id()
    selected -> selected
  }

  load_model(model_id, "", "", "")
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    ModelChanged(model_id) -> load_model(model_id, "", "", "")

    KeyLabelChanged(label) -> Model(..model, key_label: label)

    CreateKey(fields) -> {
      let label = field_value(fields, "key_label", model.key_label)
      let #(ok, message, raw_key) = external_create_key(model.model_id, label)

      case ok {
        True -> load_model(model.model_id, message, "", raw_key)
        False -> load_model(model.model_id, "", message, "")
      }
    }

    RevokeKey(key_id) -> {
      let #(ok, message) = external_revoke_key(key_id)

      case ok {
        True -> load_model(model.model_id, message, "", "")
        False -> load_model(model.model_id, "", message, "")
      }
    }

    SaveAccess(fields) -> {
      let requires_api_key =
        field_value(
          fields,
          "requires_api_key",
          bool.to_string(model.requires_api_key),
        )
        == "true"

      let unkeyed_access =
        field_value(fields, "unkeyed_access", model.unkeyed_access)

      let #(ok, message) =
        external_save_access(model.model_id, requires_api_key, unkeyed_access)

      case ok {
        True -> load_model(model.model_id, message, "", "")
        False -> load_model(model.model_id, "", message, "")
      }
    }
  }
}

fn load_model(
  requested_model_id: String,
  status: String,
  error: String,
  created_key: String,
) -> Model {
  let #(model_id, requires_api_key, unkeyed_access, _) =
    external_access_summary(requested_model_id)

  Model(
    model_id:,
    requires_api_key:,
    unkeyed_access:,
    keys: external_key_options(model_id),
    key_label: "",
    created_key:,
    status:,
    error:,
  )
}

fn field_value(
  fields: List(#(String, String)),
  wanted_name: String,
  default: String,
) -> String {
  case fields {
    [] -> default
    [field, ..rest] -> {
      let #(field_name, current_value) = field

      case field_name == wanted_name {
        True -> current_value
        False -> field_value(rest, wanted_name, default)
      }
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("model-access-app")], [
    html.style([], styles()),
    sidebar(model),
    html.main([class("workspace")], [
      html.header([class("topbar")], [
        html.div([], [
          html.p([class("eyebrow")], [text("Access control")]),
          html.h1([], [text("Model Access")]),
          html.p([], [
            text(
              "Choose a Wardwright model, then configure API-key requirements and unkeyed access.",
            ),
          ]),
        ]),
      ]),
      notices(model),
      html.section([class("model-key-grid")], [
        model_summary(model),
        access_policy_editor(model),
        create_key_panel(model),
        keys_panel(model),
      ]),
    ]),
  ])
}

fn sidebar(model: Model) -> Element(Msg) {
  html.aside([class("rail")], [
    html.div([class("brand")], [
      html.span([class("mark")], [text("W")]),
      html.div([], [
        html.strong([], [text("Wardwright")]),
        html.span([], [text("Model access controls")]),
      ]),
    ]),
    element("nav", [class("rail-nav")], [
      rail_link(
        "Workbench",
        "Run and inspect registered models.",
        "/workbench",
        False,
      ),
      rail_link(
        "Model Access",
        "Configure keyed and unkeyed model access.",
        "/admin/model-api-keys",
        True,
      ),
      deprecated_rail_link(),
    ]),
    html.div([class("sidebar-footer")], [
      html.span([], [text("Selected model")]),
      html.strong([], [text(model.model_id)]),
      html.span([], [text("Access")]),
      html.code([], [
        text(case model.requires_api_key {
          True -> "keyed"
          False -> model.unkeyed_access
        }),
      ]),
    ]),
  ])
}

fn rail_link(
  label: String,
  description: String,
  href: String,
  active: Bool,
) -> Element(Msg) {
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

fn deprecated_rail_link() -> Element(Msg) {
  element("a", [class("deprecated"), attribute("href", "/policies")], [
    html.strong([], [text("Legacy workbench (deprecated)")]),
    html.span([], [text("Previous policy view.")]),
  ])
}

fn notices(model: Model) -> Element(Msg) {
  case model.status, model.error, model.created_key {
    "", "", "" -> html.div([], [])
    _, _, _ ->
      html.div([class("notices")], [
        case model.status {
          "" -> html.div([], [])
          status ->
            html.section([class("notice success")], [
              html.strong([], [text(status)]),
            ])
        },
        case model.error {
          "" -> html.div([], [])
          error ->
            html.section([class("notice error")], [
              html.strong([], [text(error)]),
            ])
        },
        case model.created_key {
          "" -> html.div([], [])
          created_key ->
            html.section([class("panel success-panel")], [
              html.h2([], [text("New Key")]),
              html.p([], [
                text(
                  "Copy this key now. Wardwright stores only a hash and will not show it again.",
                ),
              ]),
              html.pre([], [text(created_key)]),
            ])
        },
      ])
  }
}

fn model_summary(model: Model) -> Element(Msg) {
  html.article([class("panel model-summary-panel")], [
    html.div([class("panel-header")], [
      html.div([], [
        html.h2([], [text("Selected Model")]),
        html.p([], [
          html.code([], [text(model.model_id)]),
          text(
            " is the model id agents call through the OpenAI-compatible API.",
          ),
        ]),
      ]),
      html.span([class("badge")], [
        text(case model.requires_api_key {
          True -> "keyed"
          False -> "unkeyed"
        }),
      ]),
    ]),
    html.label([class("field")], [
      html.span([], [text("Model to edit")]),
      select_ui.select(
        [
          id("model"),
          name("model"),
          value(model.model_id),
          event.on_change(ModelChanged),
        ],
        model_options(model.model_id),
      ),
    ]),
    html.dl([class("metrics")], [
      metric("Mode", case model.requires_api_key {
        True -> "API key required"
        False -> "Unkeyed"
      }),
      metric("Unkeyed access", model.unkeyed_access),
      metric("Keys", int.to_string(list.length(model.keys))),
    ]),
  ])
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

fn metric(label: String, body: String) -> Element(Msg) {
  html.div([], [
    html.dt([], [text(label)]),
    html.dd([], [text(body)]),
  ])
}

fn access_policy_editor(model: Model) -> Element(Msg) {
  html.article([class("panel access-policy-editor")], [
    html.h2([], [text("Access Policy")]),
    html.form(
      [
        id("model-access-form"),
        class("stacked-form"),
        event.on_submit(SaveAccess),
      ],
      [
        html.fieldset([], [
          html.legend([], [text("Model calls")]),
          html.div([class("radio-card access-mode-card")], [
            html.label([class("radio-card-main")], [
              html.input([
                type_("radio"),
                name("requires_api_key"),
                value("false"),
                checked(!model.requires_api_key),
              ]),
              html.span([], [
                html.strong([], [text("Unkeyed")]),
                html.small([], [
                  text("Allow calls without a Wardwright model API key."),
                ]),
              ]),
            ]),
            case model.requires_api_key {
              True -> html.div([], [])
              False -> unkeyed_access_options(model)
            },
          ]),
          html.label([class("radio-card")], [
            html.input([
              type_("radio"),
              name("requires_api_key"),
              value("true"),
              checked(model.requires_api_key),
            ]),
            html.span([], [
              html.strong([], [text("Keyed")]),
              html.small([], [
                text("Require a bearer key scoped to this model."),
              ]),
            ]),
          ]),
        ]),
        button.button([button.variant(button.Default), type_("submit")], [
          text("Save access policy"),
        ]),
      ],
    ),
  ])
}

fn unkeyed_access_options(model: Model) -> Element(Msg) {
  html.div([class("nested-radio-group")], [
    html.span([], [text("Unkeyed access")]),
    radio_card(
      "unkeyed_access",
      "public",
      model.unkeyed_access == "public",
      "Public",
      "Show the model in discovery and allow direct unkeyed calls.",
    ),
    radio_card(
      "unkeyed_access",
      "internal",
      model.unkeyed_access == "internal",
      "Composition only",
      "Hide unkeyed direct calls while keeping internal composition possible.",
    ),
  ])
}

fn radio_card(
  field_name: String,
  field_value: String,
  is_checked: Bool,
  label: String,
  detail: String,
) -> Element(Msg) {
  html.label([class("radio-card compact")], [
    html.input([
      type_("radio"),
      name(field_name),
      value(field_value),
      checked(is_checked),
    ]),
    html.span([], [
      html.strong([], [text(label)]),
      html.small([], [text(detail)]),
    ]),
  ])
}

fn create_key_panel(model: Model) -> Element(Msg) {
  html.article([class("panel")], [
    html.h2([], [text("Create Key")]),
    html.form(
      [
        id("create-model-key-form"),
        class("inline-form"),
        event.on_submit(CreateKey),
      ],
      [
        html.label([class("field")], [
          html.span([], [text("Label")]),
          html.input([
            id("key_label"),
            name("key_label"),
            placeholder("gateway-prod"),
            value(model.key_label),
            event.on_input(KeyLabelChanged),
          ]),
        ]),
        button.button([button.variant(button.Default), type_("submit")], [
          text("Create key"),
        ]),
      ],
    ),
  ])
}

fn keys_panel(model: Model) -> Element(Msg) {
  html.article([class("panel keys-panel")], [
    html.h2([], [text("Keys")]),
    html.table([], [
      html.thead([], [
        html.tr([], [
          html.th([], [text("Label")]),
          html.th([], [text("Prefix")]),
          html.th([], [text("Created")]),
          html.th([], []),
        ]),
      ]),
      html.tbody([], key_rows(model.keys)),
    ]),
  ])
}

fn key_rows(keys: List(KeyOption)) -> List(Element(Msg)) {
  case keys {
    [] -> [
      html.tr([], [
        html.td([attribute("colspan", "4")], [
          text("No API keys have been created for this model."),
        ]),
      ]),
    ]
    _ -> list.map(keys, key_row)
  }
}

fn key_row(key: KeyOption) -> Element(Msg) {
  let #(key_id, label, prefix, created_at) = key

  html.tr([], [
    html.td([], [text(label)]),
    html.td([], [html.code([], [text(prefix)])]),
    html.td([], [text(created_at)]),
    html.td([], [
      button.button(
        [
          button.variant(button.Destructive),
          type_("button"),
          event.on_click(RevokeKey(key_id)),
        ],
        [text("Revoke")],
      ),
    ]),
  ])
}

fn styles() -> String {
  "
  .model-access-app {
    min-height: 100vh;
    display: grid;
    grid-template-columns: 320px minmax(0, 1fr);
  }
  .rail {
    display: flex;
    flex-direction: column;
    gap: 28px;
    padding: 24px;
    border-right: 1px solid var(--border);
    background: #fbfcfd;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .brand div, .field {
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
  .brand span, .field > span, .eyebrow, dt {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
  }
  .rail-nav {
    display: grid;
    gap: 8px;
  }
  .rail-nav a {
    display: grid;
    gap: 4px;
    padding: 12px;
    border: 1px solid transparent;
    border-radius: 8px;
    color: inherit;
    text-decoration: none;
  }
  .rail-nav a:hover, .rail-nav a.active {
    border-color: var(--border);
    background: #eef6f5;
  }
  .rail-nav span, small {
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
    margin-top: auto;
    display: grid;
    gap: 6px;
    padding: 14px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  .workspace {
    display: flex;
    flex-direction: column;
    gap: 18px;
    padding: 24px;
  }
  .topbar {
    display: flex;
    justify-content: space-between;
    gap: 14px;
  }
  .eyebrow {
    margin: 0 0 6px;
    text-transform: uppercase;
  }
  h1, h2, p, dl {
    margin: 0;
  }
  h1 {
    font-size: 30px;
    line-height: 1.15;
  }
  p {
    color: #46525f;
    line-height: 1.45;
  }
  .model-key-grid {
    display: grid;
    grid-template-columns: minmax(280px, 0.9fr) minmax(360px, 1.2fr);
    gap: 18px;
    align-items: start;
  }
  .panel, .notice {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--card);
  }
  .notice.success, .success-panel {
    border-color: #9cc9c2;
    background: #eef8f6;
  }
  .notice.error {
    border-color: #d99a94;
    background: #fff2f0;
  }
  .notices {
    display: grid;
    gap: 12px;
  }
  .panel-header {
    display: flex;
    justify-content: space-between;
    gap: 12px;
  }
  .badge {
    height: fit-content;
    padding: 4px 10px;
    border: 1px solid var(--border);
    border-radius: 999px;
    background: #eef3f5;
    color: #4a5865;
    font-size: 12px;
    font-weight: 800;
  }
  .metrics {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 8px;
  }
  .metrics div {
    min-width: 0;
    padding: 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fbfcfd;
  }
  dd {
    margin: 0;
    font-weight: 800;
    overflow-wrap: normal;
  }
  p code {
    overflow-wrap: anywhere;
  }
  select, input {
    width: 100%;
    min-height: 40px;
    border: 1px solid var(--input);
    border-radius: 8px;
    background: #fff;
    color: var(--foreground);
    font: inherit;
    padding: 8px 10px;
  }
  .stacked-form, fieldset {
    display: grid;
    gap: 8px;
  }
  fieldset {
    margin: 0;
    padding: 14px;
    border: 1px solid var(--border);
    border-radius: 8px;
  }
  legend {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
    text-transform: uppercase;
  }
  .radio-card {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fff;
  }
  .radio-card-main {
    display: flex;
    gap: 10px;
  }
  .radio-card input {
    width: auto;
    min-height: auto;
    margin-top: 3px;
  }
  .radio-card span {
    display: grid;
    gap: 3px;
  }
  .nested-radio-group {
    display: grid;
    gap: 8px;
    margin: 8px 0 0 38px;
    padding-left: 14px;
    border-left: 3px solid #b7d8d3;
  }
  .inline-form {
    display: grid;
    grid-template-columns: minmax(180px, 1fr) max-content;
    gap: 12px;
    align-items: end;
  }
  button {
    min-height: 38px;
    border-radius: 8px;
    padding: 8px 12px;
    cursor: pointer;
    font-weight: 750;
  }
  .bg-primary {
    background: var(--primary);
  }
  .text-primary-foreground {
    color: var(--primary-foreground);
  }
  .bg-destructive {
    background: var(--destructive);
  }
  .text-destructive-foreground {
    color: #fff;
  }
  table {
    width: 100%;
    border-collapse: collapse;
  }
  th, td {
    border-bottom: 1px solid var(--border);
    padding: 10px;
    text-align: left;
    vertical-align: top;
  }
  th {
    background: #eef3f5;
    color: #4a5865;
    font-size: 12px;
    text-transform: uppercase;
  }
  .keys-panel {
    grid-column: 1 / -1;
  }
  pre {
    overflow: auto;
    margin: 0;
    padding: 12px;
    border-radius: 8px;
    background: #111821;
    color: #f7f8fa;
  }
  @media (max-width: 860px) {
    .model-access-app, .model-key-grid, .inline-form {
      grid-template-columns: 1fr;
    }
    .rail {
      border-right: 0;
      border-bottom: 1px solid var(--border);
    }
  }
  "
}
