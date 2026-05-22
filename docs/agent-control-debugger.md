---
layout: default
title: Agent Control Debugger
description: Wardwright's trace-driven control loop for agentic workflows.
---

# Agent Control Debugger

Wardwright should not compete with tool-call reliability libraries or static
workflow engines at their strongest point. Its useful product loop is to record
agent behavior at the model boundary, explain the policy and routing decisions
that happened there, and let an operator turn a real trace into a safer,
measurable control change.

This page is the implementation log for that loop. Each shipped slice should
leave the same review trail:

1. plan
2. adversarial plan review
3. implementation notes
4. adversarial implementation and design review
5. test evidence

## Ralph Loop Acceptance Criteria

A Ralph debugging loop is not complete merely because one operator can click
through the UI. The same debugging capability must be available through three
operator surfaces:

- the visual Control Debugger UI
- MCP tools for an assisting agent
- CLI or CLI-discoverable HTTP/API instructions for scriptable operation

Each surface should be usable by a future agent or operator with no private
project context. It may point to a dedicated help command, docs URL, or example
catalog instead of embedding every example inline, but the surface itself must
explain what to run next and where to get complete guidance.

For a Ralph run to count as accepted, the evidence should show:

- UI proof: screenshots of the investigation, replay or fork controls, final
  result, and any confusing UI state that drove a change.
- MCP proof: tool-discoverable names, argument shapes, and safety notes for the
  same investigation path, or a clearly filed follow-up when a control is
  missing.
- CLI proof: `wardwright tools` or another documented command gives enough
  context for an agent starting from a shell to discover the same debugging
  workflow without reading the repository.
- Cross-check proof: final scenario, trace, replay result, and saved evidence
  agree across the UI and non-UI surfaces.

The surfaces do not need identical interaction design. They do need to share the
same backend capability model so that the UI cannot become a polished demo while
MCP and CLI remain incomplete, and so that agent-assisted debugging does not
gain invisible powers that a human operator cannot review.

## Track 1: Streaming Tool Calls

### Plan

OpenAI-compatible streaming providers may emit tool calls as
`choices[].delta.tool_calls` chunks. Wardwright should preserve those tool-call
deltas when acting as a proxy, and receipts should distinguish text stream
content from structured tool-call output.

### Adversarial Plan Review

The risk is treating tool-call deltas as ordinary text. That can produce a
successful receipt while the caller receives no actionable tool call. The fix
must prove behavior at the public OpenAI-compatible stream boundary, not only in
provider parser internals.

### Implementation Notes

OpenAI-compatible SSE parsing now recognizes `delta.tool_calls` chunks and
preserves them as downstream OpenAI-compatible SSE deltas. Receipts record only
the safe fact that structured delta fields were preserved, using
`preserved_delta_fields: ["tool_calls"]`; they do not store raw tool-call
arguments.

Provider capability metadata no longer marks OpenAI-compatible stream
`tool_calls` deltas as unsupported. This is pass-through support, not argument
policy enforcement.

### Adversarial Implementation And Design Review

The fix intentionally avoids inspecting streamed tool-call arguments in the
text stream policy path. That keeps passthrough safe for Forge-style proxy
composition, but it also means Wardwright is not yet enforcing argument-level
tool-call rules. A streamed tool-call delta can start the downstream SSE
response, so later text-policy retry semantics remain constrained by the
already-started response boundary.

### Test Evidence

Focused evidence for this slice:

```text
(cd app && mise exec -- mix test --no-deps-check test/stream_provider_transport_test.exs)
(cd app && mise exec -- mix test --no-deps-check test/storage_and_admin_test.exs)
```

The stream-provider tests cover fake OpenAI-compatible SSE chunks containing
`delta.tool_calls` and assert the downstream SSE plus receipt metadata.

## Track 2: First-Class Allowed Tools

### Plan

