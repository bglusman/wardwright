---
layout: default
title: Model Middleware And Composition
description: Wardwright model endpoints, route DAGs, and model-middleware composition.
---

# Model Middleware And Composition

Wardwright is LLM middleware: callers use an OpenAI-compatible model ID, while
Wardwright owns the model graph, policies, receipts, and simulation surface
behind that ID. A Wardwright model can be simple, such as one local Ollama
provider with no policy, or complex, such as a context-aware route graph with
stream repair, tool policy, history checks, and nested Wardwright model targets.

The product concept is a **Wardwright model**: a named model endpoint whose
behavior is defined by middleware rather than by a single upstream provider.

Two outside ideas define the shape of this work. XBOW's "model alloy" writeups
show that alternating multiple LLMs inside one agent context can outperform a
single-model monoculture on agentic search tasks. oh-my-pi's Time Traveling
Streamed Rules show that rules can sit outside the prompt until model output
actually triggers them, then abort and retry with a targeted reminder.

References:

- [XBOW: Agents Built From Alloys](https://xbow.com/blog/alloy-agents/)
- [oh-my-pi Time Traveling Streamed Rules](https://github.com/can1357/oh-my-pi#-time-traveling-streamed-rules-ttsr)

## Current Composition Model

The current implementation supports route-DAG composition. A route can select a
concrete provider target or delegate to another embedded Wardwright model
artifact. Delegation resolves recursively until Wardwright selects a concrete
provider target. Cycles fail validation before activation, depth is capped, and
receipts include `decision.route_lineage` so users and agents can see each model
hop.

This is intentionally **route composition**, not full middleware wrapping. The
nested model contributes route selection and lineage. Its request, stream,
output, and tool policies do not yet wrap the outer policy execution. Full
middleware layering is a roadmap item because it needs explicit phase ordering:
outer request policy, inner request policy, provider attempt, inner output
policy, outer output policy, retries, and receipt nesting all need a clear
visual and behavioral contract.

## Simple Provider Target

A minimal Wardwright model can point directly at one provider target.

```json
{
  "model_definition_version": 1,
  "model_id": "local-helper",
  "version": "2026-05-18",
  "targets": [
    {"model": "ollama/qwen2.5-coder", "context_window": 32768}
  ],
  "route_root": "context-fit",
  "dispatchers": [
    {"id": "context-fit", "models": ["ollama/qwen2.5-coder"]}
  ]
}
```

`model_definition_version` is the schema version for the model definition
itself, not the operator-facing model `version`. Version `1` is the current
definition shape. Older unversioned definitions load as version 1, so additive
fields stay backward compatible while future renames or removals can get an
explicit migration path.

The selector field names are still transitional. Conceptually, this is just a
context-fit route node with one provider candidate.

## Route-DAG Delegation

A target can delegate to another Wardwright model artifact:

```json
{
  "model_definition_version": 1,
  "model_id": "coding-balanced",
  "version": "2026-05-18",
  "targets": [
    {
      "model": "private-local-gate",
      "target_kind": "wardwright_model",
      "context_window": 32768,
      "artifact": {
        "model_definition_version": 1,
        "model_id": "private-local-gate",
        "version": "2026-05-18",
        "targets": [
          {"model": "ollama/qwen2.5-coder", "context_window": 32768}
        ],
        "route_root": "local-only",
        "dispatchers": [
          {"id": "local-only", "models": ["ollama/qwen2.5-coder"]}
        ]
      }
    },
    {"model": "managed/kimi-k2.6", "context_window": 262144}
  ],
  "route_root": "outer-context-fit",
  "dispatchers": [
    {"id": "outer-context-fit", "models": ["private-local-gate", "managed/kimi-k2.6"]}
  ]
}
```

For a small request, the outer model can select `private-local-gate`; that model
then resolves to `ollama/qwen2.5-coder`. Receipts preserve both hops:

```json
{
  "decision": {
    "route_type": "model_graph",
    "selected_model": "ollama/qwen2.5-coder",
    "route_lineage": [
      {
        "model": "coding-balanced",
        "route_id": "outer-context-fit",
        "delegated_to": "private-local-gate"
      },
      {
        "model": "private-local-gate",
        "route_id": "local-only",
        "selected_model": "ollama/qwen2.5-coder"
      }
    ]
  }
}
```

## Routing Patterns

The route patterns are useful implementation choices, but they should not
dominate the mental model:

- **Context-fit route**: choose the smallest eligible context window for the
  request and keep larger eligible targets as later fallbacks.
- **Ordered fallback route**: try candidates in declaration order, skipping
  targets whose context windows cannot fit the request.
- **Blended route**: choose among equivalent targets by deterministic-all,
  weighted, or round-robin-style selection.

These can all be expressed as route nodes inside a Wardwright model graph. The
user should think in terms of model middleware behavior first, and only reach
for the specific routing pattern when it matches the job.

## Policy Control

The model graph is the baseline model definition. Route policy runs before
provider selection and can narrow or override that baseline:

- `restrict_routes` adds an `allowed_targets` constraint. Entries may be concrete
  model IDs such as `ollama/qwen2.5-coder` or provider prefixes such as
  `ollama`.
- `switch_model` and `reroute` add a `forced_model` constraint.
- receipts include both the base route decision and `policy_route_constraints`,
  so the UI can show "what the model definition allowed" separately from "what
  policy removed or forced for this request."
- if policy removes every provider candidate, Wardwright fails closed and
  records `route_blocked` in the receipt instead of falling through to an
  arbitrary provider.

Built-in declarative route gates and Dune-backed policy snippets can both emit
these actions. WASM remains fail-closed until the runtime is enabled.

## Roadmap: Delegation Versus Full Middleware Synthesis

Route-DAG delegation answers "which concrete provider should handle this turn?"
without creating policy-order ambiguity. Full middleware synthesis would answer
"how do multiple Wardwright models' policies jointly wrap one call?" That is
more powerful, but it needs first-class UI and receipt support for phase order,
conflict detection, retry ownership, and nested policy evidence.

Near-term roadmap items:

- store multiple activated Wardwright model artifacts instead of embedding every
  delegated artifact inline
- render the route DAG separately from policy overlays in the workbench
- let receipts group route lineage, policy lineage, and provider attempts
- decide whether each model composes by route delegation, middleware wrapping,
  or an explicit per-model setting
- reject policy combinations whose ordering or retry ownership cannot be made
  clear to the user
