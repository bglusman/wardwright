# Bash Command Canonicalization Eval

This branch starts a narrow Wardwright-side experiment for agent Bash tool calls
that are semantically allowlist-friendly but shaped in ways that trigger
permission prompts.

It is inspired by
[wayfinder-router](https://github.com/itsthelore/wayfinder-router)'s core shape:
make a deterministic, offline decision from request structure before spending
latency, model budget, or human attention. Wayfinder applies that to
local-vs-cloud model routing; this branch tests the same kind of preflight
control point for tool-call shape.

The first library surface is `Wardwright.BashCanonicalizer.canonicalize/2`.
It returns a JSON-serializable map:

- `status: "rewritten"` when the command can be safely converted to one or more
  atomic commands.
- `status: "unchanged"` when no rewrite is needed.
- `status: "repair"` when the model should be asked to retry with a simpler
  command shape.

Initial covered cases:

- `git -C <current repo> status --short` -> `git status --short`
- top-level `&&` and `;` chains split into separate commands while preserving
  separators inside quotes
- `git -C <other repo> ...` reported as model-repair, not rewritten
- shell variable assignment plus later expansion reported as model-repair

Other Wayfinder-shaped Wardwright experiments worth comparing against this one:

- prompt complexity scoring as a route fact before model selection
- deterministic request classification as a cheap guard before Dune/WASM policy
  evaluation
- tool-call canonicalization as a preflight repair loop before permission
  prompts or denials
- receipt-visible router explanations that show which structural features drove
  a route, guard, or repair decision

Run the focused library eval:

```bash
cd app
mise exec -- mix test test/bash_canonicalizer_test.exs
```

This is intentionally deterministic before adding model-to-model rewrite passes.
The next useful step is to feed the `repair` diagnostics back into a simple model
retry stage and compare original command, canonical command(s), predicted
permission behavior, and execution result.