State or phase scoped `allowed_tools` should become an explicit model artifact
feature. Existing tool-context normalization already identifies the current
tool, phase, namespace, and source; the new feature should compile that data
into a clear allow/block decision and receipt evidence.

### Adversarial Plan Review

Static allowlists can be too blunt. The first slice should avoid pretending to
solve all workflow orchestration. It should enforce the narrow claim: "in this
state or phase, this tool name/namespace is allowed and other matching tool
calls are blocked with evidence."

### Implementation Notes

`kind: "allowed_tools"` is now a first-class governance rule. It matches
normalized tool context by phase and optional state scope, lets listed tools
pass without a policy action, and blocks unlisted matching tool calls with the
existing fail-closed policy-action path.

Receipts expose the decision evidence needed to debug the block:
`allowed_tools`, `blocked_tools`, `allowed_tool_phase`, `state_scope`, and the
normalized `tool_context`. The artifact validator and projection path recognize
the new rule kind.

### Adversarial Implementation And Design Review

This is deliberately narrower than Statewright-style workflow orchestration. It
does not prove that an agent is in the correct state; it enforces that when
Wardwright is given a phase/state/tool context, the current tool call is or is
not allowed there. Dynamic policy remains possible because the allowlist is
part of the model artifact rather than hardcoded middleware.

### Test Evidence

Focused coverage lives in `tool_context_policy_test.exs`, with projection and
validator assertions in the public API and projection tests. Full app validation
must still be run after integration because this slice touches core planning
and projection contracts.

## Track 3: VCR Record And Policy Replay

### Plan

Wardwright receipts already capture the route, policy, provider, caller, and
final status. VCR v0 should make that record replayable for deterministic
policy decisions without calling a provider. Live replay can later fork from a
receipt and resume against a real provider, but deterministic replay is the
first safe contract.

### Adversarial Plan Review

Replay is not a perfect counterfactual. It can prove that a new policy would
have matched the recorded facts, but it cannot prove the model would have made
the same later choices after an intervention. Docs, API names, and receipt
fields must preserve that distinction.

### Implementation Notes

New receipts include `vcr` data for policy, route, request shape, decision, and
final status. The default model configuration is `vcr.mode: metadata_only`,
which records message roles and lengths rather than prompt/completion text.
Operators can explicitly set `vcr.mode: full_session` on a model when a
debugging session needs complete request and provider response payloads.

`Wardwright.PolicyReplay.replay_receipt_id/1` returns
`wardwright.policy_replay.v0` results without calling a provider, and a
protected authoring endpoint exposes that replay:
`POST /v1/policy-authoring/replay-receipts/:receipt_id`.

Receipts now use the configurable file-backed receipt store when it is enabled,
so debugger receipts survive process restarts in normal local/package runs
without making the shared SQLite model/key store the live receipt write path.

The authoring tool list advertises the replay tool so MCP clients can discover
the capability.

### Adversarial Implementation And Design Review

Replay v0 is historical replay, not counterfactual execution against a changed
policy. Metadata-only mode intentionally omits raw prompt and completion
content; request metadata is limited to roles, lengths, model ids, and routing
facts. Full-session mode is intentionally explicit because it stores sensitive
payloads for later time-travel debugging. Legacy receipts can replay from
existing decision metadata with a warning, but only new receipts get the
explicit VCR schema.

### Test Evidence

Focused evidence:

```text
(cd app && mise exec elixir@1.20.0-rc.6-otp-29 -- mix test --only policy_replay)
```

The tests assert default VCR redaction, explicit full-session payload capture,
direct replay, protected API behavior, and file-backed receipt persistence.

## Track 4: Fork From Receipt

### Plan

The workbench should expose receipts and saved scenarios as starting points for
controlled replay. A fork starts from recorded evidence, lets the operator edit
the deterministic policy or turn fields, and labels the result as replay or
fork evidence instead of source of truth.

### Adversarial Plan Review

