defmodule WardwrightWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :wardwright

  alias Phoenix.LiveView.Socket

  @session_options [
    store: :cookie,
    key: "_wardwright_key",
    signing_salt: "policy projection"
  ]

  socket("/live", Socket)

  socket("/admin/socket", WardwrightWeb.LustreWorkbenchSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers, :auth_token, session: @session_options]
    ]
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
  end

  plug(Plug.Static,
    at: "/",
    from: :wardwright,
    gzip: false,
    only: ~w(assets favicon.ico robots.txt)
  )

  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false,
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/vendor/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.Static,
    at: "/vendor/lustre",
    from: {:wardwright, "priv/static/vendor/lustre"},
    gzip: false,
    only: ~w(lustre-server-component.mjs lustre-server-component.min.mjs)
  )

  plug(Plug.Static,
    at: "/vendor/cytoscape",
    from: {:wardwright, "priv/static/vendor/cytoscape"},
    gzip: false,
    only: ~w(cytoscape.min.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Plug.MethodOverride)
  plug(Plug.Head)

  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end

  if code_reloading? do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.LiveReloader)
  end

  plug(Plug.Session, @session_options)

  plug(WardwrightWeb.Router)
end
