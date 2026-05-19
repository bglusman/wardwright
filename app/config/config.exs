import Config

alias Phoenix.Endpoint.Cowboy2Adapter

env_config = "#{config_env()}.exs"

config :live_dashboard_history, LiveDashboardHistory,
  router: WardwrightWeb.Router,
  metrics: WardwrightWeb.Telemetry,
  buffer_size: 120

config :wardwright, WardwrightWeb.Endpoint,
  adapter: Cowboy2Adapter,
  render_errors: [
    formats: [html: WardwrightWeb.ErrorHTML, json: WardwrightWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Wardwright.PubSub,
  live_view: [signing_salt: "wardwright-policy-projection-v1"]

config :wardwright, serve_http: true

if File.exists?(Path.join(__DIR__, env_config)) do
  import_config env_config
end
