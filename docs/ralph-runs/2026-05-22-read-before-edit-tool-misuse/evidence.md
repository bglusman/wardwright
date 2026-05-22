---
title: Ralph UI Loop Pilot Evidence - Read Before Edit Tool Misuse
---

# Evidence

## Commands Run

```sh
git status --short --branch
rg -n "read-before|before reading|edit.*read|control debugger|counterfactual|replay|harness|scenario" app docs contracts scripts AGENTS.md README.md
mise exec -- mix deps.get
WARDWRIGHT_BIND=127.0.0.1:8797 WARDWRIGHT_RECEIPT_STORE_DIR=/tmp/wardwright-ralph-pilot-1/receipts WARDWRIGHT_POLICY_SCENARIO_STORE_FILE=/tmp/wardwright-ralph-pilot-1/scenarios/scenarios.json WARDWRIGHT_TRANSCRIPT_STORE_DIR=/tmp/wardwright-ralph-pilot-1/transcripts WARDWRIGHT_SQLITE_STORE=/tmp/wardwright-ralph-pilot-1/sqlite/wardwright.sqlite WARDWRIGHT_ALLOW_TEST_CREDENTIALS=1 mise exec -- mix phx.server
node <inline CDP browser driver>
MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs
mise exec -- gleam format --check src
mise exec -- gleam check --target erlang
python3 scripts/check-lustre-controlled-inputs.py app/src
MIX_ENV=test mise exec -- mix test --no-deps-check
WARDWRIGHT_BROWSER_REQUIRED=1 mise run check:browser
```

## Server URLs

- Main pilot UI: `http://127.0.0.1:8797/admin?view=control_debugger`
- Browser smoke used its own temporary server and Chrome debug ports.

## Screenshots

1. `01-initial-control-debugger.png`
2. `02-selected-read-before-edit-scenario.png`
3. `03-recorded-example-failure-facts.png`
4. `04-trace-evidence-and-selected-event.png`
5. `05-replay-fork-controls-before-change.png`
6. `06-fork-continued-before-change.png`
7. `07-harness-export-opencode-warning.png`
8. `08-ui-friction-default-pattern-mismatch-before-change.png`
9. `09-final-recorded-fixed-tool-governance-pattern.png`
10. `10-final-save-scenario-tool-governance.png`
11. `11-final-replay-fork-accepted-after-fix.png`

## Receipts And Transcripts

- First successful UI run receipt: `rcpt_f6f56af1bb272eed`
- UI-friction save run receipt: `rcpt_2b451c6ab615bf39`
- Final verification receipt: `rcpt_0f72bfc10c73ea5b`
- Final verification session: `session_774_1779467644594`
- Final fork point: `session_774_1779467644594:5`
- Final fork session: `fork_837_1779467645408`

## Key UI Evidence

- Before the fix, `ui-friction-default-pattern-before-change.txt` shows: `Open Workbench, choose tts-retry, then choose the saved scenario.`
- After the fix, `ui-pilot-final-evidence.txt` shows: `Open Workbench, choose tool-governance, then choose the saved scenario.`
- Final replay evidence shows: `Replayed to selected fork point without calling a provider.`
- Final fork evidence shows: `Forked from selected point, applied policy overlay, and continued.`
- Final comparison evidence shows: `Comparison accepted yes` and `Applied rules read-before-edit`.

## Log Notes

- Initial server start failed because dependencies were not installed in the fresh worktree. `mise exec -- mix deps.get` resolved it.
- The first screenshot automation attempt failed before writing screenshots due to an invalid browser-side helper string. Exact terminal error: `Error: Uncaught at evalExpr (file:///Users/admin/projects/wardwright.ralph-pilot-1/[eval1]:102:35)`. The corrected CDP driver captured all required screenshots.
- The local server logged a `tzdata_release_updater` crash while checking the 2026b time-zone release. The app continued serving the UI and the pilot did not depend on time-zone conversion.
- OpenCode was available locally and the UI generated an OpenCode import command, but the pilot did not run a native OpenCode resume.

## Validation Results

- `MIX_ENV=test mise exec -- mix test --no-deps-check test/workbench_test.exs`: 56 passed.
- `mise exec -- gleam format --check src`: passed.
- `mise exec -- gleam check --target erlang`: passed with dependency warnings.
- `python3 scripts/check-lustre-controlled-inputs.py app/src`: passed.
- `MIX_ENV=test mise exec -- mix test --no-deps-check`: 388 passed, 6 excluded.
- `WARDWRIGHT_BROWSER_REQUIRED=1 mise run check:browser`: passed.
