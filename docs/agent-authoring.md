---
layout: default
title: Agent Authoring Guide
description: How external agents should inspect, draft, validate, simulate, and activate Wardwright model middleware.
---

# Agent Authoring Guide

Wardwright ships a local MCP/API surface so an operator can point their
preferred agent at a running Wardwright service and keep the deterministic
policy artifact as the reviewed source of truth. A separate Jido-backed
in-page assistant spike is being evaluated against the same tool registry; it is
convenience UI, not a replacement for review, validation, and activation gates.

The safe workflow is:

1. Inspect the target model and projection.
2. Simulate representative scenarios.
3. Draft a new model or propose a narrow rule change.
4. Validate the artifact and explain every error or review gap.
5. Record or import scenarios that demonstrate intended behavior.
6. Ask for explicit user approval before activating a model.

Do not treat generated policy as authoritative merely because it validates.
Validation catches structural errors and missing review evidence. It does not
prove the user's intent.

## Connect

Start Wardwright and then inspect the tool registry:

```bash
wardwright tools
wardwright tools --json
```

MCP-capable agents should connect to:

```text
http://127.0.0.1:8787/mcp
```

If the service is bound to a different address, replace `8787` with the
configured `WARDWRIGHT_BIND` port. Protected HTTP tools accept loopback callers
by default; non-loopback deployments should set `WARDWRIGHT_ADMIN_TOKEN` and
send it as an admin bearer token.

Agents should not ask users to paste raw provider API keys into model artifacts.
For OpenAI-compatible targets, reference `credential_fnox_key` when fnox is
configured on the host, or `credential_env` for local development and smoke
tests. Fnox is a secret lookup path, not Wardwright authentication: do not assume
a Wardwright service with encrypted provider keys is safe for untrusted callers.
See [Provider Credentials](provider-credentials.html).

## Optional In-Page Assistant Spike

The local workbench may expose an experimental **Authoring Agent Spike** panel
when this spike branch is running. It uses `jido_ai` through a small
`WardwrightWeb.AuthoringAgent` boundary and prompts the model with the same
authoring tool names used by MCP/API clients.

To try it locally with an OpenAI-compatible backend:

```bash
WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
WARDWRIGHT_AUTHORING_AGENT_ROUTE=direct
WARDWRIGHT_AUTHORING_AGENT_BASE_URL=https://opencode.ai/zen/go/v1
WARDWRIGHT_AUTHORING_AGENT_MODEL=qwen3.6-plus
WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE=/path/to/provider-key
WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=16384
WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=120000
```

To dogfood Wardwright itself, route the in-page assistant through the local
OpenAI-compatible Wardwright endpoint instead of a direct provider endpoint:

```sh
WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
WARDWRIGHT_AUTHORING_AGENT_ROUTE=wardwright
WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=16384
WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=120000
```

That makes authoring-agent prompts visible to the same routing, receipts, and
runtime activity surfaces as other local model calls.

OpenCode Go usage is BYOK when the account/key is configured that way; the API
reports that in response usage metadata. The current OpenCode Go chat endpoint
does not require an additional Wardwright request-body flag. Reasoning-heavy
coding models such as Kimi K2.6 can spend many tokens before final content, so
use a larger token budget and timeout or choose a faster final-answer model such
as Qwen for interactive authoring.

The first spike may execute read-only and draft-only tools from chat so it can
inspect projections, simulate scenarios, validate artifacts, and prepare
reviewable model drafts. It does not automatically execute durable write-capable
tools, and it must not claim a model is active unless the activation tool
reports success.

## Inspect Before You Edit

Use `explain_projection` to understand the target model. A projection is the
review shape Wardwright can explain: route choices, state transitions, policy
phases, effects, conflicts, and opaque regions.

Projection is not the source of truth. The deterministic artifact is the source
of truth. Projection tells a user what Wardwright believes the artifact means.

Useful background:

- [Model Middleware](wardwright-models.html)
- [Policy Engine](policy-engine.html)
- [Tool Context Policy](tool-context-policy.html)

## Simulate Before You Activate

Use `simulate_policy` to find the scenarios already associated with a policy
pattern. Simulations should answer practical questions:

- What did the user send?
- What did the upstream model produce?
- What did Wardwright hold, rewrite, retry, block, route, alert, or release?
- Which state or history facts changed now versus on the next request?
- Which receipt evidence would let an operator debug the decision later?

Add or import scenarios when a behavior is important enough to preserve.
Scenario evidence should be small, reviewable, and redacted unless the user
explicitly asks to retain raw content.

## Draft A Wardwright Model

Use `draft_wardwright_model` when creating a new local model. It accepts either a
full artifact or a smaller shape containing:

- `model_id`: unprefixed model id such as `support-router`
- `targets`: provider targets or Wardwright model targets with embedded
  artifacts for route-DAG delegation
- `route`: a model-graph route node such as context-fit, ordered fallback, or
  blended selection
- `governance`: request, route, alert, history, and tool policy rules
- `stream_rules`: streamed response hold, rewrite, retry, or block rules

Drafting returns the normalized artifact, validation, access details, and next
steps. It does not change the current running model.

## Propose A Rule Change

Use `propose_rule_change` for narrow edits to an existing artifact. Supported
operations are:

- `append_rule`
- `replace_rule`
- `remove_rule`

Supported collections are:

- `governance`
- `stream_rules`

The result is always draft-only. It should be shown to the user as a proposed
artifact, validated, and simulated before activation.

