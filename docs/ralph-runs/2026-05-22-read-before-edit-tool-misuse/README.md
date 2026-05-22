---
title: Ralph UI Loop Pilot - Read Before Edit Tool Misuse
---

# Ralph UI Loop Pilot: read-before-edit-tool-misuse

## Scenario

Failure mode: an agent attempts `edit_file` before reading the target file. The pilot used Wardwright's Control Debugger UI to record a built-in read-before-edit counterfactual example, inspect the trace, replay to the unsafe edit point, fork with a policy overlay, continue deterministically, and save the receipt as simulator evidence.

## Environment

- Worktree: `/Users/admin/projects/wardwright.ralph-pilot-1`
- Branch: `codex/ralph-ui-loop-pilot-1`
- Server URL: `http://127.0.0.1:8797/admin?view=control_debugger`
- Demo/model source: built-in `read-before-edit` counterfactual example using `counterfactual-ui-demo`
- Continuation source: deterministic scripted continuation, not a remote paid provider
- Harness path: OpenCode handoff export was exercised from the UI; no native OpenCode live-agent resume was run

## UI Path

1. Opened `/admin?view=control_debugger`.
2. Selected the `Read before edit - tool-order failure` example.
3. Clicked `Record example session`.
4. Inspected the session trace and selected `#5 Tool call: edit_file`.
5. Clicked `Replay to fork point`, confirming no provider call.
6. Clicked `Fork and continue`, confirming the fork passed with applied rule `read-before-edit`.
7. Clicked `Prepare harness handoff`, confirming OpenCode export with best-effort fidelity warning.
8. Clicked `Save scenario` and observed a UI mismatch: the read-before-edit receipt was saved under `tts-retry`.
9. Fixed the example-to-Workbench-pattern mapping.
10. Re-ran the UI path and confirmed the saved scenario now points to `tool-governance`.

## Failure Observed

The core scenario was observable through the UI: the trace showed `list_files`, then `edit_file` on `app.txt`, without a prior `read_file` for the edited path. The original session status was `failed`; the forked session status was `passed`; comparison was accepted; applied rules included `read-before-edit`.

The UI friction found during the pilot was that the `Create simulator case` card defaulted to the first Workbench pattern, `Time-travel stream retry`, after recording a read-before-edit failure. Saving from that state told the operator to open `tts-retry`, which is the wrong place for tool-governance evidence.

## Changes Made

- Added `WardwrightWeb.ControlDebuggerData.default_pattern_id_for_example/1`.
- Updated the Lustre Control Debugger model so selecting or recording a counterfactual example updates the Workbench pattern picker.
- Added regression coverage that `read-before-edit` targets `tool-governance` and `output-contract` targets `ambiguous-success`.

## Final Verification

Final UI verification passed through the browser after restarting the local server. The UI recorded a fresh read-before-edit session, saved the scenario, and displayed: `Open Workbench, choose tool-governance, then choose the saved scenario.` Replay and fork also succeeded after the fix.

## Remaining Concerns

- The trace still makes the operator infer the precise violation from surrounding facts; it should explicitly summarize "edit_file ran before read_file for app.txt."
- OpenCode was only exercised as a UI handoff export, not as a native resumed live agent.
- The simulator case store was memory-only in this run, despite using an isolated local test environment.
