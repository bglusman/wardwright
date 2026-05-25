defmodule WardwrightWeb.UXExplorationController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  @issue_url "https://github.com/bglusman/wardwright/issues/75"

  @concepts [
    %{
      id: "model-config-cleanup",
      label: "Current Model Config Cleanup",
      letter: "A",
      summary: "Conservative IA pass for the existing Models & access page.",
      tag: "near-term",
      vote_url: @issue_url <> "#issuecomment-4534975919"
    },
    %{
      id: "capability-command-center",
      label: "Capability Command Center",
      letter: "B",
      summary: "Model capability and advertisement clarity.",
      tag: "capability-first",
      vote_url: @issue_url <> "#issuecomment-4534975938"
    },
    %{
      id: "route-topology-map",
      label: "Route Topology Map",
      letter: "C",
      summary: "Graph-first explanation of composed model behavior.",
      tag: "graph-first",
      vote_url: @issue_url <> "#issuecomment-4534975930"
    },
    %{
      id: "guided-change-review",
      label: "Guided Change Review",
      letter: "D",
      summary: "Safer review flow for risky model changes.",
      tag: "workflow-first",
      vote_url: @issue_url <> "#issuecomment-4534975928"
    },
    %{
      id: "holistic-control-room",
      label: "Holistic Control Room",
      letter: "E",
      summary: "Whole-product workspace for models, policy, evidence, integrations, and release readiness.",
      tag: "north star",
      vote_url: @issue_url <> "#issuecomment-4534975916"
    }
  ]

  def index(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/html")
    |> html(page("Wardwright UX Exploration", index_body()))
  end

  def show(conn, %{"concept" => concept_id}) do
    case Enum.find(@concepts, &(&1.id == concept_id)) do
      nil ->
        conn
        |> put_status(404)
        |> put_resp_content_type("text/html")
        |> html(page("Wardwright UX Exploration", not_found_body(concept_id)))

      concept ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("text/html")
        |> html(page("Wardwright UX Exploration - #{concept.label}", concept_body(concept)))
    end
  end

  defp index_body do
    """
    <section class="hero">
      <div>
        <p class="eyebrow">Exploratory app route</p>
        <h1>Try alternate Wardwright admin directions</h1>
        <p>These pages are implemented as protected Wardwright routes so reviewers can experience the interaction model, compare alternatives, and vote in GitHub. They are not the production admin shell.</p>
      </div>
      <div class="actions">
        <a class="button primary" href="/admin/ux-exploration/holistic-control-room">Open leading concept</a>
        <a class="button" href="#{@issue_url}">Vote in issue #75</a>
        <a class="button quiet" href="/admin">Back to current admin</a>
      </div>
    </section>

    <section class="metrics">
      <article><span>Concepts</span><strong>5</strong><small>real app routes</small></article>
      <article><span>Current production UI</span><strong>/admin</strong><small>unchanged</small></article>
      <article><span>Feedback</span><strong>#75</strong><small>GitHub reactions</small></article>
    </section>

    <section class="concept-grid">
      #{Enum.map_join(@concepts, &concept_card/1)}
    </section>
    """
  end

  defp concept_card(concept) do
    """
    <article class="concept-card">
      <div class="concept-title">
        <span class="letter">#{concept.letter}</span>
        <div>
          <h2>#{h(concept.label)}</h2>
          <p>#{h(concept.summary)}</p>
        </div>
        <span class="badge">#{h(concept.tag)}</span>
      </div>
      <div class="mini-preview #{concept.id}">
        #{mini_preview(concept.id)}
      </div>
      <div class="actions">
        <a class="button primary" href="/admin/ux-exploration/#{concept.id}">Try concept</a>
        <a class="button" href="#{concept.vote_url}">Vote for #{concept.letter}</a>
      </div>
    </article>
    """
  end

  defp concept_body(concept) do
    """
    <section class="concept-shell">
      <aside class="concept-nav">
        <a class="brand" href="/admin/ux-exploration"><span class="mark">W</span><strong>UX Exploration</strong></a>
        #{Enum.map_join(@concepts, &concept_nav_item(&1, concept.id))}
        <a class="admin-link" href="/admin">Current admin</a>
      </aside>
      <main class="concept-workspace">
        <header class="concept-header">
          <div>
            <p class="eyebrow">Concept #{concept.letter} / #{h(concept.tag)}</p>
            <h1>#{h(concept.label)}</h1>
            <p>#{h(concept.summary)} This is an app-native prototype route with realistic controls and labels, not a screenshot.</p>
          </div>
          <div class="actions">
            <a class="button primary" href="#{concept.vote_url}">Vote for #{concept.letter}</a>
            <a class="button" href="/admin/ux-exploration">All concepts</a>
          </div>
        </header>
        #{render_concept(concept.id)}
      </main>
    </section>
    """
  end

  defp concept_nav_item(concept, current_id) do
    active = if concept.id == current_id, do: " active", else: ""

    """
    <a class="nav-item#{active}" href="/admin/ux-exploration/#{concept.id}">
      <span class="letter small">#{concept.letter}</span>
      <span>#{h(concept.label)}</span>
    </a>
    """
  end

  defp render_concept("model-config-cleanup") do
    model = selected_model()
    {tool_count, conditional_tools} = tool_counts(model.id)

    """
    <section class="split">
      <article class="panel hero-panel">
        <h2>#{h(model.id)}</h2>
        <p>#{h(model.description)}</p>
        <div class="metric-row">
          <span><strong>Access</strong>#{h(model.access)}</span>
          <span><strong>Replay</strong>#{h(model.vcr)}</span>
          <span><strong>Tools</strong>#{tool_count}</span>
          <span><strong>Conditional</strong>#{conditional_tools}</span>
        </div>
      </article>
      <article class="panel decision">
        <h2>Operating decision</h2>
        <p>Keep the top of Models & access focused on what the model promises, then move server tools, access, recording, keys, and lifecycle into task tabs.</p>
        <a class="button primary" href="/admin?view=model_access&amp;model=#{u(model.id)}">Open current model config</a>
      </article>
    </section>
    <section class="tabbed panel">
      <nav class="tabs"><span class="active">Server tools</span><span>Access</span><span>Recording</span><span>Keys</span><span>Lifecycle</span></nav>
      <div class="tool-list">
        #{tool_cards(model.id)}
      </div>
    </section>
    """
  end

  defp render_concept("capability-command-center") do
    model = selected_model()
    {tool_count, conditional_tools} = tool_counts(model.id)

    """
    <section class="command-center">
      <article class="panel capability-hero">
        <p class="eyebrow">Selected model</p>
        <h2>#{h(model.id)}</h2>
        <p>Lead with whether agents can safely rely on the model contract.</p>
        <div class="actions"><a class="button primary" href="/admin/ux-exploration/guided-change-review">Review advertisement</a><a class="button" href="/admin?model=#{u(model.id)}">Run model lab</a></div>
      </article>
      <article class="score"><span>Stable tools</span><strong>#{max(tool_count - conditional_tools, 0)}</strong></article>
      <article class="score warn"><span>Conditional tools</span><strong>#{conditional_tools}</strong></article>
      <article class="score"><span>Route type</span><strong>#{h(model.route_type)}</strong></article>
    </section>
    <section class="panel">
      <h2>Agent-visible capability contract</h2>
      <p>Show the promise first, then reveal target differences and implementation detail.</p>
      <div class="tool-list">#{tool_cards(model.id)}</div>
    </section>
    """
  end

  defp render_concept("route-topology-map") do
    model = selected_model()
    targets = provider_targets()

    """
    <section class="topology">
      <div class="map-panel">
        <div class="node model"><h3>Stable model</h3><p>#{h(model.id)}</p><span>public contract</span></div>
        <div class="node route"><h3>Route graph</h3><p>#{h(model.route_type)}</p><span>selector</span></div>
        <div class="node policy"><h3>Policy stack</h3><p>stream, structured output, receipts</p><span>governed</span></div>
        #{Enum.map_join(targets, &target_node/1)}
        <div class="node evidence"><h3>Evidence</h3><p>receipts, replay, smoke checks</p><span>auditable</span></div>
      </div>
      <aside class="panel inspector">
        <h2>Inspector</h2>
        <p>Selecting a node should explain what is promised, what is conditional, and what evidence supports it.</p>
        <div class="facts">
          <span><strong>Targets</strong>#{length(targets)}</span>
          <span><strong>Access</strong>#{h(model.access)}</span>
          <span><strong>Replay</strong>#{h(model.vcr)}</span>
        </div>
      </aside>
    </section>
    """
  end

  defp render_concept("guided-change-review") do
    model = selected_model()

    """
    <section class="review-flow">
      #{review_step("1", "What can agents do?", "Compare the current model contract against route and tool support.", "current model: #{h(model.id)}")}
      #{review_step("2", "Who can call it?", "Review public access, API keys, and caller provenance requirements.", h(model.access))}
      #{review_step("3", "What gets recorded?", "Confirm receipt and replay capture before enabling risky behavior.", h(model.vcr))}
      #{review_step("4", "Prove it works", "Run scenario, replay, browser smoke, and package smoke evidence before apply.", "evidence required")}
      #{review_step("5", "Apply change", "Save only after Wardwright can show what changed and why it is supported.", "blocked until proof")}
    </section>
    """
  end

  defp render_concept("holistic-control-room") do
    models = Wardwright.model_summaries()

    """
    <section class="control-room">
      <article class="panel wide">
        <h2>Overview</h2>
        <p>Start with whether the gateway is safe to use, what changed recently, and what evidence supports release claims.</p>
        <div class="metric-row">
          <span><strong>Gateway</strong>OK</span>
          <span><strong>Models</strong>#{length(models)}</span>
          <span><strong>Evidence</strong>browser + package smoke</span>
          <span><strong>Release</strong>candidate</span>
        </div>
      </article>
      <article class="panel"><h2>Models</h2><p>Stable contracts, route graph, capability catalog, access, and recording.</p><a class="button" href="/admin/ux-exploration/route-topology-map">Open route map</a></article>
      <article class="panel"><h2>Policy Lab</h2><p>Author, simulate, compare, and activate only with evidence.</p><a class="button" href="/admin">Open current lab</a></article>
      <article class="panel"><h2>Evidence</h2><p>Receipts, replay, adapter smoke, package smoke, and known limits.</p><a class="button" href="/admin?view=control_debugger">Open replay</a></article>
      <article class="panel"><h2>Integrations</h2><p>Framework SDK recipes stay separate from local coding-agent adapters.</p><a class="button" href="#{@issue_url}">Discuss priorities</a></article>
    </section>
    """
  end

  defp render_concept(_id), do: ""

  defp review_step(number, title, body, status) do
    """
    <article class="step">
      <span class="step-number">#{number}</span>
      <div><h2>#{title}</h2><p>#{body}</p></div>
      <span class="badge">#{status}</span>
    </article>
    """
  end

  defp target_node(target) do
    model = target["model"] || "target"
    kind = target["kind"] || target["provider"] || "provider"

    """
    <div class="node target"><h3>#{h(model)}</h3><p>#{h(kind)}</p><span>raw target</span></div>
    """
  end

  defp tool_cards(model_id) do
    {tools, _targets, _mediation, _advertisement} = WardwrightWeb.LustreModelAccessData.server_tool_summary(model_id)

    case tools do
      [] ->
        ~s(<article class="tool-card"><h3>No configured server tools</h3><p>This model currently exposes no Wardwright-hosted server tools.</p></article>)

      tools ->
        Enum.map_join(tools, fn {name, engine, source, state, visibility, limits, parameter_keys, input_keys} ->
          """
          <article class="tool-card">
            <div><h3>#{h(name)}</h3><p>#{h(engine)} / #{h(source)} / #{h(visibility)}</p></div>
            <span class="badge">#{h(state)}</span>
            <small>#{h(limits)} / params #{h(parameter_keys)} / input #{h(input_keys)}</small>
          </article>
          """
        end)
    end
  end

  defp mini_preview("model-config-cleanup") do
    ~s(<div class="wire blocks"><span></span><span></span><span></span><strong></strong></div>)
  end

  defp mini_preview("capability-command-center") do
    ~s(<div class="wire metrics"><strong></strong><span></span><span></span><span></span></div>)
  end

  defp mini_preview("route-topology-map") do
    ~s(<div class="wire graph"><span></span><span></span><span></span><span></span></div>)
  end

  defp mini_preview("guided-change-review") do
    ~s(<div class="wire steps"><span></span><span></span><span></span><span></span></div>)
  end

  defp mini_preview("holistic-control-room") do
    ~s(<div class="wire room"><strong></strong><span></span><span></span><span></span><span></span></div>)
  end

  defp selected_model do
    summary = Wardwright.model_summary()

    %{
      access: if(summary["requires_api_key"], do: "Keyed", else: "Public"),
      description: summary["description"] || "",
      id: summary["id"] || Wardwright.model_id(),
      route_type: summary["route_type"] || "dispatcher",
      vcr: get_in(summary, ["vcr", "mode"]) || "metadata_only"
    }
  end

  defp tool_counts(model_id) do
    {_tools, _targets, _mediation, {_mode, guaranteed, conditional}} =
      WardwrightWeb.LustreModelAccessData.server_tool_summary(model_id)

    {guaranteed + conditional, conditional}
  end

  defp provider_targets do
    Wardwright.current_config()
    |> Wardwright.provider_targets()
    |> Enum.take(4)
  end

  defp not_found_body(concept_id) do
    """
    <section class="hero">
      <div><p class="eyebrow">Not found</p><h1>Unknown UX concept</h1><p>There is no concept route for #{h(concept_id)}.</p></div>
      <a class="button primary" href="/admin/ux-exploration">Open UX exploration</a>
    </section>
    """
  end

  defp page(title, body) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h(title)}</title>
        <style>#{styles()}</style>
      </head>
      <body>
        #{body}
      </body>
    </html>
    """
  end

  defp styles do
    """
    :root {
      --background: #f4f6f8;
      --foreground: #18202a;
      --panel: #ffffff;
      --primary: #16605a;
      --primary-dark: #0e4843;
      --secondary: #f0b04f;
      --muted: #e7eaee;
      --muted-foreground: #66727f;
      --accent: #dcefed;
      --border: #d7dde3;
      --warn: #fff1c4;
      --danger: #f5d4d0;
      --blue: #245a82;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      overflow-x: clip;
      background: var(--background);
      color: var(--foreground);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      letter-spacing: 0;
    }
    body > .hero,
    body > .metrics,
    body > .concept-grid {
      width: min(1180px, calc(100vw - 32px));
      margin-inline: auto;
    }
    .hero {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 20px;
      align-items: end;
      padding: 28px 0 18px;
    }
    .eyebrow {
      color: var(--primary);
      font-size: 12px;
      font-weight: 850;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    h1, h2, h3, p { margin: 0; }
    h1 { font-size: clamp(30px, 4vw, 48px); line-height: 1.05; }
    h2 { font-size: 20px; line-height: 1.15; }
    h3 { font-size: 15px; line-height: 1.2; }
    p, small { color: var(--muted-foreground); font-size: 13px; line-height: 1.45; }
    .hero p { max-width: 800px; margin-top: 8px; }
    .actions { display: flex; flex-wrap: wrap; gap: 9px; align-items: center; min-width: 0; }
    .button {
      display: inline-flex;
      min-height: 38px;
      align-items: center;
      justify-content: center;
      padding: 8px 12px;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: #fff;
      color: var(--foreground);
      font-size: 13px;
      font-weight: 800;
      text-decoration: none;
    }
    .button.primary { border-color: var(--primary); background: var(--primary); color: #fff; }
    .button.quiet { background: transparent; }
    .metrics, .concept-grid { display: grid; gap: 14px; }
    .metrics { grid-template-columns: repeat(3, minmax(0, 1fr)); margin-bottom: 14px; }
    .metrics article, .concept-card, .panel, .step {
      min-width: 0;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: 0 1px 0 rgba(24, 32, 42, 0.04);
    }
    .metrics article { display: grid; gap: 5px; padding: 14px; }
    .metrics span, .metrics small { color: var(--muted-foreground); font-size: 12px; font-weight: 800; }
    .metrics strong { font-size: 28px; }
    .concept-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); padding-bottom: 28px; }
    .concept-card { display: grid; gap: 12px; padding: 14px; }
    .concept-title { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: 10px; align-items: start; }
    .letter, .mark, .step-number {
      display: grid;
      place-items: center;
      width: 34px;
      height: 34px;
      border-radius: 999px;
      background: var(--blue);
      color: #fff;
      font-weight: 900;
    }
    .letter.small { width: 24px; height: 24px; font-size: 12px; }
    .badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: fit-content;
      min-height: 24px;
      padding: 3px 8px;
      border: 1px solid var(--border);
      border-radius: 999px;
      background: var(--accent);
      color: var(--foreground);
      font-size: 11px;
      font-weight: 850;
    }
    .mini-preview {
      min-height: 170px;
      overflow: hidden;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: #fbfcfd;
      padding: 14px;
    }
    .wire { height: 140px; display: grid; gap: 10px; }
    .wire span, .wire strong {
      display: block;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--muted);
    }
    .wire.blocks { grid-template-columns: 1fr 2fr 1fr; }
    .wire.metrics { grid-template-columns: repeat(3, 1fr); grid-template-rows: 1fr 1fr; }
    .wire.metrics strong { grid-column: 1 / -1; background: var(--warn); }
    .wire.graph { position: relative; display: block; }
    .wire.graph span { position: absolute; width: 34%; height: 34px; }
    .wire.graph span:nth-child(1) { left: 2%; top: 50px; }
    .wire.graph span:nth-child(2) { left: 32%; top: 18px; }
    .wire.graph span:nth-child(3) { left: 32%; top: 92px; }
    .wire.graph span:nth-child(4) { right: 2%; top: 52px; background: var(--warn); }
    .wire.steps { grid-template-rows: repeat(4, 1fr); }
    .wire.room { grid-template-columns: repeat(4, 1fr); grid-template-rows: 1fr 1fr; }
    .wire.room strong { grid-column: 1 / -1; background: var(--accent); }
    .concept-shell { min-width: 0; max-width: 100%; min-height: 100vh; overflow-x: clip; display: grid; grid-template-columns: 250px minmax(0, 1fr); }
    .concept-nav { min-width: 0; display: grid; align-content: start; gap: 8px; padding: 18px; border-right: 1px solid var(--border); background: #fbfcfd; }
    .brand, .nav-item, .admin-link { color: inherit; text-decoration: none; }
    .brand { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }
    .nav-item { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 8px; align-items: center; padding: 9px; border: 1px solid transparent; border-radius: 8px; font-size: 13px; font-weight: 800; }
    .nav-item.active, .nav-item:hover { border-color: var(--border); background: var(--accent); }
    .admin-link { margin-top: 12px; color: var(--muted-foreground); font-size: 13px; font-weight: 800; }
    .concept-workspace { min-width: 0; display: grid; align-content: start; gap: 16px; padding: 22px; }
    .concept-header { min-width: 0; display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 16px; align-items: end; }
    .split, .topology, .command-center, .control-room { min-width: 0; display: grid; gap: 14px; }
    .split { grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr); }
    .panel, .step { padding: 14px; }
    .hero-panel, .capability-hero { background: #fffaf0; }
    .metric-row, .facts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin-top: 12px; }
    .metric-row span, .facts span { display: grid; gap: 4px; padding: 10px; border: 1px solid var(--border); border-radius: 8px; background: #fff; color: var(--muted-foreground); font-size: 12px; font-weight: 750; }
    .metric-row strong, .facts strong { color: var(--foreground); font-size: 13px; }
    .tabs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; }
    .tabs span { padding: 8px 10px; border: 1px solid var(--border); border-radius: 999px; font-size: 12px; font-weight: 850; }
    .tabs .active { background: var(--primary); color: #fff; }
    .tool-list { display: grid; gap: 10px; }
    .tool-card { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 8px; align-items: center; padding: 10px; border: 1px solid var(--border); border-radius: 8px; background: #fff; }
    .tool-card small { grid-column: 1 / -1; }
    .command-center { grid-template-columns: minmax(0, 1fr) repeat(3, minmax(140px, 0.22fr)); }
    .score { display: grid; align-content: center; gap: 8px; padding: 14px; border: 1px solid var(--border); border-radius: 8px; background: #fff; }
    .score.warn { background: var(--warn); }
    .score span { color: var(--muted-foreground); font-size: 12px; font-weight: 850; }
    .score strong { font-size: 32px; }
    .topology { grid-template-columns: minmax(0, 1fr) 340px; }
    .map-panel { min-height: 540px; position: relative; border: 1px solid var(--border); border-radius: 8px; background: linear-gradient(var(--muted) 1px, transparent 1px), linear-gradient(90deg, var(--muted) 1px, transparent 1px), #fff; background-size: 28px 28px; }
    .node { position: absolute; width: 190px; display: grid; gap: 5px; padding: 10px; border: 1px solid var(--border); border-radius: 8px; background: #fff; }
    .node span { color: var(--primary); font-size: 11px; font-weight: 850; }
    .node.model { left: 40px; top: 230px; border-color: var(--primary); }
    .node.route { left: 280px; top: 135px; }
    .node.policy { left: 280px; top: 325px; }
    .node.target:nth-of-type(4) { left: 520px; top: 80px; }
    .node.target:nth-of-type(5) { left: 520px; top: 220px; }
    .node.target:nth-of-type(6) { left: 520px; top: 360px; }
    .node.evidence { right: 36px; top: 230px; background: var(--accent); }
    .review-flow { display: grid; gap: 12px; }
    .step { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: 12px; align-items: center; }
    .control-room { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .control-room .wide { grid-column: 1 / -1; }
    @media (max-width: 900px) {
      .hero, .concept-header, .split, .topology, .command-center, .control-room, .metrics, .concept-grid, .concept-shell { grid-template-columns: 1fr; }
      .concept-nav { border-right: 0; border-bottom: 1px solid var(--border); }
      .metric-row, .facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .map-panel { display: grid; position: static; gap: 10px; min-height: 0; padding: 12px; }
      .node { position: static; width: auto; }
      .step { grid-template-columns: auto minmax(0, 1fr); }
      .step .badge { grid-column: 2; }
    }
    """
  end

  defp h(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp u(value), do: URI.encode_www_form(to_string(value))
end
