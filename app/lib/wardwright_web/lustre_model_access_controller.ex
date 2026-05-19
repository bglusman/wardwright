defmodule WardwrightWeb.LustreModelAccessController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def show(conn, params) do
    conn = fetch_query_params(conn)
    selected_model = Map.get(conn.query_params, "model", Map.get(params, "model", ""))

    conn
    |> put_session(:wardwright_model_access_model, selected_model)
    |> put_resp_content_type("text/html")
    |> html(page_html(Plug.CSRFProtection.get_csrf_token(), selected_model))
  end

  defp page_html(csrf_token, selected_model) do
    socket_route =
      "/admin/model-api-keys/socket/websocket?" <>
        URI.encode_query(%{"_csrf_token" => csrf_token, "model" => selected_model})

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Wardwright Model Access</title>
        <script type="module" src="/vendor/lustre/lustre-server-component.mjs"></script>
        <style>
          :root {
            --background: #f4f6f8;
            --foreground: #18202a;
            --card: #ffffff;
            --primary: #16605a;
            --primary-foreground: #ffffff;
            --muted-foreground: #66727f;
            --accent: #dcefed;
            --destructive: #b42318;
            --border: #d7dde3;
            --input: #c9d2da;
          }

          * { box-sizing: border-box; }
          body {
            margin: 0;
            min-height: 100vh;
            background: var(--background);
            color: var(--foreground);
            font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }
          lustre-server-component { display: block; min-height: 100vh; }
        </style>
      </head>
      <body>
        <lustre-server-component
          route="#{socket_route}"
          data-runtime="lustre-server-component"
        ></lustre-server-component>
      </body>
    </html>
    """
  end
end
