---
title: Adapter Install Validation Ralph Loop Prompt
---

# Adapter Install Validation Ralph Loop Prompt

You are continuing the Wardwright adapter install validation Ralph loop.

## Required Context

Read these files before editing:

- `AGENTS.md`
- `CLAUDE.md`
- `docs/architecture-ratchets.md`
- `docs/testing-ratchets.md`
- `docs/ralph-runs/adapter-install-validation-requirements.md`
- `docs/ralph-runs/adapter-install-validation-loop-supervisor.md`

## Loop Contract

Perform one coherent implementation loop only.

1. Check branch and worktree state. Continue on `codex/pi-replay-spike`.
2. Pick the highest-priority unfinished requirement from the supervisor
   backlog.
3. Implement a narrow, reviewable slice.
4. Prefer typed Gleam for pure adapter decision logic. Keep impure filesystem,
   process, HTTP, JSON, and Phoenix boundaries in Elixir.
5. Add behavior-focused tests that would fail for the bug or missing product
   behavior under review. Avoid tests that only lock in private implementation
   details.
6. Run the focused validation needed for the slice, plus formatting/docs checks
   when touched.
7. Commit the slice with a descriptive message and let repository hooks run.
8. After committing, conduct an adversarial review of the committed changes.
   Record architecture concerns, code/comment quality, and test quality in the
   supervisor. Fix blockers before ending the loop.
9. Push the branch.
10. Update
    `docs/ralph-runs/adapter-install-validation-loop-supervisor.md` with:
    loop number, timestamp, starting commit, ending commit, scope, validation,
    adversarial review, skipped probes, and next open item.

Do not open a new pull request. Do not claim stronger adapter or replay
fidelity than tests prove.

## Completion

If all exit criteria in
`docs/ralph-runs/adapter-install-validation-requirements.md` are complete,
validated, and recorded in the supervisor:

1. Mark the supervisor status as complete.
2. Create the local sentinel file:
   `$(git rev-parse --git-path ralph-runs/adapter-install-validation/complete)`
3. Push the final branch state.

If the loop cannot make progress, record the blocker and stop without touching
the completion sentinel.
