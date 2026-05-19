import Config

code_reloader? = System.get_env("WARDWRIGHT_CODE_RELOADER", "true") != "false"
gleam_code_reloader? = System.get_env("WARDWRIGHT_GLEAM_CODE_RELOADER", "false") == "true"

reloadable_compilers =
  if code_reloader? do
    [:elixir, :app] ++ if(gleam_code_reloader?, do: [:gleam, :erlang], else: [])
  else
    []
  end

live_reload_patterns = [
  ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
  ~r"lib/wardwright_web/(controllers|live|components|layouts)/.*(ex|heex)$",
  ~r"lib/wardwright_web/.*_controller.ex$",
  ~r"lib/wardwright_web/.*_socket.ex$"
]

live_reload_patterns =
  live_reload_patterns ++
    if(gleam_code_reloader?, do: [~r"src/wardwright/.*\.gleam$"], else: [])

config :phoenix_live_view,
  debug_attributes: true,
  debug_heex_annotations: true

config :wardwright, WardwrightWeb.Endpoint,
  code_reloader: code_reloader?,
  debug_errors: true,
  reloadable_compilers: reloadable_compilers,
  live_reload: [
    patterns: live_reload_patterns
  ]
