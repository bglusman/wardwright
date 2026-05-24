---
layout: default
title: Wardwright
description: A governed model gateway for AI agents.
---

<section class="hero">
  <p class="eyebrow">Governed model gateway</p>
  <h1>Wardwright</h1>
  <p class="lede">
    Agents call normal OpenAI-compatible model names. Wardwright decides what
    those names mean: which provider or local model to use, what policy rules
    apply, when to retry, reroute, block, or rewrite output, and what receipt
    should be recorded afterward.
  </p>
  <div class="actions">
    <a class="button" href="#install">Install</a>
    <a class="button secondary" href="workbench.html">Policy Workbench</a>
    <a class="button secondary" href="wardwright-models.html">Model Middleware</a>
    <a class="button secondary" href="agent-authoring.html">Agent Authoring</a>
    <a class="button secondary" href="agent-adapters.html">Agent Adapters</a>
    <a class="button secondary" href="framework-adapters.html">Framework Adapters</a>
    <a class="button secondary" href="tutorial-news-monitor-agent.html">News Monitor Tutorial</a>
    <a class="button secondary" href="https://github.com/bglusman/wardwright">GitHub</a>
  </div>
</section>

<div class="notice">
  <strong>Status:</strong> Wardwright is early but installable. The
  <code>v0.1.0</code> release line includes the Lustre workbench migration,
  framework-adapter recipes, and local agent-adapter install/probe support.
</div>

Wardwright is for teams and operators who want model behavior to be a reviewed,
testable contract instead of scattered prompt strings, provider IDs, and retry
logic inside every agent.

Today, Wardwright can run as a local or remote service, define Wardwright
models, simulate policy behavior in the `/admin` workbench, record receipts,
and exercise early policy examples such as routing decisions, stream governance,
output checks, retries, and saved simulator test cases. Operator workflows start
from `/admin`; old `/policies` links redirect there. The admin surface currently
supports basic auth, while individual models can be configured for API-key or
open access.

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

For an end-to-end example of why the workbench and framework recipes matter,
see [Build A Lightweight News Monitor](tutorial-news-monitor-agent.html).

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

The installed app includes a workbench at `/admin` for visualizing and
simulating Wardwright models before using them behind real traffic. Choose the
registered Wardwright model being simulated, load a fixture, edit the simulated
request, model output, and retry attempts, then step through the resulting
policy run.

<figure>
  <img src="assets/workbench/registered-model-workbench.png" alt="Wardwright registered-model workbench showing a retry simulation fixture">
  <figcaption>The simulator can replay stream governance, including editable model output, retry attempts, state transitions, and receipt evidence.</figcaption>
</figure>

Fresh installs include starter examples for output contracts, route/model
composition, stream repair and session state, plus tool/workflow control.
Locally authored models use the same workbench path when they expose a supported
projection, and reviewed turns can be saved as reusable simulator test cases.

See [Policy Workbench](workbench.html) for screenshots and examples. External
agents can use `wardwright tools`, `/mcp`, and the protected authoring APIs; see
[Agent Authoring](agent-authoring.html) for the review workflow.
Adapter install and validation commands are covered in
[Agent Adapters](agent-adapters.html).
SDK and application-framework recipes are tracked separately in
[Framework Adapters](framework-adapters.html).

## Provider Credentials

Wardwright can call local Ollama without credentials. OpenAI-compatible provider
targets can reference secrets through `credential_fnox_key` or `credential_env`.
Fnox is a secret lookup path, not Wardwright authentication; keep real provider
credentials on loopback-only instances or behind a trusted auth boundary. See
[Provider Credentials](provider-credentials.html).

## Current Runtime

The active app is a Phoenix service with a Lustre operator workbench. Elixir
owns Phoenix, HTTP/API boundaries, provider calls, storage drivers, PubSub, and
top-level supervision; Gleam owns correctness-heavy policy logic and new
workbench behavior. Runtime state is being evaluated for `gleam_otp` migration
where typed actors can remove invalid states or clarify concurrency ownership.

Current capabilities include:

- OpenAI-compatible `/v1/chat/completions` and `/v1/models` endpoints.
- Wardwright model routing with provider targets and route-DAG delegation.
- Request, route, stream, output, history, alert, and tool policy behavior.
- Protected authoring APIs, MCP, receipts, simulations, and admin status.
- Workspace recipe loading for seeded and local model examples.
