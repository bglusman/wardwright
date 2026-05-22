---
layout: default
title: Storage Inventory
description: Durable and ephemeral Wardwright runtime stores.
---

# Storage Inventory

Wardwright currently uses one configurable SQLite store, one file-backed receipt
store, and a few runtime stores with narrower durability contracts. SQLite is
an operator/admin artifact store in this design, not the live coordination
plane for active agent execution.

## SQLite Store

`WARDWRIGHT_SQLITE_STORE` chooses the SQLite path. If unset, package/runtime
builds use Wardwright's XDG data path. Test configuration can set
`:sqlite_store_path` to `nil` to keep storage ephemeral.

The SQLite store owns:

- registered model definitions
- hashed model API keys

SQLite deliberately does not own receipts while Wardwright's default local
store is SQLite. Receipt writes can happen in parallel across active agent
traffic, and making one shared SQLite database the hot receipt sink creates
avoidable lock and corruption-risk questions before Wardwright has a real
multi-writer database story.

## Receipt File Store

`WARDWRIGHT_RECEIPT_STORE_DIR` chooses the receipt directory. If unset,
package/runtime builds use Wardwright's XDG data path at `receipts/`. Test
configuration can set `:receipt_store_dir` to `nil` to keep receipts ephemeral.

The file-backed receipt store writes one JSON file per receipt with an atomic
write-and-rename path. Receipts are still held in memory while the process is
running for fast replay and list filtering, but durable file IO happens outside
the in-memory index critical section. The source records are loaded back from
the receipt directory on receipt-store startup or storage reconfiguration.

This is still a v0 debugger convenience. It is appropriate for local use, admin
review, and receipt snapshots. It avoids putting parallel receipt writes through
one global SQLite database, but it is not yet a hosted multi-node receipt store
or an analytics database.

## Session Capture Storage

Full-session VCR capture should grow toward session-scoped artifacts: one
serial capture bundle per agent/session, optionally indexed by the admin SQLite
store for discovery. The important constraint is that the live capture path
should have one writer per session. If SQLite is used for a full transcript
bundle, prefer a separate SQLite file per session over one shared live database.
That keeps the write path naturally serialized, makes sensitive captures easier
to delete or move as a unit, and avoids pretending that one global SQLite
database is the right live-data bus for parallel agents.

A future shared admin database can still index these captures after the fact:
receipt id, session id, model id, timestamps, storage path, redaction mode, and
summary status are good index records. Raw request/response payloads and
step-by-step tool transcripts should live in file/session artifacts unless a
specific operator workflow requires importing them into a database.

## Scenario Fixtures

`PolicyScenarioStore` is still memory-backed by default with an optional
JSON-file store configured by `:policy_scenario_store_path`. That is enough for
portable fixture packs and regression export, but it is now the main remaining
operator-authored artifact that should probably move behind the SQLite storage
contract.

Recommended next step: decide whether reviewed scenarios belong beside receipts
as files or in SQLite with model configuration. The answer should follow the
write pattern: operator-authored, low-rate configuration can live in SQLite;
parallel live traces should stay out of the shared SQLite store.

## Runtime State

These stores are intentionally ephemeral for now:

- `PolicyCache`: bounded session/history hints used by dynamic policy
  evaluation.
- `ProviderRuntime`: provider health, attempt counts, and latency observations.
- `Sinks`: in-process alert sinks and dead-letter buffers.
- `Runtime.SessionRuntime` and `Runtime.ModelRuntime`: supervised execution
  state.

Durability for these should be added only when there is a clear replay or
operator workflow that needs it. They should not move to SQLite just because
they are process-local. If a live workflow needs capture, prefer a
session-scoped append-only artifact first and import/index it through the admin
layer after the fact.

## Gleam Boundary

Persistence should follow the same boundary rule as policy execution: pure
shape decisions belong in Gleam, runtime adapters stay in Elixir.

Recommended extraction order:

1. Add Gleam types for persisted receipts, VCR metadata, model configuration
   storage records, and storage health.
2. Move receipt/model/key normalization, summary fields, and indexed-column
   extraction into Gleam.
3. Keep the SQLite/file drivers, app-env lookup, file permissions, and
   supervision in Elixir unless Wardwright adopts dedicated Gleam storage
   adapters.

This keeps the storage contract typed without forcing database-driver and OTP
boundary work into Gleam prematurely.

## Ecto Decision

Do not add Ecto yet. The current persistence surface is small and already has
an explicit storage boundary. Ecto becomes more attractive when Wardwright
needs migrations across multiple storage backends, relational queries over
operator artifacts, or a Postgres deployment target.
