defmodule WardwrightWeb.LustreWorkbenchController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def show(conn, _params) do
    conn = fetch_query_params(conn)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    |> put_resp_content_type("text/html")
    |> html(
      page_html(
        Plug.CSRFProtection.get_csrf_token(),
        page_param(conn.query_params),
        Map.get(conn.query_params, "model", ""),
        ""
      )
    )
  end

  def show_ux_exploration(conn, params) do
    conn = fetch_query_params(conn)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    |> put_resp_content_type("text/html")
    |> html(
      page_html(
        Plug.CSRFProtection.get_csrf_token(),
        "ux_exploration",
        Map.get(conn.query_params, "model", ""),
        Map.get(params, "concept", "")
      )
    )
  end

  def redirect_legacy_policies(conn, params) do
    conn = fetch_query_params(conn)
    model = Map.get(conn.query_params, "model") || Map.get(params, "model") || ""

    target =
      case String.trim(to_string(model)) do
        "" -> "/admin"
        model_id -> "/admin?" <> URI.encode_query(%{"model" => model_id})
      end

    redirect(conn, to: target)
  end

  defp page_html(csrf_token, page, model, concept) do
    socket_route =
      "/admin/socket/websocket?" <>
        URI.encode_query(%{
          "_csrf_token" => csrf_token,
          "concept" => concept,
          "model" => model,
          "page" => page
        })

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Wardwright Admin</title>
        <script src="/vendor/cytoscape/cytoscape.min.js"></script>
        <script type="module" src="/assets/wardwright_state_graph.js?v=graph-boundaries-5"></script>
        <script type="module" src="/vendor/lustre/lustre-server-component.mjs"></script>
        <script>
          (() => {
            const componentSelector = 'lustre-server-component[data-runtime="lustre-server-component"]';

            const currentComponent = () => document.querySelector(componentSelector);

            const idFromHash = (hash) => {
              const raw = String(hash || "").replace(/^#/, "");
              try {
                return decodeURIComponent(raw);
              } catch {
                return raw;
              }
            };

            const targetFromHash = (hash) => {
              const id = idFromHash(hash);
              if (!id) return null;
              return currentComponent()?.shadowRoot?.getElementById(id) || null;
            };

            const scrollToHash = (hash, behavior = "auto") => {
              const target = targetFromHash(hash);
              if (!target) return false;
              const top = Math.max(0, target.getBoundingClientRect().top + scrollY - 16);
              scrollTo({ top, behavior });
              return true;
            };

            const anchorFromEvent = (event) =>
              event.composedPath?.().find((node) => node?.tagName === "A" && node.href);

            const bindComponentMount = () => {
              const component = currentComponent();
              if (!component || component.dataset.anchorBridge === "ready") return;
              component.dataset.anchorBridge = "ready";
              component.addEventListener("lustre:mount", () =>
                requestAnimationFrame(() => scrollToHash(location.hash))
              );
              requestAnimationFrame(() => scrollToHash(location.hash));
            };

            document.addEventListener("click", (event) => {
              const anchor = anchorFromEvent(event);
              if (!anchor) return;

              const url = new URL(anchor.href, location.href);
              if (
                url.origin !== location.origin ||
                url.pathname !== location.pathname ||
                url.search !== location.search ||
                !url.hash ||
                !targetFromHash(url.hash)
              ) {
                return;
              }

              event.preventDefault();
              history.pushState(null, "", url.pathname + url.search + url.hash);
              scrollToHash(url.hash, "smooth");
            });

            addEventListener("hashchange", () => scrollToHash(location.hash, "smooth"));
            addEventListener("popstate", () => scrollToHash(location.hash));
            document.addEventListener("DOMContentLoaded", bindComponentMount, { once: true });
            bindComponentMount();
          })();
        </script>
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
          lustre-server-component {
            display: block;
            min-height: 100vh;
            max-width: 100vw;
            overflow-x: clip;
          }
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

  defp page_param(%{"view" => "model_access"}), do: "model_access"
  defp page_param(%{"view" => "control_debugger"}), do: "control_debugger"
  defp page_param(%{"page" => "model_access"}), do: "model_access"
  defp page_param(%{"page" => "control_debugger"}), do: "control_debugger"
  defp page_param(_query_params), do: "workbench"
end
