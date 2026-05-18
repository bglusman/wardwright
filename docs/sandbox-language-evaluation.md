---
title: Sandbox Language Evaluation
description: Evaluation plan and early findings for Dune, Starlark, and other policy execution languages.
---

# Sandbox Language Evaluation

Wardwright should evaluate policy languages along two separate axes:

1. **Authoring quality**: whether AI and technical policy authors can produce,
   repair, explain, and review correct policies.
2. **Execution boundary**: whether the runtime can enforce bounded execution,
   fault isolation, deterministic outputs, and fail-closed receipts.

The primary user interface should remain natural-language assisted authoring,
projection visualization, simulation, and review. The language is an
implementation and storage detail unless a technical user opens the advanced
editor.

## Candidates

| Candidate | Primary value | Main concern |
| --- | --- | --- |
| Structured YAML/TOML policy | Best projection, validation, and UI explainability | May need many primitives before it covers advanced cases |
| Dune / Elixir subset | Native BEAM execution, allowlist, timeout, reduction, memory limits | Best-effort sandbox only; not a hostile multi-tenant boundary |
| Starlark sidecar | Portable deterministic policy language with mature Go/Rust engines | Sidecar lifecycle, backpressure, projection fidelity |
| Starlark Rustler NIF | Fast in-process Starlark semantics | NIF crash/scheduler risk even with dirty schedulers |
| JS/Deno | Strong model familiarity and mature tooling | Operational/runtime boundary is separate from BEAM supervision |
| Lua/Luerl | Designed for embedded scripting and BEAM-compatible options exist | Less likely to be authored well by generic LLMs than JS/Starlark/Elixir |

## Execution Tiers

Wardwright should not force one sandbox language to satisfy every trust model.
Policy execution should be split by provenance:

| Tier | Engines | Intended use | Boundary |
| --- | --- | --- | --- |
| Local trusted | structured primitives, Dune | operator-owned rules, AI-authored local snippets, fast iteration | BEAM supervision plus allowlist, timeout, reduction, memory, and receipt controls |
| Portable untrusted | WASM, sidecar, hosted policy service | externally shared packages, marketplace policies, third-party policy code | capability-based host ABI, fuel, memory limits, deterministic IO, provenance metadata |

Dune is therefore an ergonomics and local-control candidate. It should not be
marketed as the hostile-code boundary. WASM or an isolated external process
should be required before policy crosses an external trust boundary.

## Dune Spike Findings

The initial Elixir spike adds `Wardwright.PolicySandbox.Dune`, a thin adapter
that normalizes Dune success and failure structs into policy-engine result maps.
This is intentionally small so callers can fail closed without binding the rest
of Wardwright to Dune's API.

A second spike adds `Wardwright.PolicySandbox.DuneSnippetRegistry`, a small
registry of named snippets plus an evaluator for registry and ad hoc source.
The registry is exposed through protected HTTP and MCP-shaped tools:

- `GET /v1/policy-authoring/dune-snippets`
- `POST /v1/policy-authoring/dune-snippets/evaluate`
- `list_dune_snippets`
- `evaluate_dune_snippet`

The evaluator binds a JSON-like `input` map before executing source, normalizes
successful map returns to `wardwright.policy_result.v1`, and turns sandbox
failures or malformed returns into explicit fail-closed policy results. This is
the first concrete version of the "snippet emulator" idea: an agent can draft
or fork a snippet, run it against representative inputs, and show the exact
policy action and trace before suggesting artifact changes.

The next maturation step converts the small reusable `engine: primitive`
contains matcher into the registry snippet
`primitive.request-contains-actions`. Existing primitive-engine artifacts still
load as a compatibility shape, but their behavior now executes through the same
Dune adapter and action/result ABI as hand-authored snippets. This is the first
case where Dune is not merely parallel example code: it is the source of truth
for a previously separate primitive engine implementation.

Executable tests currently verify:

- deterministic policy-shaped map results can be returned
- parsed code exposes a reviewable AST string while runtime atoms are rewritten
- file, environment, process spawn, and message-send attempts fail closed
- CPU-heavy policy work can be stopped by `max_reductions`
- large allocations can be stopped by `max_heap_size`
- low wall-clock budgets stop slow allowed work by timeout or reductions
- registry snippets are inspectable and evaluate against example inputs
- ad hoc snippets can be tested, while malformed outputs fail closed
- the legacy primitive contains engine is backed by a named Dune snippet and
  still emits the same policy actions through hybrid evaluation

