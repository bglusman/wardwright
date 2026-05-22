---
title: Ralph Followup Evidence - Read Before Edit
---

# Evidence

## Commands Run

```sh
git status --short --branch
sed -n '1,240p' docs/agent-control-debugger.md
sed -n '1,220p' docs/ralph-runs/2026-05-22-read-before-edit-tool-misuse/README.md
sed -n '1,260p' docs/ralph-runs/2026-05-22-read-before-edit-tool-misuse/evidence.md
cat docs/ralph-runs/2026-05-22-read-before-edit-tool-misuse/followups.yml
WARDWRIGHT_BIND=127.0.0.1:8798 ... mise exec -- mix phx.server
node <inline CDP browser driver for before/after screenshots>
MIX_ENV=test mise exec -- mix run --no-compile --no-start -e 'Wardwright.CLI.run(["tools"], &IO.puts/1)'
MIX_ENV=test mise exec -- mix run --no-compile --no-start -e 'Wardwright.CLI.run(["tools", "--json"], &IO.puts/1)'
MIX_ENV=test mise exec -- mix run --no-compile --no-start -e 'IO.inspect selected MCP tool components'
cd app && mise exec -- mix format --check-formatted
cd app && mise exec -- gleam format --check src
cd app && python3 ../scripts/check-lustre-controlled-inputs.py src
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/cli_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/mcp_authoring_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/agent_harness_adapters_test.exs
mise run check:browser
WARDWRIGHT_BIND=127.0.0.1:8799 ... mise exec -- mix phx.server
node <inline CDP browser driver for storage/save screenshots>
mise check
```

The first attempt to capture `wardwright tools --json` immediately after a
fresh compile produced compile logs on stdout before the JSON payload. The
clean evidence files were regenerated with `mix run --no-compile --no-start`
after compilation.

## UI Proof

Before the change, `ui-before-rbe001-text.txt` contained the selected event
copy:

```text
args: path=app.txt
Suggested fork point: before mutating app.txt.
```

After the change, `ui-after-rbe001-text.txt` and
`ui-save-scenario-text.txt` contain:

```text
args: path=app.txt
Violation: edit_file ran before read_file for app.txt. Suggested fork point: before mutating app.txt.
```

The save-path text also shows:

```text
Open Workbench, choose tool-governance, then choose the saved scenario.
```

Screenshots captured:

- `screenshots/01-before-rbe001-selected-event.png`
- `screenshots/02-after-rbe001-selected-event.png`
- `screenshots/03-storage-note-env-hint.png`
- `screenshots/04-save-scenario-result.png`

## MCP Proof

`mcp-tool-names.json` includes:

```json
["export_agent_harness_trace","list_harness_adapters","replay_receipt_policy"]
```

`mcp-tool-components.txt` records the argument shapes and safety annotations.
The relevant schemas are:

```text
export_agent_harness_trace:
  required: session_id, adapter_id
  optional: cwd, title
  annotations: read_only=true

list_harness_adapters:
  required: none
  annotations: read_only=true

replay_receipt_policy:
  required: receipt_id
  annotations: read_only=true
```

`test/mcp_authoring_test.exs` now proves the harness adapter MCP path returns
OpenCode fidelity as `session_import_best_effort`, with
`equivalent_agent_resume` set to false, and that unknown receipt replay fails
closed.

## CLI Proof

`cli-tools-help.txt` and `cli-tools.json` show the shell-discoverable controls
for replay and harness handoff. The relevant CLI JSON entries include:

```text
replay_receipt_policy | POST /v1/policy-authoring/replay-receipts/{receipt_id}
list_harness_adapters | GET /v1/policy-authoring/harness-adapters
export_agent_harness_trace | POST /v1/policy-authoring/harness-adapters/{adapter_id}/export
```

The safety notes explicitly say replay is read-only and never calls a provider,
and that harness export must not be treated as equivalent hidden agent state
unless the adapter says `equivalent_agent_resume` is true.

`wardwright --help` also now advertises:

```text
WARDWRIGHT_TRANSCRIPT_STORE_DIR
WARDWRIGHT_POLICY_SCENARIO_STORE_FILE
```

## Cross-Check

The UI trace, text dumps, browser smoke, CLI, and MCP proof agree on these
facts:

- The unsafe selected event is `#5 Tool call: edit_file`.
- The event arguments include `path=app.txt`.
- No prior `read_file` event exists for `app.txt`.
- Replay to the selected point is provider-free.
- The saved scenario belongs to `tool-governance`.
- OpenCode export is a best-effort handoff and not proof of equivalent native
  resume.

## Validation Results

```text
cd app && mise exec -- mix format --check-formatted: passed
cd app && mise exec -- gleam format --check src: passed
cd app && python3 ../scripts/check-lustre-controlled-inputs.py src: passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs: 57 passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/cli_test.exs: 10 passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/mcp_authoring_test.exs: 11 passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/agent_harness_adapters_test.exs: 7 passed
mise run check:browser: passed, including "ok control debugger saves read-before-edit scenario to tool-governance"
mise check: passed, including 391 app tests/properties, docs/site checks, map-boundary and style ratchets, Assay with total errors 0, and browser smoke
```

Two early combined `mix test` command attempts used the wrong Mix argument
shape and were rejected as unknown dependencies. The tests above were rerun
sequentially with the intended file paths.

## Adversarial Review

Architecture: the exact violation is derived in
`WardwrightWeb.ControlDebuggerData` from recorded trace events rather than from
a UI-only string. That keeps the copy tied to backend projection data. The
implementation is intentionally narrow: it detects `edit_file` before
`read_file` for the same path, not a general symbolic tool-order engine.

Security: the new MCP harness export tool calls `AgentHarnessAdapters.export/3`
and is annotated read-only; it does not write files. Its descriptions and CLI
safety notes preserve the sensitive-trace warning and explicitly avoid claiming
equivalent native agent resume.

Code quality/comments: no broad refactor was made. The read-before-edit state
tracking is a small `MapSet` pass over event summaries. The remaining concern is
that Control Debugger data assembly is growing; a later refactor should split
trace annotation from general UI state assembly if more tool-order rules are
added.

Test quality: the new regression would fail on the original bug because the
original view did not contain the exact violation sentence. The browser smoke
exercises real UI buttons for record and save rather than calling backend
functions directly. MCP tests assert behavior and safety-relevant output, not
private implementation details.

Remaining risk: MCP still cannot perform every Control Debugger UI action as a
first-class operation. That gap is tracked as `RALPH-RBE-005`.
