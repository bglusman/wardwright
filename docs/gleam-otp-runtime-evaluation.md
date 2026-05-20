---
layout: default
title: Gleam OTP Runtime Evaluation
description: Migration rules for moving Wardwright runtime state into typed Gleam OTP actors.
---

# Gleam OTP Runtime Evaluation

Wardwright already uses Gleam for correctness-heavy policy decisions and Lustre
for the admin workbench. The next useful question is whether long-lived runtime
state should also move into Gleam actors using `gleam_otp`, leaving Elixir as a
thin Phoenix, Plug, provider, and storage boundary.

## Current Process Ownership

Elixir currently owns these mutable runtime surfaces:

- `Wardwright.ReceiptStore`: in-memory/file-backed receipt index plus PubSub
  notifications.
- `Wardwright.ModelApiKeyStore`: model API key lifecycle with optional SQLite
  backing.
- `Wardwright.PolicyScenarioStore`: saved simulator scenarios and fixture
  export.
- `Wardwright.PolicyCache` and `Wardwright.PolicyCache.SessionStore`:
  bounded runtime history and per-scope cache sessions.
- `Wardwright.Runtime.ModelRuntime` and
  `Wardwright.Runtime.SessionRuntime`: supervised model/session lifetimes,
  ordered visibility events, and Dune session reuse.
- `Wardwright.ProviderRuntime`: provider attempt tracking while external calls
  run in supervised tasks.
- `Wardwright.Sinks`: sink normalization and dead-letter handling.

The Elixir supervisor tree also owns Phoenix, PubSub, registries,
`DynamicSupervisor`s, the MCP server, and task supervisors. Those are real
boundary responsibilities and do not need to move first.

## Where Gleam OTP Helps

`gleam_otp` actors can make runtime state machines more explicit than open maps
inside Elixir `GenServer` or `Agent` processes. The strongest candidates are
processes with:

- a small, closed message vocabulary;
- state that can be represented as a typed record or sum type;
- invariants that should be impossible to represent incorrectly;
- behavior that does not depend on Phoenix internals or broad dynamic maps.

Good first candidates:

- Session runtime event ordering. A typed actor can require every publishable
  event to carry a model id, version, session id, sequence, and event type.
- Policy cache configuration and bounded insertion. A typed actor can make
  capacity, recent-limit, scope, and eviction decisions explicit.
- Receipt storage metadata. A typed actor can separate `MemoryStore`,
  `FileStore`, and future store kinds without letting callers mix unsupported
  capabilities.
- Scenario fixture storage. The actor can validate scenario identity and fixture
  compatibility before persistence.

Poor first candidates:

- Provider HTTP calls and streaming adapters. Elixir/Plug/Cowboy and provider
  libraries are still the practical boundary.
- Phoenix controllers, sockets, and LiveView fallback code.
- `Task.Supervisor`, `Registry`, and top-level supervision wiring. These can
  start Gleam actors, but Elixir currently gives clearer integration with the
  app boot path.
- SQLite connection ownership. While Gleam can own typed persistence decisions,
  a single live SQLite writer would introduce avoidable serialization pressure
  for receipts and sessions. Receipt durability should stay append-only file
  based for now.

## Proposed Migration Shape

Use Elixir wrappers as stable public modules while moving the state machine
behind them into Gleam actors one subsystem at a time.

1. Define a Gleam module with typed state, typed messages, and pure transition
   helpers.
2. Start the Gleam actor from the existing Elixir supervisor or wrapper.
3. Keep the public Elixir function names initially unchanged so controllers and
   tests do not churn.
4. Add tests that prove behavior at the boundary: event ordering, isolation
   between model/session siblings, eviction, persistence mode, and failure
   handling.
5. Remove the old Elixir state implementation only after the wrapper delegates
   fully to Gleam.

This gives a reversible path: each migration is judged by reduced invalid
states, simpler tests, and no worse concurrency behavior.

## First Spike

The best first spike is `Wardwright.Runtime.SessionRuntime`.

Reasons:

- The state is naturally typed: model id, version, session id, sequence,
  event count, last event, and Dune session cache.
- The existing tests already assert sibling isolation and ordered event
  publishing.
- It is meaningful runtime logic but still narrow enough to migrate without
  changing HTTP routes, provider calls, receipt storage, or UI behavior.

The spike should stop before porting Dune session evaluation if interop becomes
awkward. A useful intermediate result would be a Gleam-owned session event actor
with Elixir still handling the Dune sandbox call as a boundary operation.

## Decision Rule

Move runtime state into Gleam OTP when the migration removes representable bad
states or materially clarifies concurrency ownership. Do not move a subsystem
only to replace a small Elixir `GenServer` with a larger FFI adapter.
