defmodule WardwrightWeb.SprocketSimulatorController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  def index(conn, params) do
    conn = fetch_query_params(conn)
    params = Map.merge(params, conn.query_params)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, WardwrightWeb.SprocketWorkbenchPage.render(params))
  end
end
