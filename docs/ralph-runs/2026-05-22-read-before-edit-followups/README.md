---
title: Ralph Followup Loop - Read Before Edit Evidence Clarity
---

# Ralph Followup Loop: read-before-edit-followups

## Scenario

This followup run continued the read-before-edit Ralph loop from
`docs/ralph-runs/2026-05-22-read-before-edit-tool-misuse`. The target behavior
was a full-session trace where an agent called `edit_file` for `app.txt` before
any `read_file` for that path.

The primary UI defect was that the selected trace event made the operator infer
the violation from the surrounding event sequence. The event copy now states the
exact failure:

`Violation: edit_file ran before read_file for app.txt. Suggested fork point: before mutating app.txt.`

## Environment

- Worktree: `/Users/admin/projects/wardwright.ralph-loop-2`
- Branch: `codex/ralph-loop-followups-1`
- Main local UI URL: `http://127.0.0.1:8798/admin?view=control_debugger`
- Fresh storage-note UI URL: `http://127.0.0.1:8799/admin?view=control_debugger`
- Demo/model source: built-in `read-before-edit` counterfactual example using
  `counterfactual-ui-demo`
- Continuation source: deterministic scripted continuation; no paid provider
  call was needed for the UI proof

## Followups Attempted

- `RALPH-RBE-001`: closed. The selected unsafe edit event now states the exact
  violation in plain language.
- `RALPH-RBE-002`: remains open. Wardwright can export an OpenCode handoff and
  now exposes adapter fidelity through CLI/MCP, but native OpenCode resume with
  preserved private agent/tool state was not proven and was not claimed.
- `RALPH-RBE-003`: closed. Memory-only simulator storage now tells the operator
  exactly how to enable durable scenario storage with
  `WARDWRIGHT_POLICY_SCENARIO_STORE_FILE`; the CLI help advertises the same
  variable.
- `RALPH-RBE-004`: closed. Browser smoke now records the read-before-edit
  example and verifies the control-debugger save path points to
  `tool-governance`.

## UI Path

1. Opened `/admin?view=control_debugger`.
2. Clicked `Record example session` for the built-in read-before-edit example.
3. Selected `#5 Tool call: edit_file`.
4. Captured the before state showing only `Suggested fork point: before
   mutating app.txt.`
5. Updated the trace projection copy to track prior `read_file` calls and name
   missing reads at unsafe `edit_file` events.
6. Re-ran the UI path and captured the selected event with the exact violation
   sentence.
7. Re-ran the save path and confirmed the saved scenario points to
   `tool-governance`.
8. Restarted a fresh server without
   `WARDWRIGHT_POLICY_SCENARIO_STORE_FILE` and confirmed the UI explains how to
   enable durable simulator storage.

## MCP And CLI Symmetry

The loop improved non-UI discoverability for the same investigation family:

- `wardwright tools` and `wardwright tools --json` list replay and harness
  export controls with method, path, when-to-use guidance, and safety notes.
- MCP now exposes `replay_receipt_policy`, `list_harness_adapters`, and
  `export_agent_harness_trace`.
- The MCP tool components expose read-only annotations and explicit input
  schemas for receipt replay and harness export.

One symmetry gap remains: MCP still does not have first-class controls for
recording a built-in counterfactual example, selecting a trace cursor, forking,
and saving the selected trace as a simulator case. That is filed as
`RALPH-RBE-005` in this run.

## Screenshots

- `screenshots/01-before-rbe001-selected-event.png`: before copy; selected
  `edit_file` event did not state the exact violation.
- `screenshots/02-after-rbe001-selected-event.png`: after copy; selected
  `edit_file` event states the exact read-before-edit violation.
- `screenshots/03-storage-note-env-hint.png`: memory-only simulator storage
  hint names `WARDWRIGHT_POLICY_SCENARIO_STORE_FILE`.
- `screenshots/04-save-scenario-result.png`: browser path saved the scenario
  and pointed the operator to `tool-governance`.

## Final Result

The UI, CLI, MCP, focused tests, and browser smoke now agree on the core result:
the selected unsafe event is an `edit_file` for `app.txt` with no earlier
`read_file` for `app.txt`; replay remains provider-free; saved evidence belongs
to the `tool-governance` policy pattern; and OpenCode handoff is only
best-effort unless a future run proves equivalent native resume.
