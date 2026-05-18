defmodule WardwrightWeb.Router do
  @moduledoc false

  use Phoenix.Router, helpers: false
  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {WardwrightWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :protected_browser do
    plug(WardwrightWeb.ProtectedAccess)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :protected_api do
    plug(WardwrightWeb.ProtectedAccess)
  end

  pipeline :protected_browser do
    plug(WardwrightWeb.ProtectedAccess)
  end

  scope "/", WardwrightWeb do
    pipe_through([:browser, :protected_browser])

    live("/", PolicyProjectionLive, :index)
    live("/policies", PolicyProjectionLive, :index)
    live("/policies/:pattern/:mode/recipe/:recipe/step/:step", PolicyProjectionLive, :index)
    live("/policies/:pattern/:mode/recipe/:recipe", PolicyProjectionLive, :index)
    live("/policies/:pattern/:mode/step/:step", PolicyProjectionLive, :index)
    live("/policies/:pattern/:mode", PolicyProjectionLive, :index)
  end

  scope "/" do
    pipe_through([:browser, :protected_browser])

    live_dashboard("/dashboard",
      metrics: WardwrightWeb.Telemetry,
      metrics_history: {LiveDashboardHistory, :metrics_history, [__MODULE__]}
    )
  end

  scope "/" do
    pipe_through(:protected_api)

    forward(
      "/mcp",
      Hermes.Server.Transport.StreamableHTTP.Plug,
      server: WardwrightWeb.MCPServer
    )
  end

  scope "/" do
    pipe_through(:api)

    forward("/", Wardwright.Router)
  end
end
