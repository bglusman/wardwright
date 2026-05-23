---
title: Pi and oh-my-pi Replay Spike
---

# Pi and oh-my-pi Replay Spike

This spike takes over the Ralph read-before-edit continuation from PR #70 and
compares three continuation targets:

- Pi session JSONL
- oh-my-pi / omp session JSONL plus TTSR rule export
- OpenCode import plus plugin scaffold

## Working Hypothesis

Wardwright should remain the replay and proof surface for counterfactual
policy behavior. omp may be the better runtime home for rules that are naturally
TTSR-shaped and that users want enforced directly in their coding agent.

That makes rule location a product choice, not a purely technical choice:

- keep rules in Wardwright when the value is review, audit, simulation, or
  backend policy consistency;
- move or mirror rules into omp when the value is immediate live-agent
  interruption and user-owned local behavior;
- compare the same rule in both places before claiming the omp copy preserves
  the Wardwright behavior.

It also gives Wardwright a concrete quality test for its own TTSR model. In
theory, a read-before-edit rule should behave the same whether it lives in
Wardwright replay or in omp runtime rules. If it does not, the mismatch is
useful signal rather than noise:

- agent visibility: the rule may be more legible or more likely to be followed
  when it is visible inside the agent's own runtime;
- implementation efficiency: one runtime may enforce the interruption with
  less replay, buffering, or prompt overhead;
- correctness: differences in matching, cursor handling, or tool-result
  preservation can expose bugs in either Wardwright's projection or the omp
  rule/export path.

## Adapter Results

### Pi

The Pi adapter now emits a native Pi session JSONL artifact with:

- session header version 3;
- a session info entry;
- imported Wardwright trace context;
- synthetic assistant tool calls;
- native `toolResult` message entries with Wardwright cursor and fingerprint
  details.

The adapter remains `session_import_best_effort`: it preserves model-visible
trace and tool-result evidence better than a prompt handoff, but it does not
prove workspace snapshots or private agent state.

### oh-my-pi / omp

The omp adapter emits the same Pi session JSONL plus a replay bundle:

- `wardwright-read-before-edit.md` for `.omp/rules`;
- `wardwright-state-fidelity.ts` as an extension scaffold;
- the exported Wardwright state-fidelity probe.

This is the most promising direction for TTSR-shaped rules. The important
comparison is not "Wardwright or omp"; it is "Wardwright proves and audits the
rule, omp optionally enforces the proven rule in the user's live agent loop."
The same exported rule should therefore be run as a behavioral equivalence
check: same trace, same expected interruption, same failure classification.
The exported OMP rule keeps the match condition deliberately broad and uses
tool scopes for edit/write/patch tool names, because OMP evaluates `condition`
against streamed content while `scope` narrows which tool argument streams are
eligible.

### Runtime Equivalence Probe

The next test is executable as:

```bash
OMP_BIN=/tmp/omp-darwin-arm64 node scripts/omp-ttsr-runtime-equivalence.mjs
```

Use `OMP_BIN=omp` when `omp` is installed on `PATH`.

The probe extracts the current Wardwright OMP rule from
`WardwrightWeb.AgentHarnessAdapters`, then creates an isolated OMP home,
project, rule directory, and extension. The extension registers a fake
`wardwright-runtime/tool-probe` model provider that streams actual OMP
assistant `toolcall_delta` events without live model credentials. OMP then
loads the exported Wardwright rule from `.omp/rules`, so the assertion runs
through OMP's real session/TTSR runtime rather than a Wardwright-side matcher.

Current observed result against OMP 15.2.4:

- `edit` triggers `wardwright-read-before-edit`;
- `edit_file` triggers `wardwright-read-before-edit`;
- `write` triggers `wardwright-read-before-edit`;
- `read` does not trigger.

This proves the exported rule's OMP runtime shape for the core read-before-edit
interruption. It still does not prove full replay equivalence: the separate
state-fidelity probe must compare imported session/tool-result evidence before
the adapter can claim more than best-effort continuation.

### OpenCode Plugin

The OpenCode plugin spike keeps the current import result conservative. A
plugin can add replay reminders and metadata around future tool execution, but
it does not repair the current import limitation where Wardwright evidence is
stored as text/step parts rather than native imported tool-result state.

## Adapter Policy Questions

Agent adapters should be treated as capability signals, not requirements.
Wardwright should continue to work for ordinary clients exactly as it does now,
then selectively unlock better behavior when an adapter is present and
verified.

The gateway should probably distinguish at least these cases:

- no adapter signal: use today's explicit debugger controls and do not assume
  agent-local state exists;
- adapter installed but unverified: expose setup status and conservative
  handoff/export commands, but do not change recording defaults;
- adapter verified for the current workspace/session: allow opt-in behavior
  such as "auto-record debugger traces for adapted agents";
- adapter verified plus state-fidelity probe matched: allow stronger replay UI
  affordances while still avoiding equivalent-resume claims unless the full
  contract says so.

That suggests debugger recording should become policy-driven rather than a
single global toggle. A useful default could be:

- record when the request declares a trusted Wardwright adapter identity and the
  user enabled adapter auto-recording;
- do not auto-record for generic OpenAI-compatible clients unless the user
  enabled broader gateway recording;
- always allow explicit record/replay controls regardless of adapter status.

Shipping also needs a real install and maintenance story. The adapter should be
easy to discover and diagnose without requiring users to understand each
agent's config layout. A future Wardwright CLI surface could provide:

- `wardwright adapters install omp` to place rules/extensions and write the
  minimal agent config;
- `wardwright adapters doctor` to report installed versions, config paths,
  reachable gateway URL, auth status, and whether the adapter identity is being
  sent on live requests;
- `wardwright adapters repair` or scoped install subcommands when config drift
  is common enough to justify mutation;
- export-only fallback commands for users who do not want persistent agent
  integration.

The standard should stay strict: adapters are worth shipping when they improve
visibility, fidelity, setup ergonomics, or enforcement latency. They should not
become the only path unless they unlock something that cannot degrade cleanly
to today's gateway/API support.

## Current Verdict

Pi/omp is more promising than OpenCode for counterfactual replay because Pi
sessions are append-only JSONL with explicit message entries, and omp gives us a
native TTSR runtime for rules users may want outside Wardwright. The fidelity
claim should still remain best-effort until a live fork/resume trial proves the
session store and tool-result entries survive exactly as needed.
