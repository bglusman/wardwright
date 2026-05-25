import gleam/bool
import gleam/int
import gleam/list
import lustre
import lustre/attribute.{
  attribute, checked, class, id, name, placeholder, selected, type_, value,
}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event
import ui/button
import ui/select as select_ui
import wardwright/lustre_shell

type ModelOption =
  #(String, String, String, String)

type KeyOption =
  #(String, String, String, String)

type ServerToolOption =
  #(String, String, String, String, String, String, String, String)

type ServerToolTargetOption =
  #(String, String, String)

type ToolMediationSummary =
  #(String, Int)

pub type Model {
  Model(
    model_id: String,
    requires_api_key: Bool,
    unkeyed_access: String,
    vcr_mode: String,
    keys: List(KeyOption),
    key_label: String,
    created_key: String,
    status: String,
    error: String,
    receipt_storage_note: String,
    server_tools: List(ServerToolOption),
    server_tool_targets: List(ServerToolTargetOption),
    tool_mediation: ToolMediationSummary,
  )
}

pub type Msg {
  ModelChanged(String)
  AccessModeChanged(String)
  UnkeyedAccessChanged(String)
  VcrModeChanged(String)
  KeyLabelChanged(String)
  CreateKey(List(#(String, String)))
  RevokeKey(String)
  SaveAccess(List(#(String, String)))
  ArchiveModel
  RestoreArchivedModel(String)
  DeleteArchivedModel(String)
}

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "default_model_id")
fn external_default_model_id() -> String

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "model_options")
fn external_model_options() -> List(ModelOption)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "archived_model_options")
fn external_archived_model_options() -> List(ModelOption)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "access_summary")
fn external_access_summary(
  model_id: String,
) -> #(String, Bool, String, Int, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "key_options")
fn external_key_options(model_id: String) -> List(KeyOption)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "server_tool_summary")
fn external_server_tool_summary(
  model_id: String,
) -> #(
  List(ServerToolOption),
  List(ServerToolTargetOption),
  ToolMediationSummary,
)

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
  vcr_mode: String,
) -> #(Bool, String)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "archive_model")
fn external_archive_model(model_id: String) -> #(Bool, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "restore_archived_model")
fn external_restore_archived_model(model_id: String) -> #(Bool, String, String)

@external(erlang, "Elixir.WardwrightWeb.LustreModelAccessData", "delete_archived_model")
fn external_delete_archived_model(model_id: String) -> #(Bool, String, String)

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

    AccessModeChanged(mode) -> Model(..model, requires_api_key: mode == "true")

    UnkeyedAccessChanged(access) -> Model(..model, unkeyed_access: access)

    VcrModeChanged(mode) -> Model(..model, vcr_mode: mode)

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

      let vcr_mode = field_value(fields, "vcr_mode", model.vcr_mode)

      let #(ok, message) =
        external_save_access(
          model.model_id,
          requires_api_key,
          unkeyed_access,
          vcr_mode,
        )

      case ok {
        True -> load_model(model.model_id, message, "", "")
        False -> load_model(model.model_id, "", message, "")
      }
    }

    ArchiveModel -> {
      let #(ok, message, next_model_id) = external_archive_model(model.model_id)

      case ok {
        True -> load_model(next_model_id, message, "", "")
        False -> load_model(model.model_id, "", message, "")
      }
    }

    RestoreArchivedModel(model_id) -> {
      let #(ok, message, next_model_id) =
        external_restore_archived_model(model_id)

      case ok {
        True -> load_model(next_model_id, message, "", "")
        False -> load_model(model.model_id, "", message, "")
      }
    }

    DeleteArchivedModel(model_id) -> {
      let #(ok, message, next_model_id) =
        external_delete_archived_model(model_id)

      case ok {
        True -> load_model(next_model_id, message, "", "")
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
  let #(model_id, requires_api_key, unkeyed_access, _, vcr_mode, storage_note) =
    external_access_summary(requested_model_id)

  let #(server_tools, server_tool_targets, tool_mediation) =
    external_server_tool_summary(model_id)

  Model(
    model_id:,
    requires_api_key:,
    unkeyed_access:,
    vcr_mode:,
    keys: external_key_options(model_id),
    key_label: "",
    created_key:,
    status:,
    error:,
    receipt_storage_note: storage_note,
    server_tools:,
    server_tool_targets:,
    tool_mediation:,
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
    workspace(model),
  ])
}

