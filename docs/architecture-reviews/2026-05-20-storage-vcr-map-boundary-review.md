---
layout: default
title: Map Boundary Review - 2026-05-20 Storage and VCR
description: Review note for the map-boundary ratchet update in the receipt storage and VCR PR.
---

# Map Boundary Review - 2026-05-20 Storage and VCR

The map-boundary baseline increases in this PR are intentional and confined to
JSON/storage boundary modules:

- `Wardwright` normalizes and exposes the new model-scoped `vcr` config. Model
  artifacts are still JSON-compatible maps because they are stored in SQLite,
  served through public model APIs, and edited by the admin UI.
- `Wardwright.ReceiptStore` remains the receipt JSON boundary. It now switches
  between memory and SQLite-backed receipt maps and reports storage health.
- `Wardwright.SQLiteStore` now persists receipts as JSON plus indexed summary
  columns. That module is the storage adapter, so string-keyed JSON access is
  expected there.

The review decision is not to introduce Ecto in this PR. The current storage
surface is small, SQLite-only, and already behind an explicit adapter. Ecto
should be reconsidered when Wardwright needs relational joins across receipts
and scenarios, storage migrations across multiple backends, or a Postgres
deployment target.

The longer-term direction is still to keep pure policy and route logic out of
string-keyed maps, and to confine JSON-shaped access to file, API, UI, and
storage adapters.