The workbench UI must remain a projection. It can offer affordances for replay
and forking, but it must not become the authoritative store for policy
behavior. The backend receipt/scenario/replay contracts own the replay data.

### Implementation Notes

Added a reusable Lustre control-debugger component in
`wardwright/lustre_control_debugger.gleam`. The component exposes:

- receipt selection from recent receipt summaries plus a controlled receipt-id
  input for pasted ids
- policy projection selection
- import-as-scenario action backed by
  `PolicyScenarioStore.create_from_receipt/3`
- VCR replay action backed by `Wardwright.PolicyReplay`
- richer replay facts: recording mode, original provider behavior, replay
  provider behavior, route, policy actions, request shape, selected model, and
  warnings
- session-trace loading for full-session receipts, including event cursors,
  suggested fork points, recorded tool calls/results, and replay-to-cursor
  without a provider call
- fork/continue controls with editable policy overlay JSON
- an explicit continuation mode: deterministic scripted continuation for CI
  evidence, or Wardwright-model continuation through `/v1/chat/completions`
  with native OpenAI-style tool-call history where the recorded trace can be
  represented that way, and with the new receipt recorded into the fork trace

To avoid colliding with the in-flight authoring-agent workbench PR, the
component is mounted today as a separate admin page at
`/admin?view=control_debugger`. It exports `panel(model)` separately from
`workspace(model)`, so the same panel can later be embedded in the main
workbench or authoring-agent area without moving backend logic.

### Adversarial Implementation And Design Review

This is still not a complete time-travel debugger. Importing a receipt creates
replay evidence and pinned scenario material; replaying a receipt explains
stored facts without resuming a provider. Fork continuation can now call a
configured Wardwright model, but that only proves the gateway continuation
contract. It does not yet reconnect a real external agent process with all of
its tool state.

The component uses a new Elixir data boundary instead of reaching directly into
stores from arbitrary UI code. That makes the component movable, but it also
means the boundary must stay strict about redaction and avoid growing into a
general receipt browser.

### Test Evidence

Focused evidence:

```text
(cd app && mise exec --command 'mix test --no-deps-check test/workbench_test.exs')
```

The workbench tests cover the separate admin route, server-component transport,
controlled receipt input, receipt import into saved replay evidence, and
debugger replay facts. The current focused suite also covers the
counterfactual debugger path: record a scripted example session, load
the session trace, replay to fork point with no provider call, fork/continue
deterministically, validate overlay JSON, and continue a fork through a
configured Wardwright model with a new provider receipt. The configured model in
the default suite is canned, so this proves gateway plumbing and structured
history shape rather than real-provider behavioral equivalence. The examples
cover both read-before-edit tool ordering and output-contract repair so the
debugger is not coupled to one unsafe-tool-call case.

## Track 5: Distilled Failure Scenarios

### Plan

Forge, Statewright, and the Hacker News discussion identify repeatable failure
families worth turning into Wardwright examples:

- no-result-is-not-tool-failure
- read-before-edit
- oversized-diff rejection
- malformed tool-call retry
- context-compaction breakpoint
- leading canary sentinel

This slice keeps the examples as public, synthetic policy-scenario fixtures for
the existing `tool-governance` projection. The fixture pack should exercise the
scenario-store and regression-export contracts without adding enforcement logic:

- `no-result-is-not-tool-failure` records a successful tool call whose result
  count is zero.
- `read-before-edit` records the requirement that a write-class patch plan has
  prior path-read evidence.
- `oversized-diff-rejection` records a diff-budget block or review requirement.
- `malformed-tool-call-retry` records one schema-feedback retry before tool-call
  exhaustion.
- `context-compaction-breakpoint` records the need for a compact checkpoint
  before continuing write-class work near the context limit.
- `leading-canary-sentinel` records that a leading sentinel remains visible
  before tool planning proceeds.

### Adversarial Plan Review

