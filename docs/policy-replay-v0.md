---
layout: default
title: Policy Replay V0
description: Minimal metadata-only receipt replay for Wardwright policy decisions.
---

# Policy Replay V0

Policy replay v0 gives Wardwright a small VCR-style control-layer loop:

1. Record sanitized request, policy, route, and provider outcome metadata into
   receipts.
2. Replay those recorded policy and route decisions from a receipt without
   calling a provider.
3. Use replay evidence before importing a receipt into a scenario pack or
   drafting a policy change.

The replay artifact is not the source of truth for policy behavior. The active
model artifact remains authoritative. Replay is evidence about what one stored
receipt says happened.

## Plan

- Add metadata-only `vcr` data to new receipts.
- Keep raw prompt and completion text out of VCR by default.
- Add a model-scoped opt-in `vcr.mode: full_session` for debugging sessions
  where the operator needs full request and provider response payloads.
- Add a dedicated replay boundary instead of adding branches to the router or
  receipt store.
- Expose a protected API path:
  `POST /v1/policy-authoring/replay-receipts/{receipt_id}`.
- Keep the operator workbench unchanged for this slice.

## Adversarial Plan Review

- Risk: replay could become a second policy engine. Constraint: v0 only replays
  recorded decisions and reports `mode: receipt_metadata`.
- Risk: VCR could accidentally store sensitive content. Constraint: request
  recording stores message roles and content lengths, not message text.
- Risk: full-session VCR becomes an always-on surveillance feature. Constraint:
  `metadata_only` is the default, and full-session capture is configured
  per model through the model artifact/UI.
- Risk: replay could imply a provider result was regenerated. Constraint: replay
  always reports `provider_called: false` and `would_call_provider: false`.
- Risk: old receipts become unusable. Constraint: replay can fall back to legacy
  receipt decision fields with a warning.

## Implementation Notes

New receipts include `vcr.schema = wardwright.policy_vcr.v0` with:

- request metadata: model, normalized model, message count, message roles,
  content lengths, estimated prompt tokens, stream flag, tool context
- policy metadata: actions, conflicts, events, alert count, route constraints,
  tool policy summaries
- route metadata: selected model/provider, route id/type, skipped targets,
  fallback fields, policy route constraints
- provider outcome metadata: called provider flag, mock flag, status, latency,
  provider id/model, provider metadata, provider error

When a model has `vcr.mode = full_session`, the same VCR block also includes
`vcr.full_session.request.body` and `vcr.full_session.response`. This is the
source material for later "replay the whole session until the bad turn" work.
It is deliberately not the default because it can include prompt, tool-call,
and provider response payloads.

Receipt storage uses a file-backed store when enabled.
`WARDWRIGHT_RECEIPT_STORE_DIR` chooses the receipt directory; otherwise the
packaged app uses Wardwright's XDG data path. Test builds can still disable the
file store and keep receipts in memory.

The SQLite store remains for model definitions and API key hashes, not receipt
writes. Full-session VCR should continue toward one serial artifact per
agent/session, with a future admin index recording where that artifact lives and
what receipt/session/model it belongs to.

The replay API returns `wardwright.policy_replay.v0` and does not insert a new
receipt.

## Adversarial Implementation And Design Review

- The replay boundary still consumes receipt-shaped maps because receipts are a
  JSON/storage boundary. The module keeps replay semantics separate from route
  planning and provider transport.
- The current replay is historical, not counterfactual. It cannot answer "what
  would the current policy do now?" without a later sanitized input feature
  contract.
- Full-session receipts are more useful for a time-travel debugger, but they
  deliberately trade privacy for debuggability. Operators should use
  metadata-only mode for normal operation and enable full-session mode only for
  bounded investigations.
- Message content length in metadata-only mode can still leak coarse metadata.
  That is acceptable for v0 because receipts already retain control metadata,
  but deployments needing stronger privacy should make even length metadata
  configurable.
- Provider metadata must remain allowlisted. The current provider adapters store
  usage and finish reasons, but future adapters should not place completion text
  inside provider metadata.

## Test Evidence

Behavior tests cover:

- VCR metadata is recorded on simulated receipts and excludes synthetic prompt
  and completion text.
- Full-session VCR mode stores full request and response payloads only when
  explicitly configured on the model.
- `Wardwright.PolicyReplay.replay_receipt_id/1` returns recorded policy and
  route decisions with provider calls disabled.
- The protected replay API rejects remote callers, replays local stored
  receipts, and returns `404` for missing receipt ids.
- File-backed receipt storage persists receipts across receipt-store reloads
  while memory mode remains available for tests and ephemeral runs.

Run from `app`:

```bash
mix test test/policy_replay_test.exs
mix format --check-formatted
```
