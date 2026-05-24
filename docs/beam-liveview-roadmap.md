---
layout: default
title: BEAM and Workbench Roadmap
description: Tentative architecture direction for Wardwright's Elixir, Gleam, Phoenix, and Lustre implementation.
---

# BEAM and Workbench Roadmap

The current working assumption is that Wardwright's primary implementation should
move toward a BEAM architecture:

- **Elixir** owns runtime plumbing: HTTP, Phoenix, supervision, registries,
  GenServers, ETS ownership, sidecar/NIF boundaries, provider calls, telemetry,
  dynamic config, and operational dashboards.
- **Gleam** owns correctness-heavy pure logic: policy/config data types,
  action/result ADTs, route arbitration, guard-loop state machines, cache
  eviction decisions, receipt classification, and projection generation where
  exhaustiveness materially reduces bugs.
- **Lustre/Gleam** owns first-party workbench behavior where typed view models
  and controlled inputs reduce UI drift. Phoenix remains the HTTP host for the
  operator UI and protected APIs.
- **Phoenix PubSub** is the early visibility bus between supervised runtime
  state and workbench projections. Session/model processes should publish
  receipt events, policy transitions, queue health, and simulation updates so
  the UI and other nodes can observe behavior without taking ownership of the
  hot session state.

This selection is now strong enough that the old Go and Rust backend prototypes
have been removed from the live tree. They remain useful historical evidence in
git, but active implementation should happen on the BEAM unless a later spike
shows a concrete reason to reverse course. The key difference is that Elixir and
Gleam do not need to compete as whole backends: each pure function or runtime
boundary can be assigned to the language that fits it best.

## Boundary Rule

Default to Gleam when all of these are true:

- the logic is pure or nearly pure
- invalid states can be represented with typed variants instead of ad hoc maps
- exhaustive pattern matching would catch real product mistakes
- the Elixir/Gleam boundary can be expressed as a small stable input/output
  shape

Default to Elixir when any of these are true:

- the code owns a process, supervisor, registry, socket, endpoint, ETS table, or
  sidecar
- behavior is intentionally dynamic or operator-configured
- the code needs mature Phoenix/Plug/LiveView/Ecto/Telemetry APIs
- the code is mostly orchestration, IO, or lifecycle management

Runtime call overhead between Elixir and Gleam should not drive the decision.
Both compile to BEAM modules. The real costs are build/tooling complexity,
library maturity, data-shape translation, and duplicated logic across the
boundary.

## Runtime Shape

The target process hierarchy is:

1. application supervisor
2. model registry and dynamic supervisor
3. one model runtime subtree per Wardwright model/version
4. session registry and dynamic supervisor under each model runtime
5. one session runtime per caller/session/run
6. narrow workers for provider calls, sidecars, dirty NIF calls, alert queues,
   stream windows, and policy evaluation

Required runtime tests:

- crash one session and prove sibling sessions continue
- crash or restart one model runtime and prove other models continue
- saturate or timeout a sidecar/alert queue and prove unrelated failure domains
  do not inherit backpressure
- publish model/session/receipt events over PubSub and prove LiveView-style
  subscribers see ordered visibility updates without mutating session state
- run a dirty NIF policy evaluation and document scheduler isolation separately
  from killability
- emit receipts with model id/version, session id, policy version, attempt id,
  and failure domain

Cluster visibility should start as PubSub-backed projections, not distributed
session mutation. A session should have one authoritative owner process tree at
a time. Other nodes can subscribe to visibility topics, render near-real-time
state, and consume receipt/event projections. Cross-node session handoff,
distributed locking, or multi-node mutation should be treated as later explicit
features with their own failure semantics. Phoenix PubSub is the application
mechanism; actual multi-node delivery still requires an explicit node discovery
and clustering configuration such as distributed Erlang/libcluster.

Sidecars remain attractive for hard killability, but they must be scored as
backpressure and scaling risks: queue depth, single-worker serialization,
protocol failures, cold starts, restart storms, pool sizing, and cross-session
or cross-model saturation.

State machines appear in several layers and should not be conflated:

- policy state-machine artifacts are user-facing governance data
- pure transition selectors can live in Gleam when exhaustiveness helps
- Elixir runtime processes own supervision, timers, cancellation, PubSub, ETS,
  and provider IO
- long-lived or highly eventful machines may compile to or be hosted by
  `gen_statem` when process lifecycle semantics matter

