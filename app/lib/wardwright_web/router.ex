defmodule WardwrightWeb.Router do
  @moduledoc false

  use Phoenix.Router, helpers: false

  import Phoenix.LiveDashboard.Router

  alias Hermes.Server.Transport.StreamableHTTP.Plug

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
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

  scope "/", WardwrightWeb do
    pipe_through([:browser, :protected_browser])

    get("/", LustreWorkbenchController, :show)
    get("/admin", LustreWorkbenchController, :show)
    get("/policies", LustreWorkbenchController, :redirect_legacy_policies)
    get("/policies/*path", LustreWorkbenchController, :redirect_legacy_policies)
    get("/spikes/graph-renderer-lab", GraphRendererLabController, :show)
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
      Plug,
      server: WardwrightWeb.MCPServer
    )
  end

  scope "/" do
    pipe_through(:api)

    forward("/", Wardwright.Router)
  end
end
