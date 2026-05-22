---
title: Ralph Loop Supervisor
---

# Ralph Loop Supervisor

This file is the durable, compact tracker for the Ralph read-before-edit
continuation. Keep this file current, but do not commit raw per-agent artifacts
unless they are small, directly reusable, and more useful than the commit and
validation record below.

## Branch Policy

- Use one continuing integration branch for the Ralph continuation.
- Current integration branch: `codex/ralph-ui-loop-pilot-1` / PR #70.
- Do not create a branch or pull request per loop.
- Prefer one coherent commit per loop, pushed to the integration branch.
- Update the existing PR/comment stream instead of opening a new PR unless the
  user asks for a split.

## Loop Budget

- Historical loops completed before this tracker: 3.
- Additional heartbeat continuation budget: 10 loops.
- Additional loops completed: 6.
- Additional loops remaining: 4.

## Historical Baseline

| Loop | Commit | Result |
| --- | --- | --- |
| 1 | `f8a1637` | Ran the first read-before-edit Control Debugger UI pilot. Found that saving read-before-edit evidence pointed operators at the wrong Workbench pattern. |
| 2 | `851d4f5` | Made selected unsafe `edit_file` events state the exact read-before-edit violation and exposed replay/harness handoff controls through CLI/MCP. |
| 3 | `a434531` | Added first-class Control Debugger MCP and protected HTTP trace controls: list examples, record examples, load traces, replay to cursor, fork, and save evidence. |

## Continuation Log

### Loop 4 - Artifact Consolidation

- Timestamp: 2026-05-22T22:11Z heartbeat.
- Starting commit: `a434531`.
- Ending commit: this supervisor consolidation commit on
  `codex/ralph-ui-loop-pilot-1`.
- Scope: collapsed noisy Ralph run directories into this compact supervisor log
  after sanity review.
- Sanity review:
  - The deleted artifacts were screenshots, raw CLI/MCP/HTTP captures, and
    long browser text dumps that duplicated the branch commits and tests.
  - Useful conclusions were retained in this tracker: branch policy, loop
    budget, closed `RALPH-RBE-005`, and open `RALPH-RBE-002`.
  - Local fetch was repaired by replacing stale branch-specific fetch refspecs
    with the normal `+refs/heads/*:refs/remotes/origin/*` refspec.
- Validation:
  - `mise run check:docs`: passed.
  - Commit hook docs and staged-secret checks: passed.
- Adversarial review:
  - Main risk is losing detailed visual evidence. That is acceptable for this
    branch because the evidence was oversized and not useful to the product
    review loop; reproducible tests and commits are the stronger evidence.

### Loop 5 - Harness Fidelity Verification Status

- Timestamp: 2026-05-22T22:41Z heartbeat.
- Starting commit: `d6b1bb2`.
- Ending commit: this harness verification status commit on
  `codex/ralph-ui-loop-pilot-1`.
- Scope: made `RALPH-RBE-002` operational by exposing a machine-readable resume
  claim status and state-fidelity verification checklist on harness adapters.
- Validation:
  - `mise run check:docs`: passed.
  - `cd app && MIX_ENV=test mise exec -- mix test`: passed, 393 tests with
    21 properties and 6 excluded live/acceptance tests.
- Adversarial review:
  - This does not close `RALPH-RBE-002`; it deliberately prevents accidental
    closure by making the missing proof explicit across UI, MCP, and exported
    adapter payloads.

### Loop 6 - Harness State-Fidelity Probe

- Timestamp: 2026-05-22T23:06Z heartbeat.
- Starting commit: `0f16020`.
- Ending commit: this state-fidelity probe commit on
  `codex/ralph-ui-loop-pilot-1`.
- Scope: added an executable `state_fidelity_probe` to harness exports, with
  trace and tool-result fingerprints plus pass conditions for the eventual
  OpenCode import/resume fidelity trial. The push gate also exposed persistent
  transcript-store leakage between Mix invocations, so the loop isolated
  `RouterCase` transcript storage per test before pushing.
- Validation:
  - `mise run check:docs`: passed.
  - `cd app && MIX_ENV=test mise exec -- mix test`: passed, 393 tests with
    21 properties and 6 excluded live/acceptance tests.
- Adversarial review:
  - This still does not close `RALPH-RBE-002`; it turns the next proof step
    from prose into a concrete sidecar artifact that a harness trial can
    inspect. The risk is another export field, but it is scoped to harness
    evidence and covered across direct export and MCP tests. The RouterCase
  isolation fix reduces cross-run state coupling without changing production
  transcript behavior.

### Loop 7 - Harness State-Fidelity Verification

