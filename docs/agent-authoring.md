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

Treat `wardwright tools` as the cold-start entrypoint for an agent with no
other Wardwright context. The text form should tell a human or agent how to
connect, which operations are safe or write-capable, and where to read fuller
examples. The JSON form should expose the same tool names, paths, argument
expectations where available, safety notes, and documentation links in a shape
that an agent can use without scraping the UI.

MCP-capable agents should connect to:

```text
http://127.0.0.1:8787/mcp
```

If the service is bound to a different address, replace `8787` with the
configured `WARDWRIGHT_BIND` port. Protected HTTP tools accept loopback callers
by default; non-loopback deployments should set `WARDWRIGHT_ADMIN_TOKEN` and
send it as an admin bearer token.

MCP, CLI, and UI are expected to be symmetrical control surfaces over the same
authoring and debugging capabilities. The UI may be more visual, MCP may be
more structured, and CLI help may be more compact, but none should require
unstated project knowledge. If a workflow can only be completed in one surface,
that is either a deliberate product decision that needs documentation or a
capability gap to file from the run.

Agents should not ask users to paste raw provider API keys into model artifacts.
For OpenAI-compatible targets, reference `credential_fnox_key` when fnox is
configured on the host, or `credential_env` for local development and smoke
tests. Fnox is a secret lookup path, not Wardwright authentication: do not assume
a Wardwright service with encrypted provider keys is safe for untrusted callers.
See [Provider Credentials](provider-credentials.html).

## Optional Tidewave Runtime MCP

Developers working inside the repository can also enable Tidewave for Phoenix
in development. Tidewave is mounted only when the dev dependency is loaded and
exposes runtime-oriented tools at:

```text
http://127.0.0.1:8787/tidewave/mcp
```

For Codex CLI, register it with:

```bash
codex mcp add tidewave --url http://127.0.0.1:8787/tidewave/mcp
```

Use Tidewave for developer runtime inspection: evaluating code inside the
running Phoenix app, reading logs, finding package docs, and inspecting runtime
state. Do not treat Tidewave as an end-user policy-authoring tool. It is more
powerful than the Wardwright MCP surface and should remain local/developer
scoped unless a human explicitly chooses otherwise.

## Optional In-Page Assistant Spike

The local workbench may expose an experimental **Authoring Agent** panel when it
is enabled. It uses `jido_ai` through a small `WardwrightWeb.AuthoringAgent`
boundary and prompts the model with the same authoring tool names used by
MCP/API clients.

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

To dogfood Wardwright itself, route the in-page assistant through a specific
local Wardwright model instead of a direct provider endpoint. This mode is
intentionally stricter than direct-provider mode: the selected local Wardwright
model must include a `structured_output.schemas.authoring_tool_plan_v1` schema
so the assistant's `{answer, tool_calls, next_steps}` plan is validated by
Wardwright before any draft/read tool executes.

```sh
WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
WARDWRIGHT_AUTHORING_AGENT_ROUTE=wardwright
WARDWRIGHT_AUTHORING_AGENT_MODEL=local-fast-draft
WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY_FILE=/path/to/local/model-key
WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=16384
WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=120000
```

For packaged or service installs, put the same settings in a local env file
instead of relying on the shell that happened to launch the server. Wardwright
checks `~/.config/wardwright/authoring_agent.env`,
`/opt/homebrew/etc/wardwright/authoring_agent.env`, and
`/usr/local/etc/wardwright/authoring_agent.env`; set
`WARDWRIGHT_AUTHORING_AGENT_CONFIG_FILE` to override that path.

That makes authoring-agent prompts visible to the same routing, receipts, and
runtime activity surfaces as other local model calls, and it gives Wardwright a
dogfood path for enforcing correct authoring tool-call JSON. Omit the model key
only when the selected Wardwright model allows unkeyed access. If the selected
model is callable but does not expose the `authoring_tool_plan_v1` structured
schema, the assistant remains unconfigured rather than falling back to prompt
discipline.

OpenCode Go usage is BYOK when the account/key is configured that way; the API
reports that in response usage metadata. The current OpenCode Go chat endpoint
does not require an additional Wardwright request-body flag. Reasoning-heavy
coding models such as Kimi K2.6 can spend many tokens before final content, so
use a larger token budget and timeout or choose a faster final-answer model such
as Qwen for interactive authoring.

The first spike may execute read-only and draft-only tools from chat so it can
inspect projections, simulate scenarios, validate artifacts, and prepare
reviewable model drafts. Durable writes still need explicit review boundaries:
the assistant should not activate a model, delete a saved case, or persist a
snippet unless the user approved that operation. It must not claim a model is
active unless the activation tool reports success.

For strong models such as Kimi K2.6, prompt quality still matters. A useful
authoring run should normally include this loop:

1. Inspect the current projection when the request depends on existing behavior.
2. Draft or propose the smallest artifact change that could satisfy the request.
3. Validate the artifact and report warnings, coverage gaps, and limits.
4. Simulate at least one matching case and one non-matching control case when
   the available simulator can express them.
5. Explain whether the simulation actually exercised the changed behavior.

Good smoke tasks for evaluating the in-page assistant are:

- "Make a model that adds a cow reminder when the user's request contains moo,
  but does not change ordinary requests."
- "Rewrite streamed output matching the regex `\bmoo+\b` to a short cow marker,
  and show me a control case that does not rewrite."
- "Route private helpdesk requests to the local model but leave public requests
  on the normal route."
- "Prevent shell tools after two consecutive failures unless a browser-search
  tool was used in the last five tool calls."
- "Require structured JSON output with one of two allowed shapes and retry once
  when neither shape validates."

If the assistant cannot validate or simulate the behavior it drafted, that is a
finding, not a success. It should say which missing simulator/API capability
blocked evidence and leave the draft inactive.

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

## Record Scenarios As Regression Evidence

Use `record_scenario` when a simulated turn should become reusable evidence. A
scenario should include:

- `title` and `expected_behavior` in user-facing language
- `model_id` and `artifact_hash` when known
- a `turn` with raw user input, raw model output, optional retry-attempt outputs,
  and any history facts the policy reads
- a trace or receipt preview that explains why the saved case matters

Use `delete_scenario` to remove a stale local case, `import_receipt_scenario` to
turn a real receipt into pinned replay evidence, `replay_receipt_policy` to
inspect the recorded policy and route decisions without calling a provider,
`export_regression_pack` to share or review pinned scenarios, and
`apply_scenario_retention` to prune old unpinned exploratory cases.

## Replay Receipts Before Changing Policy

Use `replay_receipt_policy` when a stored receipt should be inspected as
metadata-only VCR evidence before a policy edit. Replay returns the recorded
request metadata, policy actions/events, route decision, final status, and an
explicit `provider_called: false` marker. It does not regenerate provider output
or expose raw prompts and completions.

The workbench can save the same shape directly from the editable simulator. That
is the preferred path when a human is actively reviewing the example because it
keeps the visible user/model pair, history context, selected simulation target,
and trace together.

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

For the current release line, a Wardwright model is easiest to
explain as four layers:

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

This is not a release requirement. The current requirement is that
agents can create and modify local Wardwright models through a documented,
reviewable, reversible workflow.

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
