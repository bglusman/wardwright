---
title: Ralph Loop 3 - Control Debugger MCP/API Parity
---

# Ralph Loop 3: Control Debugger MCP/API Parity

## Scenario

This run continued the read-before-edit Ralph followup queue from
`docs/ralph-runs/2026-05-22-read-before-edit-followups`.

The main target was `RALPH-RBE-005`: make the full Control Debugger
read-before-edit investigation operable from MCP and protected HTTP APIs, not
only from the UI.

## Environment

- Worktree: `/Users/admin/projects/wardwright.ralph-loop-3`
- Branch: `codex/ralph-loop-followups-2`
- UI proof URL: `http://127.0.0.1:8813/admin?view=control_debugger`
- Isolated receipt store: `/tmp/wardwright-ralph-loop-3/receipts`
- Isolated transcript store: `/tmp/wardwright-ralph-loop-3/transcripts`
- Isolated scenario store: `/tmp/wardwright-ralph-loop-3/scenarios.json`

## Result

- `RALPH-RBE-005`: closed. MCP, HTTP, CLI, and UI now expose the same
  read-before-edit investigation family.
- `RALPH-RBE-002`: open. OpenCode has `import`, `--session`, and `--fork`
  surfaces installed locally, but native resumed live-agent execution with
  preserved hidden/tool state was not proven.

## New Non-UI Controls

- `list_control_debugger_examples`
- `record_control_debugger_example`
- `load_control_debugger_trace`
- `replay_control_debugger_cursor`
- `fork_control_debugger_cursor`
- `save_control_debugger_evidence`

The MCP replay/list/load tools are read-only. Recording, forking, and saving are
write-capable because they create local receipt, transcript, fork, or simulator
evidence. The MCP fork path uses deterministic scripted continuation and reports
`provider_called=false`.

## Evidence Files

- `mcp-control-debugger-tools.json`: MCP tool names, input schemas, and
  annotations from `tools/list`.
- `http-control-debugger-loop.json`: protected HTTP execution path for record,
  load, replay, fork, and save.
- `cli-tools-help.txt` and `cli-tools.json`: shell-discoverable CLI surfaces.
- `ui-control-debugger-text.txt`: browser-captured UI text after the save path.
- `opencode-help.txt` and `opencode-import-help.txt`: RBE-002 status evidence.
- `screenshots/01-ui-recorded-selected-trace.png`
- `screenshots/02-ui-replay-no-provider.png`
- `screenshots/03-ui-fork-comparison.png`
- `screenshots/04-ui-save-scenario-tool-governance.png`

## Cross-Check

The UI and non-UI evidence agree on the same investigation shape:

- scenario: built-in `read-before-edit`
- receipt: `rcpt_41e6ee7522bc3d92` in the HTTP proof
- session: `session_214276_1779471901871` in the HTTP proof
- selected trace cursor: `session_214276_1779471901871:5`
- selected event: `Tool call: edit_file`
- replay: provider-free, `provider_called=false`
- fork: deterministic scripted continuation, accepted comparison
- saved evidence destination: `tool-governance`

The UI proof used a separate browser session and produced equivalent visible
state: selected unsafe edit, replay with no provider call, accepted fork, and
saved `tool-governance` scenario.
