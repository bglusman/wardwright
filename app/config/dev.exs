import Config

config :phoenix_live_view,
  debug_attributes: true,
  debug_heex_annotations: true

config :wardwright, WardwrightWeb.Endpoint,
  code_reloader: true,
  debug_errors: true,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/wardwright_web/(controllers|live|components|layouts)/.*(ex|heex)$",
      ~r"lib/wardwright_web/.*_controller.ex$",
      ~r"lib/wardwright_web/.*_socket.ex$",
      ~r"src/wardwright/.*\.gleam$"
    ]
  ]
