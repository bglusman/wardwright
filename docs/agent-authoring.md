---
layout: default
title: Agent Authoring Guide
description: How external agents should inspect, draft, validate, simulate, and activate Wardwright synthetic models.
---

# Agent Authoring Guide

Wardwright does not yet ship a first-party in-page authoring agent. It does
ship a local MCP/API surface so an operator can point their preferred agent at a
running Wardwright service and keep the deterministic policy artifact as the
reviewed source of truth.

The safe workflow is:

1. Inspect the current model and projection.
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

## Inspect Before You Edit

Use `explain_projection` to understand the current model. A projection is the
review shape Wardwright can explain: route choices, state transitions, policy
phases, effects, conflicts, and opaque regions.

Projection is not the source of truth. The deterministic artifact is the source
of truth. Projection tells a user what Wardwright believes the artifact means.

Useful background:

- [Synthetic Models](synthetic-models.html)
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

## Draft A Synthetic Model

Use `draft_synthetic_model` when creating a new local model. It accepts either a
full artifact or a smaller shape containing:

- `synthetic_model`: unprefixed model id such as `support-router`
- `targets`: concrete backing model objects such as local and managed models
- `route`: a dispatcher, cascade, or alloy route selector
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

## Activate Only After Review

Use `activate_synthetic_model` only after explicit user approval. Activation
changes the current local model available through:

```text
POST /v1/chat/completions
GET /v1/models
```

The activated model can be called with either `model-id` or
`wardwright/model-id`.

## Mental Model

For 0.0.4, a Wardwright model is easiest to explain as four layers:

1. **Targets**: real provider models or other synthetic model routes.
2. **Route selectors**: dispatchers, cascades, and alloys that choose or combine
   targets.
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

This is not a 0.0.4 requirement. The 0.0.4 requirement is that agents can create
and modify local synthetic models through a documented, reviewable, reversible
workflow.

Related planning:

- [Sandbox Language Evaluation](sandbox-language-evaluation.html)
- [Feature Spikes](feature-spikes.html)
- [Architecture Ratchets](architecture-ratchets.html)
