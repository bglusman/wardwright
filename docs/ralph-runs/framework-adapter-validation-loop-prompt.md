---
title: Framework Adapter Validation Ralph Loop Prompt
---

# Framework Adapter Validation Ralph Loop Prompt

You are continuing the Wardwright framework adapter validation Ralph loop.

## Required Context

Read these files before editing:

- `AGENTS.md`
- `CLAUDE.md`
- `docs/architecture-ratchets.md`
- `docs/testing-ratchets.md`
- `docs/agent-adapters.md`
- `docs/ralph-runs/adapter-framework-priority-review.md`
- `docs/ralph-runs/framework-adapter-validation-requirements.md`
- `docs/ralph-runs/framework-adapter-validation-loop-supervisor.md`

## Loop Contract

Perform one coherent implementation loop only.

1. Check branch and worktree state. Continue on `codex/pi-replay-spike`.
2. Pick the highest-priority unfinished requirement from the supervisor
   backlog.
3. Implement a narrow, reviewable slice.
4. Keep framework SDK integrations separate from local coding-agent adapters.
   OpenCode and OpenClaw are distinct first-class local surfaces.
5. Prefer typed Gleam for pure adapter decision and fidelity logic. Keep
   impure filesystem, process, HTTP, JSON, package-manager, and Phoenix
   boundaries in Elixir or scripts.
6. Add behavior-focused tests or smoke checks that would fail for the missing
   product behavior under review. Avoid tests that only lock in private
   implementation details.
7. Update
   `docs/ralph-runs/framework-adapter-validation-loop-supervisor.md` with:
   loop number, timestamp, starting commit, intended ending commit if known,
   scope, validation, skipped probes, and next open item.
8. Run focused validation needed for the slice, plus formatting/docs checks
   when touched.
9. Commit the slice with a descriptive message and let repository hooks run.
10. After committing, conduct an adversarial review of the committed changes.
   Record architecture concerns, code/comment quality, and test quality in the
   supervisor. If the review record changes the supervisor, amend or add a
   follow-up documentation commit before pushing. Fix blockers before ending
   the loop.
11. Push the branch.

Do not open a new pull request. Do not claim stronger adapter, framework state,
or replay fidelity than tests prove.

## Completion

If all exit criteria in
`docs/ralph-runs/framework-adapter-validation-requirements.md` are complete,
validated, and recorded in the supervisor:

1. Mark the supervisor status as complete.
2. Run a final documentation pass. Confirm the docs accurately cover
   framework tiers, provenance metadata, receipt-id propagation, smoke-test
   evidence, local coding-agent separation, fallback behavior, privacy, and
   fidelity limits.
3. Run and record `mise run check:docs`.
4. Commit and push the final supervisor/docs update.
5. Create the local sentinel file:
   `$(git rev-parse --git-path ralph-runs/framework-adapter-validation/complete)`.
6. Push the final branch state if the sentinel creation exposed any final
   branch-state issue. The sentinel itself is local git metadata and is not a
   committed repo file.

If the loop cannot make progress, record the blocker and stop without touching
the completion sentinel.
