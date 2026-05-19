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
- Left router, endpoint, LiveView, and Lustre files untouched so this branch can
  be compared with the parallel Lustre spike cleanly.

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

## Conflict notes

The parallel Lustre worktree also changes `app/gleam.toml`, `app/mix.exs`, and
`app/mix.lock`, and has its own untracked `app/manifest.toml` plus Lustre test
files. Dependency resolution will need a small manual merge. This spike
intentionally avoids the Lustre branch's router, endpoint, socket, controller,
and frontend files.