## Primitive Conversion Inventory

The current direction is to keep only genuinely tiny, high-value primitives in
host code and move higher-level policy behaviors into named, inspectable Dune
snippets when local trusted policy is acceptable.

| Primitive family | Current use | Dune conversion status | Recommendation |
|---|---|---|---|
| `engine: primitive` request contains rules | Compatibility tests, not workbench demos | Converted to `primitive.request-contains-actions`; legacy artifacts are now a shim over Dune | Keep only as a compatibility alias, then remove from user-facing docs |
| `route_gate`, `request_guard`, `request_transform`, `receipt_annotation` contains/regex rules | Request routing, alerts, reminders, and tests | Not converted; straightforward to express as Dune snippets, but host code still owns request mutation and route-constraint merging | Convert next if Dune traces stay readable; preserve host helpers for applying normalized actions |
| `history_threshold` and `history_regex_threshold` | Demonstrates session-local cache/history behavior | Partially mirrored by `history.related-secret-ladder`, but host implementation still owns cache queries | Keep cache access in host for now; expose a narrow facts input to Dune snippets rather than direct arbitrary cache reads |
| `tool_selector`, `tool_loop_threshold`, `tool_sequence` | Tool policy tests and tool-governance demos | Partially mirrored by `tool.browser-before-shell`; host implementation still records selector status, state transitions, and sequence evidence | Good Dune candidates once input facts and trace metadata are stable |
| Stream horizon/rewrite/retry primitives | Core TTSR demos and stream tests | Not converted | Do not convert first; streaming control has latency, buffering, and provider-termination semantics that should stay in host runtime until Dune can only choose actions over explicit stream facts |
| Structured-output guard rules | Bakeoff and ambiguous-success demos | Not converted | Possible later, but parser/schema validation should remain host-owned with Dune choosing repair/block policy over parsed evidence |

One useful observation: recursive module-style code hit the memory cap before
the reduction cap in an early test. This is acceptable fail-closed behavior, but
it means Wardwright should treat timeout, reductions, and memory as complementary
controls rather than assuming one budget is authoritative.

## Evaluation Matrix

Each candidate should be scored on:

- correctness on the same TTSR, route privacy, cache/count threshold, model
  switch, and ambiguous-success policies
- AI authoring quality: first-pass correctness, repairability after validation
  errors, policy size, and explanation quality
- projection quality: static node/effect extraction, source spans, opaque-region
  reporting, and trace-to-node linkage
- bounded execution: timeout, fuel/reduction cap, memory cap, kill behavior,
  scheduler impact, and receipt visibility
- fault isolation: whether one model/session/policy failure can crash, block, or
  starve unrelated sessions
- security posture: host API access, filesystem/env/network denial, atom leaks,
  process/message access, imports/metaprogramming, and dependency trust
- operational cost: runtime dependencies, deploy shape, observability,
  backpressure, and upgrade/migration surface

## Near-Term Decision Gate

Dune should advance only if it remains strong on all of these:

- common policies are easier for AI to author and repair than Starlark
- projection from Dune AST plus runtime traces is honest enough for review
- timeout, reduction, and memory failures are typed and receipt-friendly
- default allowlist blocks host escape attempts relevant to Wardwright
- BEAM model/session supervisors stay responsive under hostile policy workloads

Even if Dune passes, it should initially be treated as a local/trusted advanced
policy engine. Hostile third-party policy still needs a stronger boundary such
as a sidecar, WASM runtime, microVM, or hosted policy service.

## Current Implementation Shape

The BEAM prototype now has a common policy namespace for three execution paths:

- low-level request governance in `Wardwright.Policy.Plan`; the reusable legacy
  `engine: primitive` contains matcher now executes through the Dune snippet
  registry
- Dune snippets through `Wardwright.PolicySandbox.Dune` and
  `Wardwright.PolicySandbox.DuneSnippetRegistry`
- WASM through `Wardwright.PolicySandbox.Wasm`

The WASM path is intentionally fail-closed until a runtime dependency and fuel
budget are enabled. That keeps the ABI visible to tests and receipts without
pretending an untrusted-code boundary exists before it has actually been wired.
Hybrid evaluation composes engine results and blocks if any child engine fails
closed. Primitive, Dune, and WASM policies should continue to share the same
bounded history/cache and regex helpers so behavior does not depend on which
engine authored a rule.
