---
layout: default
title: Counterfactual Replay Contract
description: Acceptance contract for Wardwright time-travel debugging of agent sessions.
---

# Counterfactual Replay Contract

Wardwright's debugger should eventually answer a hard question:

> This agent run went wrong. If I add or change a Wardwright policy, can I replay
> the same session up to the failure point, fork it, and see whether the new
> policy would have prevented or repaired the failure?

Metadata-only receipt replay explains what a stored receipt says Wardwright
decided. Full-session VCR mode records one request and response payload inside
one receipt when explicitly enabled. The counterfactual runtime now starts the
next layer: a replayable session transcript that can be replayed to a cursor,
forked with a policy overlay, continued either deterministically or through a
configured Wardwright model, and compared.

## Acceptance Scenarios

The first contract scenario is intentionally small but agentic:

1. A task asks an agent to enable a feature flag described in `settings.json`.
2. The tool set includes `list_files`, `read_file`, `edit_file`, and `run_tests`.
3. The original run edits a tempting wrong file before reading
   `settings.json`; the final tests fail.
4. Wardwright records the complete session, including model messages, tool
   calls, tool results, policy decisions, receipts, and event cursors.
5. A debugger replays the session to the `edit_file` call without
   contacting a provider.
6. The operator forks from that cursor with a read-before-edit policy overlay.
7. The fork continues through a live or deterministic agent/model runner.
8. The fork reads the relevant file, edits the right artifact, passes tests, and
   produces a comparison showing the behavior changed for the intended reason.

The same machinery is not specific to unsafe tool calls. The Control Debugger
also includes an output-contract example:

1. A model returns a natural-language answer where the caller requires JSON.
2. Wardwright records the response, validation decision, receipt, and cursor.
3. The operator forks before the response is validated or repaired.
4. The fork applies an output-contract overlay and continues to a valid JSON
   response.
5. The comparison records the original output-contract failure and the passing
   fork.

The opt-in test for this contract lives at
`app/test/counterfactual_replay_acceptance_test.exs`. It is excluded from the
default suite as `:counterfactual_replay_acceptance` because it exercises the
debugger contract and writes transcript artifacts.

Run it explicitly with:

```bash
cd app
mise exec -- mix test --only counterfactual_replay_acceptance
```

## Runtime API Shape

The contract currently exposes a `WardwrightWeb.CounterfactualReplay` boundary
with these operations:

- `transcript_store_health/0`: report transcript storage mode, durability,
  default enablement, and whether writes are serialized through a single global
  writer.
- `run_recorded_session/1`: run a controlled agent scenario with full recording
  enabled through the OpenAI-compatible gateway and return the original outcome
  with receipt ids.
- `transcript/1`: return the ordered multi-turn transcript for a session.
- `replay_until/2`: replay a transcript to an event cursor without calling a
  provider.
- `fork/1`: create an isolated fork from a source session cursor and policy
  overlay.
- `continue/2`: continue the fork with `runner: "scripted_agent"` for
  deterministic CI evidence or `runner: "wardwright_model"` to call the normal
  `/v1/chat/completions` gateway for a configured Wardwright model and record
  the resulting receipt in the fork transcript.
- `compare/2`: compare the original and forked sessions at the level an operator
  cares about: final status, failure class, artifacts, tests, provider calls,
  tool calls, policy rule ids, and receipt evidence.

The Gleam module `wardwright/counterfactual_contract` holds the first pure
classification rules for the contract: recording scope, missing runtime
capabilities, replay mode, and accepted outcome. Runtime adapters can stay in
Elixir while the decision rules move toward Gleam.

## Plan Review

The default implementation uses scripted examples plus a configurable
Wardwright-model continuation path, not a Jido, Python, or live model dependency.
That keeps the acceptance bar reproducible and avoids network or credential
drift. Jido, Ollama, opencode/pi-style agents, or a Gleam agent package can
still be added as manual or tagged dogfood layers after the scripted contract is
passing.

The main product risk is false confidence. Replaying a receipt is not enough,
and replaying to a cursor is still not enough unless the fork can continue from
consistent history. The contract therefore requires both deterministic replay up
to the cursor and continuation after the fork.

## Implementation Slices

1. Persist ordered session transcripts separately from receipt summaries.
   Receipts can point into transcripts; transcripts should not be stored in
   SQLite while writes may come from parallel model/session activity.
2. Add stable event cursors for model messages, policy decisions, provider
   attempts, tool calls, tool results, receipt writes, and checkpoints.
3. Implement metadata replay to a cursor without provider calls.
4. Add fork creation with a policy/model overlay and isolated session id.
5. Add deterministic continuation with a scripted runner for CI.
6. Add live Wardwright-model continuation that resumes from the fork point
   through the normal gateway and records a new receipt.
7. Surface the transcript, fork point, applied policy delta, and comparison in
   the control debugger UI.

## Design Review

The transcript store should be opt-in at the model level and should advertise
where data is saved. Full transcripts may contain prompts, tool arguments, tool
results, and generated artifacts. Metadata-only receipts should remain the
default.

The first durable transcript backend should be append-only files, not SQLite.
Parallel sessions should not serialize writes through a single database actor
unless a later storage design proves that backpressure is intentional and
bounded.

The harness is allowed to use Elixir because it exercises the HTTP/runtime
boundary. Core classification and comparison logic should move to Gleam as the
API becomes stable.

## Deferred Checks

The default tests prove live continuation with a configured canned Wardwright
model, which exercises the gateway and receipt path without network drift. A
later tagged dogfood layer should run the same fork contract against a local
Ollama model, Jido, or another controllable agent runner. That layer should stay
outside the default suite because model quality, credentials, and local runtime
availability are not stable CI inputs.

The Control Debugger page now surfaces transcript-store readiness, records
scripted example sessions, loads transcript events for a selected receipt,
suggests a fork point, and opens replay/fork controls directly under the
selected timeline event. Replaying to that point never calls a provider;
fork/continue can use an editable policy overlay. Current examples cover both
read-before-edit tool ordering and malformed output-contract repair, but the
timeline/fork contract is not tied to unsafe tools. Continuation can run in
scripted mode or through a selected live Wardwright model. The UI is still not a
full policy workbench: semantic policy authoring and artifact diff review are
deferred.

Real Wardwright gateway traffic also participates in this flow when the selected
model has `vcr.mode = full_session` and the request includes `session_id` or
`run_id` metadata. On receipt finalization, Wardwright derives a replayable
session transcript from the recorded request, route decision, provider response,
and receipt event. That transcript is stored in the same append-only transcript
store as scripted examples and can be loaded from the Control Debugger by
selecting the generated receipt.

## Known Runtime Limits

- The deterministic runner currently drives the gateway through the router test
  boundary. Before this becomes a public API or enabled UI action, replace that
  with an explicit gateway boundary so production code does not depend on
  `Plug.Test`.
- The scripted runner installs a canned Wardwright model through the current
  model configuration path to force a deterministic provider response. That is
  acceptable for the opt-in harness, but an interactive debugger should use an
  isolated model overlay rather than mutating the active model registry.
- `events.jsonl` is append-only and session-scoped. `metadata.json` and
  `outcome.json` are atomic sidecar writes, so the current "append-only files"
  claim applies to the transcript event stream, not every artifact in the
  session directory.
- Transcript event appends are serialized per session, not through a global
  writer. Different sessions can continue writing independently, while repeated
  appends to the same session are ordered before the JSONL batch is written.
- Live-agent dogfood is still missing. The next tagged layer should prove the
  same replay/fork/continue flow with a real local model or controllable agent,
  not only a configured Wardwright model returning a canned response.