pub fn workspace(model: Model) -> Element(Msg) {
  html.main([class("workspace")], [
    html.header([class("topbar")], [
      html.div([], [
        html.p([class("eyebrow")], [text("Model control")]),
        html.h1([], [text("Models & access")]),
        html.p([], [
          text(
            "Choose a Wardwright model, then configure access and debugging capture.",
          ),
        ]),
      ]),
    ]),
    notices(model),
    html.section([class("model-key-grid")], [
      model_summary(model),
      access_policy_editor(model),
      server_tools_panel(model),
      model_lifecycle_panel(model),
      create_key_panel(model),
      keys_panel(model),
      archived_models_panel(),
    ]),
  ])
}

pub fn sidebar_controls(model: Model) -> List(Element(Msg)) {
  [
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
      html.span([], [text("Replay capture")]),
      html.code([], [text(vcr_mode_label(model.vcr_mode))]),
      html.span([], [text("Server tools")]),
      html.code([], [text(int.to_string(list.length(model.server_tools)))]),
    ]),
  ]
}

fn sidebar(model: Model) -> Element(Msg) {
  lustre_shell.sidebar(
    lustre_shell.ModelAccess,
    "Models & access",
    sidebar_controls(model),
  )
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
      metric("Replay capture", vcr_mode_label(model.vcr_mode)),
      metric("Receipt store", model.receipt_storage_note),
      metric("Keys", int.to_string(list.length(model.keys))),
      metric("Server tools", int.to_string(list.length(model.server_tools))),
    ]),
  ])
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
                id("requires_api_key_false"),
                type_("radio"),
                name("requires_api_key"),
                value("false"),
                checked(!model.requires_api_key),
                event.on_change(AccessModeChanged),
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
              id("requires_api_key_true"),
              type_("radio"),
              name("requires_api_key"),
              value("true"),
              checked(model.requires_api_key),
              event.on_change(AccessModeChanged),
            ]),
            html.span([], [
              html.strong([], [text("Keyed")]),
              html.small([], [
                text("Require a bearer key scoped to this model."),
              ]),
            ]),
          ]),
        ]),
        debug_recording_options(model),
        button.button([button.variant(button.Default), type_("submit")], [
          text("Save model management settings"),
        ]),
      ],
    ),
  ])
}

fn server_tools_panel(model: Model) -> Element(Msg) {
  let #(mediation_mode, mediation_rule_count) = model.tool_mediation

  html.article([class("panel server-tools-panel")], [
    html.div([class("panel-header")], [
      html.div([], [
        html.h2([], [text("Server Tools")]),
        html.p([], [
          text("Model-level Wardwright-hosted tool configuration."),
        ]),
      ]),
      html.span([class("badge")], [
        text(int.to_string(list.length(model.server_tools)) <> " configured"),
      ]),
    ]),
    html.dl([class("metrics")], [
      metric("Mediation", mediation_mode),
      metric("Mediation rules", int.to_string(mediation_rule_count)),
      metric("Tool-capable targets", int.to_string(tool_capable_count(model))),
    ]),
    server_tool_table(model.server_tools),
    server_tool_targets(model.server_tool_targets),
  ])
}

fn server_tool_table(tools: List(ServerToolOption)) -> Element(Msg) {
  case tools {
    [] -> html.p([], [text("No server tools configured for this model.")])
    _ ->
      html.table([class("server-tool-table")], [
        html.thead([], [
          html.tr([], [
            html.th([], [text("Tool")]),
            html.th([], [text("Engine")]),
            html.th([], [text("State")]),
            html.th([], [text("Source")]),
            html.th([], [text("Dune limits")]),
            html.th([], [text("Schema")]),
          ]),
        ]),
        html.tbody([], list.map(tools, server_tool_row)),
      ])
  }
}

fn server_tool_row(tool: ServerToolOption) -> Element(Msg) {
  let #(
    name,
    engine,
    source,
    enabled,
    visibility,
    limit_summary,
    parameter_keys,
    input_keys,
  ) = tool

  html.tr([], [
    html.td([attribute("data-label", "Tool")], [
      html.code([], [text(name)]),
      html.small([], [text(visibility)]),
    ]),
    html.td([attribute("data-label", "Engine")], [text(engine)]),
    html.td([attribute("data-label", "State")], [text(enabled)]),
    html.td([attribute("data-label", "Source")], [text(source)]),
    html.td([attribute("data-label", "Dune limits")], [text(limit_summary)]),
    html.td([attribute("data-label", "Schema")], [
      html.small([], [
        text("params " <> parameter_keys <> " / input " <> input_keys),
      ]),
    ]),
  ])
}