Examples are only useful if they encode behavior Wardwright can actually
observe or enforce. Each scenario should state whether it is currently enforced,
replayed as evidence, or a roadmap fixture for a not-yet-shipped policy.

The narrow risk is laundering wishlist behavior into tests that look like
enforcement. To avoid that, these scenarios are fixture evidence only. The test
should prove they load, replace demo simulations, and export as pinned
regression evidence; it should not assert that streaming, allowed-tools
enforcement, replay, or provider transport already implement the policies.

The public-repo risk is accidentally preserving real user, provider, or
deployment content while distilling examples from outside systems. The fixture
text therefore uses synthetic tool names, `example`-style model ids, and no raw
provider payloads, credentials, private endpoints, or captured prompts.

### Implementation Notes

Added `app/test/fixtures/policy_scenarios/control_layer_scenarios.json` with six
pinned `tool-governance` scenarios. Each scenario uses `source: fixture`,
`pattern_id: tool-governance`, public synthetic turn data, a small trace with
the valid `active` state, and a receipt preview that names the intended control
outcome.

Added `Wardwright.PolicyScenarioFixtureTest` to load the fixture pack through
`PolicyScenarioStore.configure_storage/1`, confirm simulations prefer persisted
scenario evidence over built-in demo evidence, export the pinned pack, and
compile the generated ExUnit regression source.

### Adversarial Implementation And Design Review

The fixture names are intentionally behavior-oriented, but the implementation is
still a documentation/evidence slice. It does not add enforcement paths for
allowed tools, write gating, stream handling, replay, or tool-call repair. That
keeps ownership clean for this worker, but downstream reviewers must not treat
these examples as shipped controls.

The test is capable of failing on meaningful fixture regressions: invalid JSON,
unknown pattern ids, missing required scenario fields, bad trace states,
unpinned records, changed export semantics, or projection code that stops
preferring persisted scenarios will break it. It is not a deep policy test, and
that is deliberate; real enforcement tests should live with the owning control
layer once those controls exist.

### Test Evidence

Focused evidence for this slice passed:

```text
(cd app && mise exec --command 'mix test --no-deps-check test/policy_scenario_fixture_test.exs')
```

Full app validation also passed after integration:

```text
(cd app && mise exec --command 'mix test --no-deps-check')
```

## Track 6: Agent-Operable Control Debugger

### Plan

The Control Debugger loop should be usable by an assisting agent without
scraping the UI. The first MCP/API parity slice should expose the same
read-before-edit family the UI already proves: list built-in examples, record a
scripted example, load trace events by receipt or session id, replay to a
cursor without a provider call, fork from a cursor with deterministic scripted
continuation, and save selected trace evidence as a simulator case.

### Adversarial Plan Review

The risk is creating an agent-only control path that does not match the UI, or
claiming more safety than the trace evidence supports. Write-capable tools must
say what they write. Replay must remain provider-free. Fork/continue should use
the deterministic scripted runner unless a separate live-provider proof is
explicitly requested.

### Implementation Notes

`WardwrightWeb.ControlDebuggerTools` now wraps the existing Control Debugger
backend operations in structured payloads. Protected HTTP endpoints live under
`/v1/policy-authoring/control-debugger/...`, and Hermes MCP tools expose the
same controls:

- `list_control_debugger_examples`
- `record_control_debugger_example`
- `load_control_debugger_trace`
- `replay_control_debugger_cursor`
- `fork_control_debugger_cursor`
- `save_control_debugger_evidence`

`wardwright tools` and `wardwright tools --json` advertise the new API controls
with method, path, when-to-use guidance, and safety notes. Read-only MCP tools
are annotated read-only; recording, forking, and saving are intentionally
write-capable. The MCP fork tool uses deterministic scripted continuation and
reports `provider_called=false`.

### Adversarial Implementation And Design Review

