---
title: Adapter Install Validation Ralph Loop Supervisor
---

# Adapter Install Validation Ralph Loop Supervisor

This file is the durable tracker for the adapter install and validation Ralph
loop. The build target is
[`adapter-install-validation-requirements.md`](adapter-install-validation-requirements.html).

## Branch Policy

- Continue on `codex/pi-replay-spike` / PR #71.
- Do not create a branch or pull request per loop.
- Prefer one coherent commit per loop, pushed to the existing PR branch.
- Keep raw logs and oversized agent artifacts out of the repo. Commit only
  small reusable docs, tests, source changes, and concise evidence.

## Cadence

- Runner: `scripts/run-adapter-ralph-loop.sh`.
- Interval: 15 minutes between completed iterations.
- Completion sentinel:
  `.git/ralph-runs/adapter-install-validation/complete`.
- The loop should stop only after the exit criteria in the requirements file
  are implemented, validated, and recorded here.

## Requirements Review

The requirements are complete enough to drive implementation. The important
execution constraints for the loop are:

- Build OMP first, because it already has a runtime equivalence probe and a
  concrete project-local install surface.
- Keep OpenCode support runtime-driven: Pi/OMP-backed OpenCode may inherit the
  Pi/OMP adapter, while OpenCode-native must stay lower fidelity.
- Treat Claude Code and OpenClaw as follow-up adapter surfaces unless OMP,
  gateway policy, CLI lifecycle, and OpenCode runtime resolution are already
  green.
- Bias new pure decision logic toward Gleam, especially state classification,
  runtime resolution, install-plan selection, recording-policy decisions, and
  drift classification.
- Keep filesystem, process execution, HTTP, JSON shaping, and Phoenix surfaces
  in Elixir boundary modules.
- Every committed loop must include behavior-focused tests or a clear reason
  why the change is documentation-only.
- After every commit, perform and record an adversarial review covering
  architecture, code quality/comments, and test quality.

## Ordered Backlog

1. Add a typed adapter-domain core for states, runtime resolution, install
   plans, and recording-policy decisions.
2. Add `wardwright adapters list` and `wardwright adapters doctor` with stable
   human and JSON output.
3. Add project-scoped OMP install, drift detection, repair refusal, uninstall,
   and focused CLI tests using temp homes/configs.
4. Wire OMP pairing and gateway adapter identity validation.
5. Connect adapter-scoped auto-recording to verified adapter identity, while
   keeping generic clients manual by default.
6. Extend `probe omp` to invoke the current runtime equivalence probe from the
   packaged CLI path.
7. Add OpenCode runtime resolution and ensure Pi/OMP-backed, OpenCode-native,
   and Codex-backed modes get distinct fidelity labels.
8. Add user-facing install, privacy, cleanup, and fallback docs.
9. Run the release-candidate validation matrix from the requirements file.

## Continuation Log

### Loop 0 - Kickoff

- Timestamp: 2026-05-23T14:58-04:00.
- Starting commit: `81e772e`.
- Scope: reviewed the adapter install validation requirements and created this
  supervisor for the 15-minute Ralph continuation.
- Validation target: future loops should update this log with their commit,
  validation commands, skipped probes, and adversarial review result.
- Current status: ready to start loop 1.
