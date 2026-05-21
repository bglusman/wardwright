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

The current debugger does not yet do that. Metadata-only receipt replay explains
what a stored receipt says Wardwright decided. Full-session VCR mode records one
request and response payload inside one receipt when explicitly enabled. Neither
is the same thing as a replayable, multi-turn agent transcript.

## Acceptance Scenario

The first contract scenario is intentionally small but agentic:

1. A task asks an agent to enable a feature flag described in `settings.json`.
2. The tool set includes `list_files`, `read_file`, `edit_file`, and `run_tests`.
3. The original run edits a tempting wrong file before reading
   `settings.json`; the final tests fail.
4. Wardwright records the complete session, including model messages, tool
   calls, tool results, policy decisions, receipts, and event cursors.
5. A debugger replays the session to the unsafe `edit_file` call without
   contacting a provider.
6. The operator forks from that cursor with a read-before-edit policy overlay.
7. The fork continues through a live or deterministic agent/model runner.
8. The fork reads the relevant file, edits the right artifact, passes tests, and
   produces a comparison showing the behavior changed for the intended reason.

The opt-in test for this contract lives at
`app/test/counterfactual_replay_acceptance_test.exs`. It is excluded from the
default suite as `:counterfactual_replay_acceptance` until the runtime exists.

Run it explicitly with:

```bash
cd app
mise exec -- mix test --only counterfactual_replay_acceptance
```

## Runtime API Shape

The contract currently expects a `Wardwright.CounterfactualReplay` boundary with
these operations:

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
- `continue/2`: continue the fork with a live or deterministic runner.
- `compare/2`: compare the original and forked sessions at the level an operator
  cares about: final status, failure class, artifacts, tests, provider calls,
  tool calls, policy rule ids, and receipt evidence.

The Gleam module `wardwright/counterfactual_contract` holds the first pure
classification rules for the contract: recording scope, missing runtime
capabilities, replay mode, and accepted outcome. Runtime adapters can stay in
Elixir while the decision rules move toward Gleam.

## Plan Review

This should start as a deterministic ExUnit harness, not a Jido, Python, or live
model dependency. That keeps the acceptance bar reproducible and lets the
missing runtime API fail loudly without network or credential drift. Jido,
Ollama, opencode/pi-style agents, or a Gleam agent package can still be added as
manual or tagged dogfood layers after the deterministic contract is passing.

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
6. Add live continuation behind a tagged profile for real local models or
   dogfood agents.
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

The current red test is still deterministic. A later tagged dogfood layer should
run the same fork contract against a local Ollama model, Jido, or another
controllable agent runner. That layer should stay outside the default suite
because model quality, credentials, and local runtime availability are not
stable CI inputs.