The older `gen_fsm` mental model is useful vocabulary, but the implementation
spike should evaluate modern `gen_statem` and ordinary GenServer-plus-pure-core
options. Users should not need to author raw callbacks for the default path.
If an expert mode later allows code-backed machines, the code must still expose
a transition graph, declared effects, simulation hooks, timeout behavior, and
receipt trace spans.

## Workbench Direction

The removed TypeScript prototype and earlier LiveView projection spike were
useful for shape discovery. The active operator workbench is now Phoenix-hosted
Lustre, with Elixir retaining the HTTP/API/PubSub boundaries.

Initial workbench surfaces:

- Wardwright model catalog and version switcher
- policy projection workbench
- simulation runner with trace overlay
- receipt explorer and diff view
- runtime dashboard for model/session trees, queue depth, restarts, and policy
  failures
- advanced policy editor with a deterministic artifact preview

Workbench pages should subscribe to PubSub topics for the model, session,
receipt, policy artifact, and simulation scope they are rendering. The server
projection remains authoritative: PubSub messages should be small invalidation
or event records that cause the workbench to update from supervised state,
durable receipts, or cached projections.

The UI must render stable backend projections rather than engine-specific
implementation details. The policy artifact and compiled plan remain the
authority; projection and simulation are review aids.

## Library Shortlist

Use Phoenix for HTTP hosting and protected endpoints, and keep Lustre/Gleam as
the default place for new first-party workbench behavior. Add client-side hooks
only for graph or canvas interactions that the server projection cannot express
cleanly.

Recommended library posture:

| Area | Candidate | Use |
|---|---|---|
| Base workbench UI | Lustre components plus existing CSS | Prefer the current typed workbench surface before adopting a larger UI kit. |
| Accessible component kit | Fluxon UI, SaladUI, or Petal Components | Evaluate only if the current Lustre/Phoenix surface cannot cover a repeated dashboard pattern cleanly. |
| Interactive policy graph | LiveFlow | Spike for node graphs. It is very young, so treat it as experimental and keep a fallback path. |
| Custom graph/canvas | Phoenix-hosted hook plus Cytoscape, D3, Mermaid, or custom SVG | Use only for graph interactions the typed workbench cannot express cleanly. Keep the graph data shape server-owned. |
| Operations dashboard | Phoenix LiveDashboard plus custom pages | Use for VM/process/telemetry inspiration and possibly embed internal metrics pages. |

Avoid committing to a large UI kit before the policy projection contract settles.
The first goal is a dense operational workbench, not a marketing dashboard.

## Near-Term Spikes

1. **Projection Contract Merge**
   Review and merge the policy projection FE/BE contract work. The contract
   should describe projection nodes, confidence, effects, conflicts, simulation
   traces, and receipt previews without assuming a client runtime.

2. **Lustre Projection Workbench**
   Keep the active Lustre workbench focused on model selection, projection
   evidence, replay controls, and adapter/framework status. Add server-side
   tests for route behavior and projection shape before adding a UI component
   library.

3. **Gleam Decision Core**
   Initial Gleam decision modules now live under `app/src/wardwright` and are
   called from the live Elixir path through wrapper modules. They currently own
   structured-output guard-loop arbitration, recent-history threshold
   classification, alert enqueue/backpressure classification, action/result
   metadata, and route selector decisions. Runtime code should call the Gleam
   cores directly through thin Elixir boundary wrappers rather than carrying
   Elixir fallback adapters. When an Elixir mirror helps readers or reviewers,
   keep it as executable reference documentation under
   `app/src/wardwright/elixir_reference` as a `.exs` module matching the Gleam
   core, and load it only from tests.

4. **Runtime Isolation Demo**
   Build model/session dynamic supervisors in the primary Elixir backend and
   expose a small LiveView or admin endpoint that shows child trees, restarts,
   queue depth, PubSub visibility topics, and failure-domain receipts.

5. **Dune vs Starlark Sandbox Spike**
   Dune should be evaluated separately from Gleam. Gleam is a typed core
   language; Dune is an Elixir sandbox candidate. Compare Dune with Starlark on
   sandbox strength, timeout/reduction limits, source review, visualization,
   ergonomics, and sidecar/NIF/backpressure tradeoffs. Track executable
   findings in [Sandbox Language Evaluation](sandbox-language-evaluation.html).