fn server_tool_targets(targets: List(ServerToolTargetOption)) -> Element(Msg) {
  html.div([class("server-tool-targets")], [
    html.h3([], [text("Provider Targets")]),
    html.ul([], list.map(targets, server_tool_target_item)),
  ])
}

fn server_tool_target_item(target: ServerToolTargetOption) -> Element(Msg) {
  let #(model, kind, support) = target

  html.li([], [
    html.code([], [text(model)]),
    html.span([], [text(kind)]),
    html.strong([], [text(support)]),
  ])
}

fn tool_capable_count(model: Model) -> Int {
  model.server_tool_targets
  |> list.filter(fn(target) {
    let #(_, _, support) = target
    support == "tool-capable" || support == "Server tools sent to provider"
  })
  |> list.length
}

fn model_lifecycle_panel(_model: Model) -> Element(Msg) {
  html.article([class("panel lifecycle-panel")], [
    html.div([class("panel-header")], [
      html.div([], [
        html.h2([], [text("Model Lifecycle")]),
        html.p([], [
          text(
            "Archive a model to remove it from discovery and routing while keeping its stored artifact recoverable.",
          ),
        ]),
      ]),
    ]),
    button.button(
      [
        button.variant(button.Destructive),
        type_("button"),
        event.on_click(ArchiveModel),
      ],
      [text("Archive model")],
    ),
    html.small([], [
      text(
        "Archive requires SQLite model registry storage. Restore or hard-delete archived models below.",
      ),
    ]),
  ])
}

fn archived_models_panel() -> Element(Msg) {
  let archived_models = external_archived_model_options()

  html.details([class("panel archived-models-panel")], [
    html.summary([], [
      html.span([], [text("Archived Models")]),
      html.small([], [
        text(
          "Hidden by default; restore for review or hard-delete from SQLite.",
        ),
      ]),
    ]),
    case archived_models {
      [] ->
        html.p([], [
          text("No archived models are stored in the SQLite model registry."),
        ])
      _ ->
        html.table([], [
          html.thead([], [
            html.tr([], [
              html.th([], [text("Model")]),
              html.th([], [text("Version")]),
              html.th([], [text("Actions")]),
            ]),
          ]),
          html.tbody([], archived_model_rows(archived_models)),
        ])
    },
  ])
}

fn archived_model_rows(models: List(ModelOption)) -> List(Element(Msg)) {
  list.map(models, fn(model) {
    let #(model_id, _, version, _) = model

    html.tr([], [
      html.td([], [html.code([], [text(model_id)])]),
      html.td([], [text(version)]),
      html.td([class("row-actions")], [
        button.button(
          [
            button.variant(button.Default),
            type_("button"),
            event.on_click(RestoreArchivedModel(model_id)),
          ],
          [text("Restore")],
        ),
        button.button(
          [
            button.variant(button.Destructive),
            type_("button"),
            event.on_click(DeleteArchivedModel(model_id)),
          ],
          [text("Hard delete")],
        ),
      ]),
    ])
  })
}

fn debug_recording_options(model: Model) -> Element(Msg) {
  html.fieldset([], [
    html.legend([], [text("Debug recording")]),
    radio_card(
      "vcr_mode",
      "metadata_only",
      model.vcr_mode == "metadata_only",
      "Metadata only",
      "Default debug capture. Stores roles, lengths, policy facts, and route facts without prompt or completion text.",
      VcrModeChanged,
    ),
    radio_card(
      "vcr_mode",
      "full_session",
      model.vcr_mode == "full_session",
      "Full session",
      "Opt-in capture for replay investigations. Stores full request and provider response payloads in the receipt store.",
      VcrModeChanged,
    ),
    html.small([class("recording-note")], [
      text("Current receipt store: " <> model.receipt_storage_note <> "."),
    ]),
  ])
}

fn vcr_mode_label(mode: String) -> String {
  case mode {
    "full_session" -> "Full session"
    _ -> "Metadata only"
  }
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
      UnkeyedAccessChanged,
    ),
    radio_card(
      "unkeyed_access",
      "internal",
      model.unkeyed_access == "internal",
      "Composition only",
      "Hide unkeyed direct calls while keeping internal composition possible.",
      UnkeyedAccessChanged,
    ),
  ])
}

