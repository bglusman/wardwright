defmodule Wardwright.LiveDashboardSinksTest do
  use ExUnit.Case, async: false

  import Plug.Test

  setup_all do
    original_config = Application.get_env(:wardwright, WardwrightWeb.Endpoint, [])

    endpoint_config =
      Keyword.merge(original_config,
        http: [ip: {127, 0, 0, 1}, port: 0],
        server: false,
        secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))
      )

    Application.put_env(:wardwright, WardwrightWeb.Endpoint, endpoint_config)
    start_supervised!(WardwrightWeb.Endpoint)

    on_exit(fn ->
      Application.put_env(:wardwright, WardwrightWeb.Endpoint, original_config)
    end)

    :ok
  end

  test "dashboard route is available for local protected access" do
    conn =
      :get
      |> conn("/dashboard")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> WardwrightWeb.Endpoint.call([])

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/dashboard/home"]
  end
end
