---
layout: default
title: Wardwright
description: LLM model middleware, governance, and receipts for agentic workflows.
---

<section class="hero">
  <p class="eyebrow">LLM model middleware</p>
  <h1>Wardwright</h1>
  <p class="lede">
    Agents call a stable OpenAI-compatible model name. Wardwright owns the
    model graph, policy checks, provider routing, stream retries and rewrites,
    tool controls, simulations, and receipts behind that name.
  </p>
  <div class="actions">
    <a class="button" href="#install">Install</a>
    <a class="button secondary" href="workbench.html">Policy Workbench</a>
    <a class="button secondary" href="wardwright-models.html">Model Middleware</a>
    <a class="button secondary" href="agent-authoring.html">Agent Authoring</a>
    <a class="button secondary" href="https://github.com/bglusman/wardwright">GitHub</a>
  </div>
</section>

<div class="notice">
  <strong>Status:</strong> Wardwright is early but installable. The prepared
  <code>v0.0.5</code> release publishes native macOS and Linux artifacts, a
  Homebrew formula, an OpenAI-compatible gateway, and a policy workbench with
  simulation playback and starter model examples.
</div>

## Install

Wardwright publishes native binaries through GitHub Releases and Homebrew.

### macOS Homebrew

```bash
brew tap bglusman/tap
brew install wardwright
wardwright admin
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/bglusman/wardwright/main/scripts/install.sh | sh
WARDWRIGHT_SECRET_KEY_BASE="$(openssl rand -base64 64)" \
WARDWRIGHT_BIND=127.0.0.1:8787 \
~/.local/bin/wardwright serve
```

Set `WARDWRIGHT_ADMIN_TOKEN` before exposing Wardwright beyond loopback. See
[Packaging](packaging.html) for manual archive install steps and service
details.

## What Wardwright Adds

Wardwright is a narrow control point between agent code and concrete model
providers.

<div class="grid">
  <div class="card">
    <h3>Stable Model IDs</h3>
    <p>Expose names such as <code>coding-balanced</code> while Wardwright owns
    the model graph and policy behind them.</p>
  </div>
  <div class="card">
    <h3>Model Composition</h3>
    <p>Route to provider targets, delegate through other Wardwright models, and
    keep context-window and fallback choices explicit.</p>
  </div>
  <div class="card">
    <h3>Policy And Repair</h3>
    <p>Apply request, route, stream, output, history, alert, and tool controls,
    including bounded stream retries and rewrites.</p>
  </div>
  <div class="card">
    <h3>Receipts</h3>
    <p>Record caller provenance, selected routes, provider attempts, policy
    actions, and final status for each run.</p>
  </div>
</div>

## Policy Workbench

The installed app includes a workbench at `/policies` for visualizing and
simulating Wardwright models before using them behind real traffic. Load an
example or local model, edit the simulated request, model output, and relevant
history, then step through the resulting policy run.

<figure>
  <img src="assets/workbench/stream-retry-simulator.png" alt="Wardwright policy workbench showing a stream retry simulation">
  <figcaption>The simulator can replay stream governance, including the raw model stream, held/released output, retry attempts, and receipt evidence.</figcaption>
</figure>

Fresh installs include starter examples for output contracts, route/model
composition, stream repair and session state, plus tool/workflow control.
Locally authored models use the same workbench path when they expose a supported
projection.

See [Policy Workbench](workbench.html) for screenshots and examples. External
agents can use `wardwright tools`, `/mcp`, and the protected authoring APIs; see
[Agent Authoring](agent-authoring.html) for the review workflow.

## Provider Credentials

Wardwright can call local Ollama without credentials. OpenAI-compatible provider
targets can reference secrets through `credential_fnox_key` or `credential_env`.
Fnox is a secret lookup path, not Wardwright authentication; keep real provider
credentials on loopback-only instances or behind a trusted auth boundary. See
[Provider Credentials](provider-credentials.html).

## Current Runtime

The active app is a Phoenix/LiveView service. Elixir owns runtime plumbing,
provider calls, HTTP/API boundaries, receipts, and the UI. Gleam is used for
correctness-heavy pure policy logic where the boundary is stable.

Current capabilities include:

- OpenAI-compatible `/v1/chat/completions` and `/v1/models` endpoints.
- Wardwright model routing with provider targets and route-DAG delegation.
- Request, route, stream, output, history, alert, and tool policy behavior.
- Protected authoring APIs, MCP, receipts, simulations, and admin status.
- Workspace recipe loading for seeded and local model examples.
