class WardwrightStateGraph extends HTMLElement {
  static get observedAttributes() {
    return [
      "data-states",
      "data-transitions",
      "data-active-state",
      "data-final-state"
    ];
  }

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.cy = null;
  }

  connectedCallback() {
    this.render();
  }

  attributeChangedCallback() {
    if (this.isConnected) {
      this.render();
    }
  }

  disconnectedCallback() {
    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }
  }

  render() {
    const states = parseJsonAttribute(this, "data-states", []);
    const transitions = parseJsonAttribute(this, "data-transitions", []);
    const activeState = this.getAttribute("data-active-state") || "";
    const finalState = this.getAttribute("data-final-state") || "";

    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          min-height: 460px;
          color: #18202a;
          font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }

        .shell {
          min-height: 460px;
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(220px, 280px);
          gap: 14px;
        }

        .canvas {
          min-height: 460px;
          border: 1px solid #d7dde3;
          border-radius: 8px;
          background: #f8fafb;
          overflow: hidden;
        }

        .details {
          display: flex;
          flex-direction: column;
          gap: 12px;
          min-width: 0;
          padding: 14px;
          border: 1px solid #d7dde3;
          border-radius: 8px;
          background: #fbfcfd;
        }

        .details h3 {
          margin: 0;
          font-size: 14px;
        }

        .details dl {
          display: grid;
          gap: 8px;
          margin: 0;
        }

        .details dt {
          color: #66727f;
          font-size: 11px;
          font-weight: 800;
          text-transform: uppercase;
        }

        .details dd {
          min-width: 0;
          margin: 0;
          color: #18202a;
          font-size: 12px;
          font-weight: 750;
          line-height: 1.35;
          overflow-wrap: anywhere;
        }

        .empty {
          min-height: 460px;
          display: grid;
          place-items: center;
          border: 1px solid #d7dde3;
          border-radius: 8px;
          background: #f8fafb;
          color: #66727f;
          font-size: 13px;
          font-weight: 800;
          text-align: center;
        }

        @media (max-width: 900px) {
          .shell {
            grid-template-columns: 1fr;
          }
        }
      </style>
      ${this.renderShell(transitions)}
    `;

    const canvas = this.shadowRoot.querySelector(".canvas");
    if (!canvas || !window.cytoscape) {
      return;
    }

    const activeEdgeIds = new Set(
      transitions
        .filter((edge) => edge.from === activeState || edge.to === activeState)
        .map((edge) => edge.id)
    );
    const initialDetail =
      transitions.find((edge) => activeEdgeIds.has(edge.id)) || transitions[0];

    this.cy = window.cytoscape({
      container: canvas,
      elements: [
        ...states.map((state) => ({
          data: {
            id: state.id,
            label: state.label || state.id,
            active: state.id === activeState ? "yes" : "no",
            terminal: state.id === finalState || state.terminal ? "yes" : "no"
          }
        })),
        ...transitions.map((edge) => ({
          data: {
            id: edge.id,
            source: edge.from,
            target: edge.to,
            label: edge.short_label || edge.event || edge.action || edge.id,
            event: edge.event,
            action: edge.action,
            node: edge.node,
            detail: edge.detail,
            active: activeEdgeIds.has(edge.id) ? "yes" : "no"
          }
        }))
      ],
      style: this.styles(),
      layout: {
        name: "breadthfirst",
        directed: true,
        padding: 44,
        spacingFactor: 1.22
      }
    });

    this.cy.on("mouseover", "edge", (event) => {
      event.target.addClass("hovered");
      this.showEdgeDetail(event.target.data());
    });
    this.cy.on("mouseout", "edge", (event) => {
      event.target.removeClass("hovered");
    });
    this.cy.on("tap", "edge", (event) => {
      this.cy.edges().removeClass("inspected");
      event.target.addClass("inspected");
      this.showEdgeDetail(event.target.data());
    });
    this.cy.on("tap", "node", (event) => {
      this.showStateDetail(event.target.data());
    });

    if (initialDetail) {
      this.showEdgeDetail(initialDetail);
    } else if (states[0]) {
      this.showStateDetail(states[0]);
    }

    window.requestAnimationFrame(() => {
      if (this.cy) {
        this.cy.fit(undefined, 42);
      }
    });
  }

  renderShell(transitions) {
    if (!window.cytoscape) {
      return `
        <div class="empty">
          Cytoscape renderer did not load.
        </div>
      `;
    }

    const detailHeading = transitions.length > 0
      ? "Transition detail"
      : "State detail";

    return `
      <div class="shell">
        <div class="canvas" aria-label="Interactive state graph"></div>
        <aside class="details" aria-live="polite">
          <h3>${detailHeading}</h3>
          <dl>
            <dt>Selection</dt>
            <dd data-detail="selection">No graph item selected.</dd>
            <dt>Event</dt>
            <dd data-detail="event">-</dd>
            <dt>Action</dt>
            <dd data-detail="action">-</dd>
            <dt>Projection node</dt>
            <dd data-detail="node">-</dd>
          </dl>
        </aside>
      </div>
    `;
  }

  styles() {
    return [
      {
        selector: "node",
        style: {
          "background-color": "#ffffff",
          "border-color": "#d7dde3",
          "border-width": 2,
          color: "#18202a",
          "font-family": "Inter, ui-sans-serif, system-ui, sans-serif",
          "font-size": 12,
          "font-weight": 800,
          height: 54,
          label: "data(label)",
          shape: "round-rectangle",
          "text-halign": "center",
          "text-valign": "center",
          width: 132
        }
      },
      {
        selector: "node[terminal = 'yes']",
        style: {
          "border-color": "#f0b04f"
        }
      },
      {
        selector: "node[active = 'yes']",
        style: {
          "background-color": "#dcefed",
          "border-color": "#16605a",
          "border-width": 4
        }
      },
      {
        selector: "edge",
        style: {
          "curve-style": "bezier",
          "target-arrow-shape": "triangle",
          "target-arrow-color": "#607184",
          "line-color": "#607184",
          width: 2,
          label: "",
          "font-size": 9,
          "font-weight": 800,
          color: "#66727f",
          "text-background-color": "#f8fafb",
          "text-background-opacity": 1,
          "text-background-padding": 3,
          "text-rotation": "autorotate"
        }
      },
      {
        selector: "edge[active = 'yes']",
        style: {
          label: "data(label)",
          "line-color": "#16605a",
          "target-arrow-color": "#16605a",
          width: 4,
          color: "#16605a"
        }
      },
      {
        selector: "edge.hovered, edge.inspected",
        style: {
          label: "data(label)",
          "font-size": 11,
          color: "#18202a",
          "line-color": "#26394c",
          "target-arrow-color": "#26394c",
          width: 4,
          "z-index": 10
        }
      }
    ];
  }

  showEdgeDetail(edge) {
    this.setDetail("selection", `${edge.source || edge.from} -> ${edge.target || edge.to}`);
    this.setDetail("event", edge.event || "-");
    this.setDetail("action", edge.action || "-");
    this.setDetail("node", edge.node || "-");
  }

  showStateDetail(state) {
    this.setDetail("selection", state.label || state.id || "-");
    this.setDetail("event", "state");
    this.setDetail("action", state.active === "yes" ? "active" : "available");
    this.setDetail("node", state.id || "-");
  }

  setDetail(name, value) {
    const target = this.shadowRoot.querySelector(`[data-detail="${name}"]`);
    if (target) {
      target.textContent = value;
    }
  }
}

function parseJsonAttribute(element, name, fallback) {
  try {
    const value = element.getAttribute(name);
    return value ? JSON.parse(value) : fallback;
  } catch (_error) {
    return fallback;
  }
}

if (!customElements.get("wardwright-state-graph")) {
  customElements.define("wardwright-state-graph", WardwrightStateGraph);
}
