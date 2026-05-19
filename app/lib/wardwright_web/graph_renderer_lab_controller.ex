defmodule WardwrightWeb.GraphRendererLabController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> html(page_html())
  end

  defp page_html do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Wardwright Graph Renderer Lab</title>
        <script src="/vendor/cytoscape/cytoscape.min.js"></script>
        <style>
          :root {
            --background: #f4f6f8;
            --foreground: #18202a;
            --panel: #ffffff;
            --panel-foreground: #18202a;
            --primary: #16605a;
            --primary-foreground: #ffffff;
            --secondary: #f0b04f;
            --secondary-foreground: #1f2933;
            --muted: #e7eaee;
            --muted-foreground: #66727f;
            --accent: #dcefed;
            --accent-foreground: #123f3c;
            --border: #d7dde3;
            --edge: #607184;
          }

          * { box-sizing: border-box; }

          body {
            margin: 0;
            min-height: 100vh;
            background: var(--background);
            color: var(--foreground);
            font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }

          .graph-lab {
            min-height: 100vh;
            display: flex;
            flex-direction: column;
          }

          .topbar {
            display: flex;
            justify-content: space-between;
            gap: 20px;
            align-items: center;
            padding: 18px 24px;
            border-bottom: 1px solid var(--border);
            background: #fbfcfd;
          }

          .title-block {
            display: flex;
            flex-direction: column;
            gap: 4px;
            min-width: 0;
          }

          .title-block strong {
            font-size: 18px;
          }

          .title-block span,
          .control label,
          .renderer-heading span,
          .metric span,
          .renderer-note {
            color: var(--muted-foreground);
            font-size: 12px;
            font-weight: 700;
          }

          .topbar-actions {
            display: flex;
            gap: 10px;
            align-items: center;
            flex-wrap: wrap;
            justify-content: flex-end;
          }

          .button {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            min-height: 36px;
            padding: 8px 12px;
            border-radius: 8px;
            border: 1px solid var(--border);
            color: var(--foreground);
            background: #ffffff;
            font-size: 13px;
            font-weight: 800;
            text-decoration: none;
            cursor: pointer;
          }

          .button.active,
          .button.primary {
            color: var(--primary-foreground);
            border-color: var(--primary);
            background: var(--primary);
          }

          .workspace {
            width: 100%;
            max-width: 1440px;
            margin: 0 auto;
            padding: 20px 24px 28px;
            display: flex;
            flex-direction: column;
            gap: 16px;
          }

          .toolbar {
            display: grid;
            grid-template-columns: minmax(220px, 360px) minmax(280px, 1fr) auto;
            gap: 16px;
            align-items: end;
            padding: 16px;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--panel);
          }

          .control {
            display: flex;
            flex-direction: column;
            gap: 8px;
          }

          select,
          input[type="range"] {
            width: 100%;
            min-height: 38px;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: #ffffff;
            color: var(--foreground);
            font: inherit;
          }

          select {
            padding: 8px 10px;
            font-weight: 750;
          }

          input[type="range"] {
            accent-color: var(--primary);
          }

          .metrics {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
            justify-content: flex-end;
          }

          .metric {
            min-width: 104px;
            padding: 9px 10px;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: #fbfcfd;
          }

          .metric strong,
          .metric span {
            display: block;
          }

          .comparison {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 16px;
          }

          .renderer {
            min-width: 0;
            min-height: 560px;
            display: flex;
            flex-direction: column;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--panel);
            overflow: hidden;
          }

          .renderer-heading {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 12px;
            padding: 14px 16px;
            border-bottom: 1px solid var(--border);
            background: #fbfcfd;
          }

          .renderer-heading div {
            display: flex;
            flex-direction: column;
            gap: 4px;
            min-width: 0;
          }

          .renderer-heading strong {
            font-size: 15px;
          }

          .badge {
            flex: 0 0 auto;
            padding: 4px 8px;
            border-radius: 999px;
            border: 1px solid var(--border);
            color: var(--accent-foreground);
            background: var(--accent);
            font-size: 11px;
            font-weight: 850;
            text-transform: uppercase;
          }

          .graph-frame {
            position: relative;
            flex: 1 1 auto;
            min-height: 420px;
            background: #f8fafb;
          }

          #baseline-graph,
          #cy-graph {
            width: 100%;
            height: 100%;
            min-height: 420px;
          }

          .renderer-note {
            min-height: 74px;
            padding: 12px 16px 14px;
            border-top: 1px solid var(--border);
            line-height: 1.5;
            background: #ffffff;
          }

          .baseline-map {
            min-height: 420px;
            display: grid;
            grid-template-rows: auto minmax(0, 1fr);
            gap: 22px;
            padding: 28px;
          }

          .baseline-state-track {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(112px, 1fr));
            gap: 10px;
            align-items: stretch;
          }

          .baseline-state {
            min-height: 72px;
            display: flex;
            flex-direction: column;
            justify-content: center;
            gap: 6px;
            padding: 12px;
            border: 2px solid var(--border);
            border-radius: 8px;
            background: #ffffff;
          }

          .baseline-state.active {
            border-color: var(--primary);
            background: var(--accent);
          }

          .baseline-state.terminal {
            border-color: var(--secondary);
          }

          .baseline-state strong {
            font-size: 13px;
            line-height: 1.2;
            overflow-wrap: anywhere;
          }

          .baseline-state span,
          .baseline-edge span {
            color: var(--muted-foreground);
            font-size: 11px;
            font-weight: 780;
            line-height: 1.35;
          }

          .baseline-edges {
            display: grid;
            gap: 10px;
            align-content: start;
          }

          .baseline-edge {
            display: grid;
            grid-template-columns: minmax(110px, 0.55fr) minmax(0, 1fr);
            gap: 12px;
            align-items: center;
            padding: 12px;
            border: 1px solid var(--border);
            border-left: 4px solid var(--edge);
            border-radius: 8px;
            background: #ffffff;
          }

          .baseline-edge.active {
            border-left-color: var(--primary);
            background: var(--accent);
          }

          .baseline-edge strong {
            font-size: 12px;
            line-height: 1.25;
            overflow-wrap: anywhere;
          }

          .baseline-edge span {
            overflow-wrap: anywhere;
          }

          @media (max-width: 980px) {
            .toolbar {
              grid-template-columns: 1fr;
            }

            .metrics {
              justify-content: flex-start;
            }

            .comparison {
              grid-template-columns: 1fr;
            }

            .baseline-edge {
              grid-template-columns: 1fr;
            }
          }

          @media (max-width: 640px) {
            .topbar {
              align-items: flex-start;
              flex-direction: column;
              padding: 16px;
            }

            .topbar-actions {
              width: 100%;
              justify-content: flex-start;
            }

            .workspace {
              padding: 14px 12px 20px;
            }
          }
        </style>
      </head>
      <body>
        <main class="graph-lab">
          <header class="topbar">
            <div class="title-block">
              <strong>Graph renderer lab</strong>
              <span>Same toy state machine, hand-laid baseline vs browser graph renderer.</span>
            </div>
            <nav class="topbar-actions" aria-label="Workbench navigation">
              <a class="button" href="/admin">Workbench</a>
              <a class="button" href="/policies">Legacy workbench</a>
            </nav>
          </header>

          <section class="workspace">
            <div class="toolbar">
              <div class="control">
                <label for="graph-select">Toy graph</label>
                <select id="graph-select">
                  <option value="retry">Streaming retry policy</option>
                  <option value="route">Model route composition</option>
                </select>
              </div>
              <div class="control">
                <label id="step-label" for="step-range">Active transition</label>
                <input id="step-range" type="range" min="0" value="0" step="1">
              </div>
              <div class="metrics" aria-label="Graph metrics">
                <div class="metric"><span>States</span><strong id="state-count">0</strong></div>
                <div class="metric"><span>Transitions</span><strong id="transition-count">0</strong></div>
              </div>
            </div>

            <div class="comparison">
              <section class="renderer" aria-label="Hand-laid graph baseline">
                <div class="renderer-heading">
                  <div>
                    <strong>Hand-laid baseline</strong>
                    <span>Deterministic layout close to the current server-rendered page.</span>
                  </div>
                  <span class="badge">No graph lib</span>
                </div>
                <div class="graph-frame">
                  <div id="baseline-graph" role="img" aria-label="Hand laid state graph"></div>
                </div>
                <div class="renderer-note">
                  Stable and dependency-light. It makes ordering explicit, but richer nesting, zoom, collision handling, and exports become our code to maintain.
                </div>
              </section>

              <section class="renderer" aria-label="Cytoscape style graph renderer">
                <div class="renderer-heading">
                  <div>
                    <strong>Cytoscape-style renderer</strong>
                    <span>Browser layout approach patterned after the graph-renderer experiment.</span>
                  </div>
                  <span class="badge">Zoom + pan</span>
                </div>
                <div class="graph-frame">
                  <div id="cy-graph" role="img" aria-label="Browser rendered state graph"></div>
                </div>
                <div class="renderer-note">
                  Better interaction and automatic layout. It also brings a JavaScript-target/browser asset path, so it should stay isolated until it proves enough value.
                </div>
              </section>
            </div>
          </section>
        </main>

        <script>
          const graphs = {
            retry: {
              states: [
                { id: "observing", label: "observing", terminal: false },
                { id: "guarding", label: "guarding", terminal: false },
                { id: "retrying", label: "retrying", terminal: false },
                { id: "recording", label: "recording", terminal: true }
              ],
              transitions: [
                { from: "observing", to: "guarding", event: "stream.start", action: "watch", node: "stream.open" },
                { from: "guarding", to: "retrying", event: "stream.match", action: "abort_attempt", node: "tts.no-old-client" },
                { from: "retrying", to: "guarding", event: "retry.start", action: "dispatch", node: "tts.retry" },
                { from: "guarding", to: "recording", event: "stream.complete", action: "record_receipt", node: "receipt.final" }
              ]
            },
            route: {
              states: [
                { id: "intake", label: "intake", terminal: false },
                { id: "privacy_gate", label: "privacy gate", terminal: false },
                { id: "local_model", label: "local model", terminal: false },
                { id: "managed_model", label: "managed model", terminal: false },
                { id: "audit", label: "audit", terminal: true }
              ],
              transitions: [
                { from: "intake", to: "privacy_gate", event: "request.received", action: "classify", node: "route.inspect" },
                { from: "privacy_gate", to: "local_model", event: "sensitive", action: "force_local", node: "route.private" },
                { from: "privacy_gate", to: "managed_model", event: "routine", action: "allow_provider", node: "route.public" },
                { from: "local_model", to: "audit", event: "response.ready", action: "receipt", node: "receipt.local" },
                { from: "managed_model", to: "audit", event: "response.ready", action: "receipt", node: "receipt.provider" }
              ]
            }
          };

          const graphSelect = document.getElementById("graph-select");
          const stepRange = document.getElementById("step-range");
          const stepLabel = document.getElementById("step-label");
          const stateCount = document.getElementById("state-count");
          const transitionCount = document.getElementById("transition-count");
          const baselineGraph = document.getElementById("baseline-graph");
          let cy = null;

          function activeTransition(graph) {
            return graph.transitions[Number(stepRange.value)] || graph.transitions[0];
          }

          function edgeLabel(edge) {
            return `${edge.event} / ${edge.action} / ${edge.node}`;
          }

          function renderBaseline(graph) {
            const active = activeTransition(graph);
            const terminalIds = new Set(graph.states.filter((state) => state.terminal).map((state) => state.id));

            const states = graph.states.map((state) => {
              const activeClass = active && (state.id === active.from || state.id === active.to) ? " active" : "";
              const terminalClass = terminalIds.has(state.id) ? " terminal" : "";

              return `
                <div class="baseline-state${activeClass}${terminalClass}">
                  <strong>${escapeHtml(state.label)}</strong>
                  <span>${escapeHtml(state.id)}</span>
                </div>
              `;
            }).join("");

            const edges = graph.transitions.map((edge) => {
              const activeClass = edge === active ? " active" : "";

              return `
                <div class="baseline-edge${activeClass}">
                  <strong>${escapeHtml(edge.from)} -> ${escapeHtml(edge.to)}</strong>
                  <span>${escapeHtml(edgeLabel(edge))}</span>
                </div>
              `;
            }).join("");

            baselineGraph.innerHTML = `
              <div class="baseline-map">
                <div class="baseline-state-track">${states}</div>
                <div class="baseline-edges">${edges}</div>
              </div>
            `;
          }

          function renderCytoscape(graph) {
            const active = activeTransition(graph);
            const elements = [
              ...graph.states.map((state) => ({
                data: { id: state.id, label: state.label, terminal: state.terminal ? "yes" : "no" }
              })),
              ...graph.transitions.map((edge, index) => ({
                data: {
                  id: `edge-${index}`,
                  source: edge.from,
                  target: edge.to,
                  label: edgeLabel(edge),
                  active: edge === active ? "yes" : "no"
                }
              }))
            ];

            if (!window.cytoscape) {
              document.getElementById("cy-graph").textContent = "Cytoscape failed to load.";
              return;
            }

            cy = cytoscape({
              container: document.getElementById("cy-graph"),
              elements,
              wheelSensitivity: 0.18,
              style: [
                {
                  selector: "node",
                  style: {
                    "background-color": "#ffffff",
                    "border-color": "#d7dde3",
                    "border-width": 2,
                    "color": "#18202a",
                    "font-family": "Inter, ui-sans-serif, system-ui, sans-serif",
                    "font-size": 12,
                    "font-weight": 800,
                    "height": 54,
                    "label": "data(label)",
                    "shape": "round-rectangle",
                    "text-halign": "center",
                    "text-valign": "center",
                    "width": 132
                  }
                },
                {
                  selector: "node[terminal = 'yes']",
                  style: {
                    "border-color": "#f0b04f"
                  }
                },
                {
                  selector: "edge",
                  style: {
                    "curve-style": "bezier",
                    "target-arrow-shape": "triangle",
                    "target-arrow-color": "#607184",
                    "line-color": "#607184",
                    "width": 2,
                    "label": "data(label)",
                    "font-size": 9,
                    "font-weight": 700,
                    "color": "#66727f",
                    "text-background-color": "#f8fafb",
                    "text-background-opacity": 1,
                    "text-background-padding": 3,
                    "text-rotation": "autorotate"
                  }
                },
                {
                  selector: "edge[active = 'yes']",
                  style: {
                    "line-color": "#16605a",
                    "target-arrow-color": "#16605a",
                    "width": 4,
                    "color": "#16605a",
                    "font-weight": 900
                  }
                },
                {
                  selector: ".active-node",
                  style: {
                    "background-color": "#dcefed",
                    "border-color": "#16605a",
                    "border-width": 4
                  }
                }
              ],
              layout: {
                name: "breadthfirst",
                directed: true,
                padding: 48,
                spacingFactor: 1.25
              }
            });

            cy.nodes().removeClass("active-node");
            if (active) {
              cy.getElementById(active.from).addClass("active-node");
              cy.getElementById(active.to).addClass("active-node");
            }
            cy.fit(undefined, 42);
          }

          function render() {
            const graph = graphs[graphSelect.value];
            stepRange.max = Math.max(graph.transitions.length - 1, 0);
            if (Number(stepRange.value) > Number(stepRange.max)) {
              stepRange.value = stepRange.max;
            }

            const active = activeTransition(graph);
            stepLabel.textContent = active
              ? `Active transition: ${active.from} -> ${active.to}`
              : "Active transition";
            stateCount.textContent = graph.states.length;
            transitionCount.textContent = graph.transitions.length;

            renderBaseline(graph);
            renderCytoscape(graph);
          }

          function escapeHtml(value) {
            return value
              .replaceAll("&", "&amp;")
              .replaceAll("<", "&lt;")
              .replaceAll(">", "&gt;")
              .replaceAll('"', "&quot;");
          }

          graphSelect.addEventListener("change", () => {
            stepRange.value = "0";
            render();
          });
          stepRange.addEventListener("input", render);
          window.addEventListener("resize", () => {
            if (cy) cy.fit(undefined, 42);
          });

          render();
        </script>
      </body>
    </html>
    """
  end
end