fn radio_card(
  field_name: String,
  field_value: String,
  is_checked: Bool,
  label: String,
  detail: String,
  to_msg: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([class("radio-card compact")], [
    html.input([
      id(field_name <> "_" <> field_value),
      type_("radio"),
      name(field_name),
      value(field_value),
      checked(is_checked),
      event.on_change(to_msg),
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

pub fn styles() -> String {
  lustre_shell.styles() <> "
  .model-access-app {
    min-height: 100vh;
    display: grid;
    grid-template-columns: minmax(0, 320px) minmax(0, 1fr);
    max-width: 100vw;
    overflow-x: hidden;
  }
  .eyebrow, dt {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 800;
  }
  small {
    color: var(--muted-foreground);
    font-size: 12px;
    font-weight: 700;
    line-height: 1.35;
  }
  .recording-note {
    display: block;
    overflow-wrap: anywhere;
  }
  .workspace {
    display: flex;
    flex-direction: column;
    gap: 18px;
    min-width: 0;
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
  h1, h2, h3, p, dl {
    margin: 0;
  }
  h1 {
    font-size: 30px;
    line-height: 1.15;
    overflow-wrap: anywhere;
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
    min-width: 0;
    max-width: 100%;
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
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
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
    min-width: 0;
    overflow-wrap: anywhere;
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
    min-width: 0;
  }
  fieldset {
    min-inline-size: 0;
    max-width: 100%;
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
    min-width: 0;
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
    min-width: 0;
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
    white-space: normal;
    overflow-wrap: anywhere;
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
    table-layout: auto;
  }
  th, td {
    border-bottom: 1px solid var(--border);
    padding: 10px;
    text-align: left;
    vertical-align: top;
  }
  td {
    overflow-wrap: anywhere;
  }
  th {
    background: #eef3f5;
    color: #4a5865;
    font-size: 12px;
    text-transform: uppercase;
  }
  .server-tools-panel {
    grid-column: 1 / -1;
  }
  .server-tool-table {
    font-size: 14px;
  }
  .server-tool-table th:nth-child(1) {
    min-width: 190px;
  }
  .server-tool-table th:nth-child(5) {
    min-width: 210px;
  }
  .server-tool-table td:first-child {
    display: grid;
    gap: 4px;
  }
  .server-tool-targets {
    display: grid;
    gap: 8px;
  }
  .server-tool-targets h3 {
    font-size: 14px;
    line-height: 1.25;
  }
  .server-tool-targets ul {
    display: grid;
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .server-tool-targets li {
    display: grid;
    grid-template-columns: minmax(160px, 1fr) minmax(120px, max-content) minmax(130px, max-content);
    gap: 10px;
    align-items: center;
    padding: 8px 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #fbfcfd;
  }
  .keys-panel {
    grid-column: 1 / -1;
  }
  .archived-models-panel {
    grid-column: 1 / -1;
  }
  details.panel {
    display: block;
  }
  summary {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    cursor: pointer;
    font-weight: 800;
  }
  .row-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
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
      grid-template-columns: minmax(0, 1fr);
    }
    .server-tool-table,
    .server-tool-table tbody,
    .server-tool-table tr,
    .server-tool-table td {
      display: block;
      width: 100%;
    }
    .server-tool-table {
      border-collapse: separate;
      border-spacing: 0 10px;
      font-size: 15px;
    }
    .server-tool-table thead {
      display: none;
    }
    .server-tool-table tr {
      padding: 10px;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: #fbfcfd;
    }
    .server-tool-table td {
      display: grid;
      grid-template-columns: minmax(92px, max-content) minmax(0, 1fr);
      gap: 12px;
      padding: 7px 0;
      border-bottom: 0;
    }
    .server-tool-table td::before {
      content: attr(data-label);
      color: var(--muted-foreground);
      font-size: 12px;
      font-weight: 800;
      text-transform: uppercase;
    }
    .server-tool-table td:first-child {
      display: grid;
      grid-template-columns: minmax(92px, max-content) minmax(0, 1fr);
      gap: 12px;
    }
    .server-tool-table td:first-child code,
    .server-tool-table td:first-child small {
      grid-column: 2;
    }
    .server-tool-table td:first-child::before {
      grid-row: 1 / span 2;
    }
    .server-tool-targets li {
      grid-template-columns: minmax(0, 1fr);
    }
    .workspace {
      padding: 18px;
    }
    .rail {
      border-right: 0;
      border-bottom: 1px solid var(--border);
    }
  }
  "
}