- Timestamp: 2026-05-22T23:21Z heartbeat.
- Starting commit: `0b72e77`.
- Ending commit: this state-fidelity verification commit on
  `codex/ralph-ui-loop-pilot-1`.
- Scope: added a protected API and MCP tool to compare an exported
  `state_fidelity_probe` with observed imported-harness state, including trace
  fingerprint, tool-result fingerprint, and read-before-edit cursor checks.
- Validation:
  - `cd app && MIX_ENV=test mise exec -- mix test`: passed, 395 tests with
    21 properties and 6 excluded live/acceptance tests.
- Adversarial review:
  - This still does not close `RALPH-RBE-002`; it makes the eventual
    OpenCode import/resume trial measurable without claiming hidden-state
    equivalence. The verifier intentionally keeps
    `equivalent_agent_resume_claim_allowed` false even when the concrete probe
    matches, because workspace snapshot and private harness state remain
    unproven.

### Loop 8 - Harness Verification Handoff

- Timestamp: 2026-05-22T23:36Z heartbeat.
- Starting commit: `267eb03`.
- Ending commit: this harness verification handoff commit on
  `codex/ralph-ui-loop-pilot-1`.
- Scope: made the Control Debugger handoff facts name the handoff artifact,
  state-fidelity probe, handoff command, and `verify_harness_state_fidelity`
  follow-up so the new verifier is discoverable from the UI and CLI help path.
- Validation:
  - `cd app && gleam format --check src`: passed.
  - `cd app && gleam check --target erlang`: passed.
  - `cd app && mix format --check-formatted`: passed.
  - `cd app && mix test`: passed, 395 tests with 21 properties and 6 excluded
    live/acceptance tests.
- Adversarial review:
  - This still does not close `RALPH-RBE-002`; it removes a usability gap
    between export and verification. The verifier remains separate and
    conservative, and the UI explicitly keeps equivalent resume claims false.

### Loop 9 - OpenCode Import Trial

- Timestamp: 2026-05-22T19:58-05:00 focused RBE-002 trial.
- Starting commit: `50a2a86`.
- Ending commit: this OpenCode import-trial evidence commit on
  `codex/ralph-ui-loop-pilot-1`.
- Scope: ran a real OpenCode import and forked continuation against a fresh
  Wardwright read-before-edit trace export, with OpenCode configured for
  `forge/forge` backed by `gemma4:26b-a4b-it-q4_K_M`.
- Findings:
  - `opencode import` successfully imported the Wardwright export and created
    session `ses_wwQj1zkBdHxnvqJh4n8JSODMku`.
  - OpenCode stored the imported trace as message text plus normal OpenCode
    step parts, not as native tool-call/tool-result rows. The imported artifact
    itself also contains only `text`, `step-start`, and `step-finish` parts.
  - A forked `opencode run --session ... --fork --model forge/forge` created
    session `ses_1ade18f54ffeGorVGCX6ghMQye` and correctly concluded that
    `edit_file` occurred before any `read_file` of `README.md`.
  - The forked model response identified the failure event cursor rather than
    perfectly normalizing every cursor, so this is useful continuation evidence
    but not exact machine-verification evidence.
  - Running `verify_state_fidelity` against the actual observed imported state
    fails as expected: the imported OpenCode database does not expose the trace
    fingerprint or tool-result fingerprints needed to prove native state
    fidelity.
- Validation:
  - Live OpenCode import and forked run completed with the current
    `gemma4:26b-a4b-it-q4_K_M` configuration.
  - `verify_state_fidelity` returned `status: probe_mismatch` for the observed
    imported state, while the read-before-edit cursor-identification check
    passed.
- Adversarial review:
  - This partially falsifies the stronger RBE-002 interpretation for current
    OpenCode JSON import: it is not native equivalent resume with preserved
    tool state. It does validate the weaker handoff claim: OpenCode can import
    the evidence, fork from it, and reason from it. PR language should keep the
    current best-effort/fidelity-warning framing unless a future adapter can
    export or recover native OpenCode tool-result state.

## Open Followup

### RALPH-RBE-002

OpenCode import/resume is now live-tested as best-effort evidence handoff, but
not as native resumed live-agent execution with preserved hidden/tool state.
OpenCode exposes `import`, `--session`, and `--fork`, and a forked model can
reason from the imported trace. The current import stores Wardwright tool
evidence as text rather than native tool-result state, so the Ralph loop must
not claim equivalent live-agent resume unless a future adapter proves stronger
state fidelity.

## Closed Followups

### RALPH-RBE-005

Closed by `a434531`. MCP, protected HTTP, CLI, and UI now expose the same
Control Debugger read-before-edit investigation family. Replay remains
provider-free, and deterministic fork continuation intentionally does not
claim live-provider execution.
