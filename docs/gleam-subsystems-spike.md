---
layout: default
title: Gleam Subsystem Spike
description: Package fit notes and first pure Gleam subsystem slice for Wardwright.
---

# Gleam subsystem spike

This spike starts with policy state-machine simulation because it is pure
decision logic, already has a stable projection contract, and is useful to both
LiveView and a future Lustre workbench. Boundary adapters should remain thin
Elixir until the surrounding integration is also ready to move.

## Current slice

- Added `wardwright/state_machine_core.gleam` as a typed, deterministic state
  machine runner.
- Exposed an Elixir-friendly tuple API for tests and future adapters.
- Used `non_empty_list` to reject empty transition tables before indexing.
- Used `trie_again` to index transitions by `[state, event]`.
- Used `act` to thread simulation state and trace steps without mutable
  process state.
- Added a small Mix compiler step that discovers imported Gleam Hex packages
  from `mix.exs` and precompiles them before the existing MixGleam compiler
  runs.
- Integrated the parallel Lustre workbench spike without moving Phoenix
  transport ownership into Gleam.
- Moved the Lustre-facing projection summary into `wardwright/projection_core`.
  Elixir now supplies raw model/config evidence plus policy simulation results;
  Gleam derives the workbench projection facts and state-machine replay.

## Lustre integration direction

The useful boundary is now one level farther out than the first state-machine
slice. Phoenix owns HTTP, websocket transport, current config lookup, and the
runtime policy execution path. Lustre/Gleam owns the selected pattern view model,
projection facts, and stateful replay. That lets frontend Gleam import backend
Gleam modules directly instead of asking Elixir for already-projected maps.

Good next candidates for the same treatment:

- Move workbench projection table/view-model shaping into Gleam records.
- Port validation and error accumulation where `non_empty_list` can encode
  "at least one issue" or "at least one viable target".
- Move recipe/model selector normalization into Gleam while keeping persisted
  model config retrieval in Elixir.
- Prototype a read-only SQLite receipt/query path in Gleam before moving writes.

## Package fit notes

| Package | Fit | Suggested next step |
| --- | --- | --- |
| [`act`](https://github.com/MystPi/act) | Good fit for pure simulations and reducers that currently thread state manually. | Keep for policy/workbench simulation cores if the API remains readable. |
| [`non_empty_list`](https://github.com/giacomocavalieri/non_empty_list) | Good fit for invariants like at least one transition, target, guard, or validation error. | Use at internal construction boundaries, then expose plain tuples/maps to Elixir as needed. |
| [`trie_again`](https://github.com/giacomocavalieri/trie_again) | Good fit for route, tool, namespace, and state/event prefix lookup. | Trial it next in tool selector matching where prefix paths matter. |
| [`delay`](https://github.com/bwireman/delay) | Interesting for typed retry plans, but not needed in this pure slice. | Revisit for provider retries or async effect scheduling; avoid adding it unused. |
| [`parrot`](https://github.com/daniellionel01/parrot) / [`sqlight`](https://github.com/lpil/sqlight) | Strong fit for SQLite-owned boundaries because Wardwright controls that storage contract. | Prototype a read-only receipt/query path in Gleam before replacing write paths. |
| [`storail`](https://github.com/lpil/storail) | Possibly useful for local JSON state, but weaker than SQLite for Wardwright durability. | Keep as a prototype-only option unless a small on-disk cache appears. |
| [`valkyrie`](https://github.com/Pevensie/valkyrie) | Useful only if Redis becomes a first-class cache or queue backend. | Defer until Redis is on the roadmap. |
| [`Eventsourcing`](https://github.com/renatillas/eventsourcing) | Conceptually overlaps with receipts and audit trails, but could impose a new architecture. | Evaluate against the storage provider contract before adopting. |
| [`carpenter`](https://github.com/grottohub/carpenter) | Fits ETS acceleration, not durable truth. | Consider only behind existing storage/cache contracts. |
| [`gleam_otp`](https://github.com/gleam-lang/otp) | Good candidate for moving supervised pure-ish BEAM processes into Gleam. | Trial after at least one storage or policy core has a stable Gleam API. |
| [`lustre`](https://github.com/lustre-labs/lustre) and related packages | Relevant to the concurrent UI spike. Shared value comes from typed projection data, not from coupling this core to any UI framework. | Keep the state-machine and projection contracts frontend-agnostic so LiveView and Lustre can consume the same data. |
