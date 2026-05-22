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
- Additional loops completed: 3.
- Additional loops remaining: 7.

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

## Open Followup

### RALPH-RBE-002

OpenCode import/resume is still unproven as native resumed live-agent execution
with preserved hidden/tool state. OpenCode exposes `import`, `--session`, and
`--fork`, but the Ralph loop should not claim equivalent live-agent resume until
a future cycle runs a real import/resume trial and verifies state fidelity.

## Closed Followups

### RALPH-RBE-005

Closed by `a434531`. MCP, protected HTTP, CLI, and UI now expose the same
Control Debugger read-before-edit investigation family. Replay remains
provider-free, and deterministic fork continuation intentionally does not
claim live-provider execution.