The slice deliberately avoids live model continuation over MCP. That keeps the
agent-operable path deterministic and prevents an MCP caller from accidentally
turning a replay proof into a provider call. The evidence-save API stores the
selected trace prefix as a pinned simulator case; it preserves cursor/session
metadata but does not pretend that the simulator case is the policy source of
truth.

### Test Evidence

Focused coverage:

```text
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/mcp_authoring_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/public_api_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/cli_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs
```

The MCP and HTTP tests run the read-before-edit loop through non-UI controls and
assert agreement on receipt id, trace cursor, provider-free replay, accepted
deterministic fork, applied rule id, and saved `tool-governance` scenario.

## Manual Experiments

### Browser-Controlled Debugger

The new Lustre debugger page was exercised against a live local server on an
alternate port with test configuration enabled. The manual flow:

1. installed a toy `allowed_tools` policy where a browser read moves the
   session into `reviewing_tool_result`
2. simulated a blocked shell write in that state
3. replayed the blocked receipt through
   `POST /v1/policy-authoring/replay-receipts/:receipt_id`
4. imported the receipt as pinned `live_replay` scenario evidence
5. drove `/admin?view=control_debugger` in the browser to select the receipt,
   replay it, and import it from the UI

That run verified the important behavior: the debugger can turn a real receipt
into replay evidence without resuming a provider call.

The browser run also found a real polish bug: the select controls had visible
labels, but label-based automation could not resolve the "Recent receipt"
control. The reusable select helper now adds an explicit `aria-label`, and the
control-debugger tests assert that accessibility contract.

### OpenCode Client Run

OpenCode was configured as a real OpenAI-compatible client against
Wardwright's `/v1` proxy using a local custom provider:

```json
{
  "provider": {
    "wardwright": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8794/v1",
        "apiKey": "wardwright-local"
      },
      "models": {
        "unit-model": {}
      }
    }
  },
  "model": "wardwright/unit-model"
}
```

The first run intentionally used an allowlist with an `opencode.*` namespace.
That failed closed and exposed an important integration detail: OpenCode sends
its tools as OpenAI function tools. Wardwright observed declared tools named
`read`, `glob`, `grep`, `task`, `webfetch`, `todowrite`, and `skill` under the
`openai.function` namespace. After updating the test allowlist to those
observed declared tools, this command completed through Wardwright:

```text
opencode run --dir tmp/manual-opencode-wardwright \
  --model wardwright/unit-model \
  --format json \
  'Tiny sanity task: what is 2+2? Answer briefly.'
```

The successful receipt recorded:

- `status: completed`
- `stream: true`
- `tool_phase: planning`
- `selected_model: canned/opencode-agent`
- `vcr.schema: wardwright.policy_vcr.v0`
- metadata-only request facts, including message roles and lengths rather than
  raw prompt text

The failed run was equally useful: `allowed_tools` can block a real agent
client before any provider call, but naive namespace assumptions will make the
policy too brittle. Public examples should teach policy authors to allow
OpenAI-compatible declared tools by their normalized `openai.function` names,
or to add an adapter that maps a client-specific namespace before policy
evaluation.

### Discussion-Derived Follow-Ups

The Forge discussion reinforced that the real overlap is proxy/middleware
control for local or small models. The useful gap for Wardwright is not "retry
nudges, but again"; it is trace-driven dynamic policy:

- turn observed tool declarations and receipt outcomes into explicit
  first-class policy refinements
- record small-model failures as replayable metadata and pinned scenarios
- support task-shape-aware compaction triggers, where runtime pressure and a
  model-emitted natural breakpoint both have to agree before compaction fires
- keep argument/result payloads redacted by default while still recording
  enough hashes, tool names, phases, and statuses to debug behavior

That compaction idea matters because Forge's current public framing is still
mostly static threshold/tier based. Wardwright can add value if it learns from
real traces and lets operators express dynamic policies such as "compact only
after tests pass and the active branch is done" instead of only "compact after
N tokens."
