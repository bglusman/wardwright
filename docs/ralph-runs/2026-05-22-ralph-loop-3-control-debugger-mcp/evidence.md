---
title: Ralph Loop 3 Evidence - Control Debugger MCP/API Parity
---

# Evidence

## Commands Run

```sh
git status --short --branch
sed -n '1,240p' docs/agent-control-debugger.md
sed -n '1,240p' docs/ralph-runs/2026-05-22-read-before-edit-followups/README.md
sed -n '1,260p' docs/ralph-runs/2026-05-22-read-before-edit-followups/evidence.md
sed -n '1,260p' docs/ralph-runs/2026-05-22-read-before-edit-followups/followups.yml
mise trust /Users/admin/projects/wardwright.ralph-loop-3/mise.toml
cd app && MIX_ENV=test mise exec -- mix deps.get
cd app && MIX_ENV=test mise exec -- mix compile --warnings-as-errors
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/mcp_authoring_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/public_api_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/cli_test.exs
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs
WARDWRIGHT_BIND=127.0.0.1:8813 ... mise exec -- mix phx.server
node <inline CDP browser driver for Control Debugger screenshots>
node <inline MCP tools/list and HTTP Control Debugger execution evidence>
cd app && MIX_ENV=test mise exec -- mix run --no-compile --no-start -e 'Wardwright.CLI.run(["tools"], &IO.puts/1)'
cd app && MIX_ENV=test mise exec -- mix run --no-compile --no-start -e 'Wardwright.CLI.run(["tools", "--json"], &IO.puts/1)'
opencode --help
opencode import --help
```

The first parallel run of `test/workbench_test.exs` failed one test while
multiple focused suites were concurrently compiling the same build directory.
The suite passed on immediate sequential rerun: 57 tests passed.

## UI Proof

Screenshots captured through headless Chrome/CDP:

- `screenshots/01-ui-recorded-selected-trace.png`
- `screenshots/02-ui-replay-no-provider.png`
- `screenshots/03-ui-fork-comparison.png`
- `screenshots/04-ui-save-scenario-tool-governance.png`

`ui-control-debugger-text.txt` includes the key visible UI states:

```text
Violation: edit_file ran before read_file for app.txt. Suggested fork point: before mutating app.txt.
Replayed to selected fork point without calling a provider.
Forked from selected point, applied policy overlay, and continued.
Open Workbench, choose tool-governance, then choose the saved scenario.
```

## MCP Proof

`mcp-control-debugger-tools.json` was captured from the live MCP
`tools/list` flow. It includes:

```text
fork_control_debugger_cursor
list_control_debugger_examples
load_control_debugger_trace
record_control_debugger_example
replay_control_debugger_cursor
save_control_debugger_evidence
```

Read-only annotations are present for:

```text
list_control_debugger_examples
load_control_debugger_trace
replay_control_debugger_cursor
```

The input schemas require the expected cursor/session fields. For example,
`replay_control_debugger_cursor` requires `session_id` and `trace_cursor`;
`save_control_debugger_evidence` requires `pattern_id`, `session_id`, and
`trace_cursor`.

## HTTP Proof

`http-control-debugger-loop.json` records a successful protected HTTP path:

```text
receipt: rcpt_41e6ee7522bc3d92
session: session_214276_1779471901871
cursor: session_214276_1779471901871:5
replay provider_called: false
fork applied rule: http-read-before-edit
saved pattern: tool-governance
saved scenario: trace-mQWMgURaiMwbudXX
```

The loaded trace includes the selected event cursor and the violation
recommendation. Replay stops before the selected cursor without a provider call.
Fork/continue uses deterministic scripted continuation and returns an accepted
comparison. Save evidence creates a pinned `live_replay` simulator case.

## CLI Proof

`cli-tools-help.txt` and `cli-tools.json` advertise:

```text
list_control_debugger_examples
record_control_debugger_example
load_control_debugger_trace
replay_control_debugger_cursor
fork_control_debugger_cursor
save_control_debugger_evidence
```

Each entry includes method, path, when-to-use guidance, safety text, and docs
URL through `PolicyAuthoringTools`.

## RBE-002 Status

`opencode-help.txt` confirms the local OpenCode install exposes `import`,
`export`, `--session`, and `--fork` surfaces. `opencode-import-help.txt`
confirms import accepts a JSON file or URL. This is not enough to close
`RALPH-RBE-002`: no native resumed live-agent execution with preserved hidden
state and tool-result state was proven in this run.

## Validation Results

```text
cd app && MIX_ENV=test mise exec -- mix compile --warnings-as-errors: passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/mcp_authoring_test.exs: 12 passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/public_api_test.exs: 24 passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/cli_test.exs: 10 passed
cd app && MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs: 57 passed on sequential rerun
mise check: passed
```

## Adversarial Review

Architecture: the new MCP/HTTP surface delegates to `ControlDebuggerData` and
`CounterfactualReplay` instead of inventing a second replay engine. That keeps
UI and non-UI behavior aligned. The main architectural debt is that
`ControlDebuggerData` still owns both UI tuple helpers and backend operations;
`ControlDebuggerTools` is a pragmatic wrapper, not a full boundary cleanup.

Security: write-capable operations are not marked read-only. MCP replay/list/load
are read-only. MCP fork uses deterministic scripted continuation and does not
accept a live model id or API key, reducing accidental provider calls. Saved
trace evidence can still contain sensitive metadata, so CLI/tool safety text
and the run docs explicitly warn that exported scenario packs need review.

Code quality/comments: the new wrapper is intentionally explicit and
boring. There is some duplication in event summaries and route error handling;
that is acceptable for this narrow slice, but a future larger Control Debugger
API should consolidate trace projection helpers instead of copying labels.

Test quality: the new tests are capable of failing if tool registration,
schemas, API routes, provider-free replay, deterministic fork, or scenario-save
wiring break. They assert public behavior and cross-surface agreement, not
private function structure. The browser proof exercises actual UI buttons and
captures screenshots, while the existing workbench suite protects the prior UI
path.

Residual risk: `RALPH-RBE-005` is closed for the deterministic read-before-edit
Ralph loop, not for live-provider fork continuation through MCP. `RALPH-RBE-002`
remains open because OpenCode native resume fidelity was not proven.
