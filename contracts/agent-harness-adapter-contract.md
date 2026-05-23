---
layout: default
title: Agent Harness Adapter Contract
description: Fidelity contract for exporting Wardwright traces into external agent harnesses.
---

# Agent Harness Adapter Contract

Wardwright can replay model-facing history more reliably than it can replay an
agent harness. A model continuation needs messages, tool calls, tool results,
and available tool schemas. A harness continuation may also depend on hidden
state: approvals, checkpoints, local file snapshots, compaction state, MCP
server state, planner memory, subagent state, and UI session indexes.

The adapter contract therefore classifies exports by what they preserve instead
of treating every handoff as equivalent.

## Fidelity Levels

- `native_harness_replay`: the target can import the session, preserve native
  tool results, restore workspace/checkpoint state, and resume private agent
  state. No current adapter claims this.
- `session_import_best_effort`: the target can import a native session container
  and fork/resume it, but Wardwright cannot prove native tool state, workspace
  snapshots, or private agent state are equivalent.
- `session_import_no_native_fork`: the target can import a session container
  but cannot fork it through a documented command.
- `model_context_replay`: the target can receive structured model history but
  not a native harness session.
- `prompt_handoff`: the target receives a rendered trace and instructions. This
  is useful for inspection and dogfood, but it is not native replay.

The UI and API expose `equivalent_agent_resume`. This should remain `false`
unless the adapter can preserve native tool results, workspace snapshots, and
private agent state.

## Current Adapters

| Adapter | Export | Fidelity | Notes |
| --- | --- | --- | --- |
| OpenCode | OpenCode session JSON | `session_import_best_effort` | OpenCode exposes `export`, `import`, `run --session`, and `--fork`. Wardwright emits an importable session-shaped artifact with the trace rendered as evidence, but it does not yet prove native OpenCode tool calls are restored as first-class tool state. |
| OpenCode plugin spike | OpenCode session JSON plus plugin scaffold | `session_import_best_effort` | OpenCode plugins may help with replay reminders and metadata on future runs, but the plugin surface does not change the imported session's missing native Wardwright tool-result state. |
| Claude Code | prompt/files | `prompt_handoff` | Claude stores JSONL transcripts and supports resume/fork for its own sessions, but Wardwright does not rely on an undocumented external import path. |
| Codex | prompt/files | `prompt_handoff` | Codex supports resume/fork for its own sessions. Wardwright treats external trace insertion as a prompt handoff until a stable import surface exists. |
| Pi | Pi session JSONL | `session_import_best_effort` | Pi exposes append-only JSONL sessions and supports `--session` / `--fork`. Wardwright can emit native-looking message and tool-result entries, but workspace snapshots and private agent state remain unproven. |
| oh-my-pi / omp | Pi session JSONL plus `.omp/rules` TTSR bundle | `session_import_best_effort` | omp is compelling as the user-facing runtime home for TTSR-shaped rules. Wardwright can replay and test the same rule, then export the rule into omp when users prefer live enforcement there. The comparison should be behavioral: the same trace and rule should produce the same interruption and failure classification unless agent visibility, runtime efficiency, or implementation correctness differs. |

## API Shape

List adapters:

```http
GET /v1/policy-authoring/harness-adapters
```

Export a loaded trace:

```http
POST /v1/policy-authoring/harness-adapters/opencode/export
Content-Type: application/json

{"session_id":"session_..."}
```

The response includes:

- `adapter`: capability matrix, fidelity label, and missing fidelity fields.
- `artifact_format`: `opencode_session_json` or `prompt_handoff`.
- `artifact`: the generated JSON or prompt/files.
- `commands`: suggested next commands for the target harness.
- `warnings`: fidelity warnings that should be shown to users.

The Control Debugger writes human-usable artifacts under Wardwright's data
directory when a user clicks "Prepare harness handoff". OpenCode gets a
`wardwright-<session_id>.opencode.json` import file. Prompt-handoff adapters
get `wardwright-trace.md` and `wardwright-handoff-prompt.md`.

## Design Review

The first OpenCode adapter intentionally does not write into OpenCode's live
database or shell out to `opencode import` from the server. Server-side imports
would mutate a user's local agent state from a web request, which is too
surprising for a debugger action. Wardwright prepares the artifact and command
instead.

The generated OpenCode artifact was smoke-tested against `opencode import`
1.15.4 in an isolated HOME/XDG directory. That proves the generated container is
accepted by this local OpenCode version; it does not prove semantic equivalence
to a session originally created by OpenCode.

The contract should move more pure classification logic into Gleam over time.
The current `wardwright/harness_adapter` module already owns the fidelity labels
and equivalent-resume predicate. Elixir remains the boundary for reading session
trace files and shaping external JSON.

## Open Questions

- Whether OpenCode accepts a generated session JSON with rendered evidence
  across more versions, and whether a stricter generated schema can represent
  native tool parts.
- Whether Pi/omp session JSONL imports can preserve enough tool call identity
  and result provenance across versions to justify stronger claims.
- Whether a rule that passes Wardwright replay should remain in Wardwright,
  move into omp TTSR, or live in both places with Wardwright as the proof and
  audit layer.
- Whether Wardwright and omp produce equivalent TTSR behavior for the same
  rule, or whether placement changes agent visibility, enforcement overhead, or
  correctness.
- Whether Wardwright should add a CLI command for adapter exports in addition to
  the protected API/UI.