## Validate And Explain Gaps

Use `validate_policy_artifact` after every draft or proposed change. Treat the
result this way:

- `invalid`: explain errors and fix them before asking the user to review.
- `needs_review`: explain coverage gaps, opaque regions, provider capability
  gaps, or missing scenarios.
- `valid`: still summarize what changed and which scenarios support it.

Sandboxed engines such as Dune or WASM require scenario evidence before they can
be treated as reviewed because the projection may not explain every branch
statically.

## Try Dune Snippets

Use `list_dune_snippets` when exploring whether an existing behavior would be
clearer as inspectable local code than as several structured fields. The current
registry is a spike and includes small examples for private route gating,
history-count state escalation, and cross-tool sequence review.

Use `evaluate_dune_snippet` before proposing any Dune-backed policy. It accepts
either:

- `snippet_id` plus an `input` map for a built-in registry snippet
- `snippet_id` plus an `input` map for a local workspace snippet saved with
  `save_dune_snippet`
- ad hoc `source` plus an `input` map for code the agent is drafting
- optional `session: {"model_id": "...", "session_id": "...", "key": "default",
  "ttl_ms": 300000, "reset": false}` when deliberately testing stateful Dune
  behavior across evaluations inside a Wardwright runtime session

The snippet receives a JSON-like map named `input` and should return a
policy-shaped map such as:

```elixir
%{
  "action" => "require_review",
  "reason" => "shell_without_recent_browser_context",
  "trace" => [%{"rule" => "browser_before_shell", "result" => false}]
}
```

Malformed return values, restricted APIs, timeout, reduction exhaustion, and
memory exhaustion all return a fail-closed `block` result. Treat that as useful
review evidence, not as permission to activate the snippet.

After an ad hoc snippet has useful evaluation evidence and the user wants to
keep it, call `save_dune_snippet` with an `id`, `source`, and optional title,
phase, description, input shape, example input, and replaced primitive labels.
Saved snippets appear in `list_dune_snippets` with `origin: "workspace"` and
can be referenced from artifacts as:

```json
{
  "engine": "dune",
  "snippet_id": "workspace.high-risk-review"
}
```

They compose through the same normalized action/result ABI as built-ins,
including inside `engine: "hybrid"` policies. Use `delete_dune_snippet` to remove
obsolete workspace snippets. Built-in snippet ids are read-only.

Stateful Dune evaluation is opt-in and should be rare. The stored Dune session
lives in the existing Wardwright runtime GenServer for the selected
`model_id`/`session_id`; `key` lets one runtime session hold separate Dune
sessions, such as one per tool call. This is useful for exploring custom policy
memory, but it also creates a second history mechanism outside Wardwright's
explicit cache and receipt model. Prefer passing explicit history facts in
`input`; use Dune sessions only when the state itself is the policy behavior
under test. Use `reset: true` to clear a Dune session before a new scenario, and
set a short `ttl_ms` so exploratory state does not accumulate indefinitely.

Dune snippets are a local/trusted advanced authoring path. Do not present them
as safe for third-party policy packages or marketplace rules; those still need a
harder boundary such as WASM or an isolated sidecar.

## Activate Only After Review

Use `activate_wardwright_model` only after explicit user approval. Activation
registers or updates one local model available through:

```text
POST /v1/chat/completions
GET /v1/models
```

The activated model can be called with either `model-id` or
`wardwright/model-id`. Other registered models remain callable unless they are
later removed or made internal-only.

## Mental Model

For 0.0.6, a Wardwright model is easiest to explain as four layers:

1. **Targets**: real provider models or other Wardwright models.
2. **Model graph**: route nodes that delegate, choose, or combine targets.
3. **Policy phases**: request, route, stream, output, tool, alert, and receipt
   decisions.
4. **Evidence**: scenarios, receipts, history facts, validation gaps, and
   simulation traces.

The current structured primitives are not as small as the word "primitive"
implies. Many are really predefined policy behaviors. Prefer clear names in
user-facing explanations: route selector, stream rule, request guard, history
counter, tool rule, alert rule, state transition.

## Open Simplification Direction

The primary authoring model is still an open product decision. A promising
follow-up is to make the runtime mental model more code-shaped without losing
reviewability:

- keep the deterministic artifact and normalized action/result ABI
- represent today's larger "primitives" as predefined Dune snippets where
  appropriate
- let agents and advanced users view, edit, fork, and simulate those snippets
- keep WASM or another harder sandbox for externally shared untrusted policy
- require projection, trace, validation, and scenario evidence to stay engine
  neutral

This is not a 0.0.6 requirement. The 0.0.6 requirement is that agents can create
and modify local Wardwright models through a documented, reviewable, reversible
workflow.

The first compatibility conversion is `primitive.request-contains-actions`,
which implements the old `engine: primitive` request-text contains matcher. The
next request-side conversion is `primitive.request-rule-action`, which evaluates
one `request_guard`, `request_transform`, `receipt_annotation`, or `route_gate`
rule with contains/regex matching and returns a normalized action intent. Host
code still applies irreversible effects such as prompt mutation, route
constraints, alert events, and blocks. Prefer proposing a Dune snippet directly
for new policy unless the user is preserving an older artifact shape for
compatibility.

Reference pages:

- [Model Middleware](wardwright-models.html)
- [Policy Workbench](workbench.html)
- [Provider Credentials](provider-credentials.html)
