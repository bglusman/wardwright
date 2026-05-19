class WardwrightStateGraph extends HTMLElement {
  static get observedAttributes() {
    return [
      "data-states",
      "data-transitions",
      "data-active-state",
      "data-final-state",
      "data-model-id"
    ];
  }

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.cy = null;
    this.interactionAbort = null;
    this.lastGraphKey = "";
    this.pendingRender = null;
  }

  connectedCallback() {
    this.scheduleRender();
  }

  attributeChangedCallback() {
    if (this.isConnected) {
      this.scheduleRender();
    }
  }

  disconnectedCallback() {
    if (this.pendingRender) {
      window.cancelAnimationFrame(this.pendingRender);
      this.pendingRender = null;
    }

    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }

    if (this.interactionAbort) {
      this.interactionAbort.abort();
      this.interactionAbort = null;
    }
  }

  scheduleRender() {
    if (this.pendingRender) {
      window.cancelAnimationFrame(this.pendingRender);
    }

    this.pendingRender = window.requestAnimationFrame(() => {
      this.pendingRender = null;
      this.render();
    });
  }

  render() {
    const states = parseJsonAttribute(this, "data-states", []);
    const transitions = parseJsonAttribute(this, "data-transitions", []);
    const activeState = this.getAttribute("data-active-state") || "";
    const finalState = this.getAttribute("data-final-state") || "";
    const rootModelId = this.getAttribute("data-model-id") || "";
    const graphKey = graphTopologyKey(states, transitions);
    const previousViewport = this.cy
      ? { zoom: this.cy.zoom(), pan: this.cy.pan() }
      : null;
    const preserveViewport =
      previousViewport && this.lastGraphKey !== "" && this.lastGraphKey === graphKey;

    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }

    this.shadowRoot.innerHTML = `
      <style>
        :host {
          display: block;
          container-type: inline-size;
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
          height: 460px;
          min-height: 460px;
          border: 1px solid #d7dde3;
          border-radius: 8px;
          background: #f8fafb;
          cursor: grab;
          overflow: hidden;
          touch-action: none;
        }

        .canvas:active {
          cursor: grabbing;
        }

        .graph-frame {
          position: relative;
          min-height: 460px;
        }

        .viewport-controls {
          position: absolute;
          top: 10px;
          right: 10px;
          z-index: 2;
          display: flex;
          gap: 6px;
        }

        .viewport-controls button {
          width: 32px;
          height: 32px;
          display: grid;
          place-items: center;
          border: 1px solid #c7d0d9;
          border-radius: 8px;
          background: rgba(255, 255, 255, 0.92);
          color: #1f2a37;
          cursor: pointer;
          font: inherit;
          font-size: 15px;
          font-weight: 900;
          line-height: 1;
        }

        .viewport-controls button:hover {
          border-color: #16605a;
          color: #16605a;
        }

        .viewport-controls svg {
          width: 15px;
          height: 15px;
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

        @container (max-width: 780px) {
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
    const pathEdgeIds = new Set(
      transitions.filter((edge) => edge.path || edge.current).map((edge) => edge.id)
    );
    const groupElements = modelGroupElements(states, rootModelId);
    const graphStates = states.map((state) =>
      stateElement(state, rootModelId, activeState, finalState)
    );
    const graphTransitions = transitions.map((edge) =>
      edgeElement(edge, rootModelId, activeEdgeIds)
    );
    const initialDetail =
      graphTransitions.find((edge) => edge.data.current === "yes")?.data ||
      graphTransitions.find((edge) => pathEdgeIds.has(edge.data.id))?.data ||
      graphTransitions.find((edge) => activeEdgeIds.has(edge.data.id))?.data ||
      graphTransitions[0]?.data;

    this.cy = window.cytoscape({
      container: canvas,
      elements: [
        ...groupElements,
        ...graphStates,
        ...graphTransitions
      ],
      style: this.styles(),
      minZoom: 0.55,
      maxZoom: 1.75,
      wheelSensitivity: 0.14,
      userPanningEnabled: true,
      userZoomingEnabled: true,
      boxSelectionEnabled: false,
      autoungrabify: true,
      layout: {
        name: "breadthfirst",
        directed: true,
        avoidOverlap: true,
        nodeDimensionsIncludeLabels: true,
        padding: 72,
        spacingFactor: graphSpacingFactor(states, transitions)
      }
    });
    this.lastGraphKey = graphKey;

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
    this.bindGraphWheel(canvas);
    this.bindViewportControls();

    const activeNode = this.cy.getElementById(activeState);
    if (activeNode.nonempty()) {
      activeNode.addClass("inspected");
      this.showStateDetail(activeNode.data());
    } else if (initialDetail) {
      this.showEdgeDetail(initialDetail);
    } else if (graphStates[0]) {
      this.showStateDetail(graphStates[0].data);
    }

    window.requestAnimationFrame(() => {
      if (this.cy) {
        this.cy.resize();

        if (preserveViewport) {
          this.cy.zoom(clamp(previousViewport.zoom, this.minZoom(), this.maxZoom()));
          this.cy.pan(previousViewport.pan);
        } else {
          this.cy.fit(undefined, 42);
        }
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
        <div class="graph-frame">
          <div class="canvas" aria-label="Interactive state graph"></div>
          <div class="viewport-controls" aria-label="Graph viewport controls">
            <button type="button" data-graph-action="zoom-in" aria-label="Zoom in" title="Zoom in">+</button>
            <button type="button" data-graph-action="zoom-out" aria-label="Zoom out" title="Zoom out">-</button>
            <button type="button" data-graph-action="fit" aria-label="Fit graph" title="Fit graph">
              <svg viewBox="0 0 16 16" aria-hidden="true">
                <path d="M3 6V3h3M10 3h3v3M13 10v3h-3M6 13H3v-3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"></path>
              </svg>
            </button>
          </div>
        </div>
        <aside class="details" aria-live="polite">
          <h3>${detailHeading}</h3>
          <dl>
            <dt>Selection</dt>
            <dd data-detail="selection">No graph item selected.</dd>
            <dt>Model</dt>
            <dd data-detail="model">-</dd>
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
          height: 58,
          label: "data(label)",
          shape: "round-rectangle",
          "text-halign": "center",
          "text-max-width": 116,
          "text-wrap": "wrap",
          "text-valign": "center",
          width: 138
        }
      },
      {
        selector: ".model-group",
        style: {
          "background-color": "#e7f2f1",
          "background-opacity": 0.38,
          "border-color": "#74a29e",
          "border-style": "dashed",
          "border-width": 2,
          color: "#395762",
          events: "no",
          "font-size": 11,
          "font-weight": 850,
          label: "data(label)",
          padding: 26,
          shape: "round-rectangle",
          "text-background-color": "#f8fafb",
          "text-background-opacity": 0.94,
          "text-background-padding": 4,
          "text-halign": "center",
          "text-margin-y": -8,
          "text-valign": "top",
          "text-wrap": "wrap",
          "z-compound-depth": "bottom",
          "z-index": 0
        }
      },
      {
        selector: ".model-group[groupDepth = '2']",
        style: {
          "background-color": "#eef1fb",
          "border-color": "#9aa7d8"
        }
      },
      {
        selector: ".model-group[groupDepth = '3']",
        style: {
          "background-color": "#fbf3e5",
          "border-color": "#d5a75d"
        }
      },
      {
        selector: ".nested-state",
        style: {
          "background-color": "#f8fdfc",
          "border-color": "#7aa9a5"
        }
      },
      {
        selector: "node[visited = 'yes']",
        style: {
          "border-color": "#31a096",
          "border-width": 3
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
          "text-margin-y": -8,
          "text-rotation": "none"
        }
      },
      {
        selector: ".model-boundary-edge",
        style: {
          "line-color": "#a46b18",
          "line-style": "dashed",
          "target-arrow-color": "#a46b18",
          width: 3,
          "z-index": 6
        }
      },
      {
        selector: "edge[path = 'yes']",
        style: {
          "line-color": "#16605a",
          "target-arrow-color": "#16605a",
          width: 4,
          color: "#16605a"
        }
      },
      {
        selector: "edge[current = 'yes']",
        style: {
          label: "data(label)",
          "line-color": "#9b6b18",
          "target-arrow-color": "#9b6b18",
          width: 5,
          color: "#9b6b18",
          "z-index": 9
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

  bindViewportControls() {
    this.shadowRoot
      .querySelector('[data-graph-action="zoom-in"]')
      ?.addEventListener("click", () => this.zoomBy(1.18));
    this.shadowRoot
      .querySelector('[data-graph-action="zoom-out"]')
      ?.addEventListener("click", () => this.zoomBy(1 / 1.18));
    this.shadowRoot
      .querySelector('[data-graph-action="fit"]')
      ?.addEventListener("click", () => this.fitView());
  }

  bindGraphWheel(canvas) {
    if (this.interactionAbort) {
      this.interactionAbort.abort();
    }

    this.interactionAbort = new AbortController();
    const signal = this.interactionAbort.signal;

    const zoomWheel = (event) => {
      if (!this.cy) {
        return;
      }

      const rect = canvas.getBoundingClientRect();

      if (
        event.clientX < rect.left ||
        event.clientX > rect.right ||
        event.clientY < rect.top ||
        event.clientY > rect.bottom
      ) {
        return;
      }

      const factor = clamp(Math.exp(-event.deltaY * WHEEL_ZOOM_INTENSITY), 0.88, 1.12);
      const zoom = clamp(this.cy.zoom() * factor, this.minZoom(), this.maxZoom());

      this.cy.zoom({
        level: zoom,
        renderedPosition: {
          x: event.clientX - rect.left,
          y: event.clientY - rect.top
        }
      });
      event.preventDefault();
      event.stopPropagation();
    };

    canvas.addEventListener(
      "wheel",
      zoomWheel,
      { capture: true, passive: false, signal }
    );
    this.addEventListener(
      "wheel",
      zoomWheel,
      { capture: true, passive: false, signal }
    );
  }

  zoomBy(factor) {
    if (!this.cy) {
      return;
    }

    const zoom = clamp(this.cy.zoom() * factor, this.minZoom(), this.maxZoom());
    this.cy.animate({
      zoom,
      center: { eles: this.cy.elements() },
      duration: 100
    });
  }

  fitView() {
    if (this.cy) {
      this.cy.animate({
        fit: { eles: this.cy.elements(), padding: 42 },
        duration: 140
      });
    }
  }

  minZoom() {
    return 0.55;
  }

  maxZoom() {
    return 1.75;
  }

  showEdgeDetail(edge) {
    this.setDetail(
      "selection",
      `${edge.sourceLabel || edge.source || edge.from} -> ${edge.targetLabel || edge.target || edge.to}`
    );
    this.setDetail("model", edge.modelLabel || "-");
    this.setDetail("event", edge.event || "-");
    this.setDetail("action", edge.action || "-");
    this.setDetail("node", edge.node || "-");
  }

  showStateDetail(state) {
    this.setDetail("selection", state.fullLabel || state.label || state.id || "-");
    this.setDetail("model", state.modelLabel || "-");
    this.setDetail("event", "state");
    this.setDetail("action", state.active === "yes" || state.active === true ? "active" : "available");
    this.setDetail("node", state.id || "-");
  }

  setDetail(name, value) {
    const target = this.shadowRoot.querySelector(`[data-detail="${name}"]`);
    if (target) {
      target.textContent = value;
    }
  }
}

const ROOT_MODEL_NAMESPACE = "__wardwright_root_model__";
const WHEEL_ZOOM_INTENSITY = 0.0012;

function modelGroupElements(states, rootModelId) {
  const namespaces = new Set();

  states.forEach((state) => {
    namespacePrefixes(stateNamespace(state.id))
      .filter((namespace) => namespace !== ROOT_MODEL_NAMESPACE)
      .forEach((namespace) => {
        namespaces.add(namespace);
      });
  });

  return [...namespaces]
    .sort((left, right) => modelDepth(left) - modelDepth(right))
    .map((namespace) => {
      const parent = parentNamespace(namespace);
      const data = {
        id: modelGroupId(namespace),
        label: modelLabel(namespace, rootModelId),
        modelGroup: "yes",
        modelNamespace: namespace,
        groupDepth: String(Math.min(modelDepth(namespace), 3))
      };

      if (parent) {
        data.parent = modelGroupId(parent);
      }

      return {
        data,
        classes: `model-group model-depth-${Math.min(modelDepth(namespace), 3)}`
      };
    });
}

function stateElement(state, rootModelId, activeState, finalState) {
  const namespace = stateNamespace(state.id);
  const depth = modelDepth(namespace);
  const data = {
    id: state.id,
    label: stateDisplayLabel(state, namespace),
    fullLabel: fullStateLabel(state),
    modelLabel: modelLabel(namespace, rootModelId),
    modelNamespace: namespace,
    modelDepth: String(depth),
    active: state.id === activeState ? "yes" : "no",
    terminal: state.id === finalState || state.terminal ? "yes" : "no",
    visited: state.visited ? "yes" : "no"
  };

  if (namespace !== ROOT_MODEL_NAMESPACE) {
    data.parent = modelGroupId(namespace);
  }

  return {
    data,
    classes: [
      "state-node",
      namespace === ROOT_MODEL_NAMESPACE ? "root-state" : "nested-state",
      `model-depth-${Math.min(depth, 3)}`
    ].join(" ")
  };
}

function edgeElement(edge, rootModelId, activeEdgeIds) {
  const sourceNamespace = stateNamespace(edge.from);
  const targetNamespace = stateNamespace(edge.to);
  const boundary = sourceNamespace !== targetNamespace;
  const sourceModel = modelLabel(sourceNamespace, rootModelId);
  const targetModel = modelLabel(targetNamespace, rootModelId);

  return {
    data: {
      id: edge.id,
      source: edge.from,
      target: edge.to,
      sourceLabel: stateReferenceLabel(edge.from, rootModelId),
      targetLabel: stateReferenceLabel(edge.to, rootModelId),
      modelLabel: boundary ? `${sourceModel} -> ${targetModel}` : sourceModel,
      boundary: boundary ? "yes" : "no",
      label: edge.short_label || edge.event || edge.action || edge.id,
      event: edge.event,
      action: edge.action,
      node: edge.node,
      detail: edge.detail,
      current: edge.current ? "yes" : "no",
      path: edge.path ? "yes" : "no",
      active: activeEdgeIds.has(edge.id) ? "yes" : "no"
    },
    classes: boundary ? "model-boundary-edge" : "model-internal-edge"
  };
}

function namespacePrefixes(namespace) {
  if (namespace === ROOT_MODEL_NAMESPACE) {
    return [ROOT_MODEL_NAMESPACE];
  }

  const parts = namespace.split("::");
  const prefixes = [];

  for (let index = 1; index <= parts.length; index += 1) {
    prefixes.push(parts.slice(0, index).join("::"));
  }

  return prefixes;
}

function stateNamespace(stateId) {
  const parts = String(stateId || "").split("::");

  if (parts.length <= 1) {
    return ROOT_MODEL_NAMESPACE;
  }

  return parts.slice(0, -1).join("::");
}

function parentNamespace(namespace) {
  if (namespace === ROOT_MODEL_NAMESPACE) {
    return null;
  }

  const parts = namespace.split("::");

  if (parts.length <= 1) {
    return null;
  }

  return parts.slice(0, -1).join("::");
}

function modelDepth(namespace) {
  return namespace === ROOT_MODEL_NAMESPACE ? 0 : namespace.split("::").length;
}

function modelGroupId(namespace) {
  if (namespace === ROOT_MODEL_NAMESPACE) {
    return "model-group-root";
  }

  return `model-group-${safeGraphId(namespace)}`;
}

function modelLabel(namespace, rootModelId) {
  if (namespace === ROOT_MODEL_NAMESPACE) {
    return formatGraphLabel(rootModelId || "selected model");
  }

  const parts = namespace.split("::");
  return formatGraphLabel(parts[parts.length - 1] || namespace);
}

function stateDisplayLabel(state, namespace) {
  if (namespace === ROOT_MODEL_NAMESPACE) {
    return formatGraphLabel(state.label || state.id || "state");
  }

  return formatGraphLabel(localStateId(state.id));
}

function fullStateLabel(state) {
  return formatGraphLabel(state.label || String(state.id || "state").replaceAll("::", " / "));
}

function stateReferenceLabel(stateId, rootModelId) {
  const namespace = stateNamespace(stateId);
  const localLabel = namespace === ROOT_MODEL_NAMESPACE
    ? formatGraphLabel(stateId)
    : formatGraphLabel(localStateId(stateId));

  return `${modelLabel(namespace, rootModelId)} / ${localLabel}`;
}

function localStateId(stateId) {
  const parts = String(stateId || "").split("::");
  return parts[parts.length - 1] || String(stateId || "state");
}

function safeGraphId(value) {
  return String(value || "model").replace(/[^A-Za-z0-9_.-]+/g, "_");
}

function formatGraphLabel(value) {
  return String(value || "")
    .replace(/^wardwright\//, "")
    .replaceAll("::", " / ")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function graphSpacingFactor(states, transitions) {
  const modelCount = new Set(states.map((state) => stateNamespace(state.id))).size;
  const density = states.length + transitions.length;

  if (modelCount > 2 || density >= 16) {
    return 2.05;
  }

  if (modelCount > 1 || density >= 10) {
    return 1.72;
  }

  return 1.42;
}

function parseJsonAttribute(element, name, fallback) {
  try {
    const value = element.getAttribute(name);
    return value ? JSON.parse(value) : fallback;
  } catch (_error) {
    return fallback;
  }
}

function graphTopologyKey(states, transitions) {
  return JSON.stringify({
    states: states.map((state) => state.id),
    transitions: transitions.map((edge) => [
      edge.from,
      edge.to,
      edge.event,
      edge.action,
      edge.node
    ])
  });
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

if (!customElements.get("wardwright-state-graph")) {
  customElements.define("wardwright-state-graph", WardwrightStateGraph);
}
