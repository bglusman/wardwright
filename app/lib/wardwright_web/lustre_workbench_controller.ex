defmodule WardwrightWeb.LustreWorkbenchController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> html(page_html(Plug.CSRFProtection.get_csrf_token()))
  end

  defp page_html(csrf_token) do
    socket_route =
      "/spikes/lustre-workbench/socket/websocket?" <>
        URI.encode_query(%{"_csrf_token" => csrf_token})

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Wardwright Lustre Workbench Spike</title>
        <script src="/vendor/cytoscape/cytoscape.min.js"></script>
        <script type="module" src="/assets/wardwright_state_graph.js?v=graph-boundaries-5"></script>
        <script type="module" src="/vendor/lustre/lustre-server-component.mjs"></script>
        <style>
          :root {
            --background: #f4f6f8;
            --foreground: #18202a;
            --card: #ffffff;
            --card-foreground: #18202a;
            --primary: #16605a;
            --primary-foreground: #ffffff;
            --secondary: #f0b04f;
            --secondary-foreground: #1f2933;
            --muted: #e7eaee;
            --muted-foreground: #66727f;
            --accent: #dcefed;
            --accent-foreground: #123f3c;
            --destructive: #b42318;
            --destructive-foreground: #ffffff;
            --border: #d7dde3;
            --input: #c9d2da;
            --ring: #1c7d74;
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
