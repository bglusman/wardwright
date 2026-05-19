# AGENTS.md — Wardwright

Workspace-wide instructions for AI coding agents operating on this public repo.

## What This Repo Is

Wardwright is experimental LLM model middleware extracted from Calciforge's
model-gateway work. Clients call stable OpenAI-compatible model names while
Wardwright owns route graphs, policy/governance, provider selection, caller
traceability, simulation, and receipts.

The repo previously contained multiple backend and frontend prototypes. The
active tree is now BEAM-first:

- `app`
- `contracts`
- `docs`

## Public Repo Rules

Read `CLAUDE.md` before committing. It contains the public-repo secret
discipline rules, never-commit list, and gitleaks workflow. Those rules apply
to every agent, not only Claude.

In short:

- Do not commit secrets, bearer tokens, API keys, private endpoints, real
  deployment identifiers, real private model names, or private user/chat IDs.
- Use `.example` files and RFC-reserved placeholders.
- Do not bypass gitleaks or pre-commit checks.
- Do not put prompt text, credentials, or provider tokens in command argv.
- Do not log provider credentials or raw user content by default.

## Project Vocabulary

- **Wardwright** — the tentative product name.
- **Ingary** — the historical working name. Public project pages now use
  `wardwright.dev`.
- **Wardwright model** — stable public model contract backed by route,
  policy, governance, simulation, and receipt behavior.
- **Route graph** — dispatcher/cascade/alloy/guard/concrete model graph.
- **Receipt** — structured record explaining route decisions, policy actions,
  provider attempts, caller provenance, and final status.
- **Governor / policy engine** — bounded decision layer for request transforms,
  routing, stream/output governance, alerts, retries, and receipt annotations.
- **Caller provenance** — tenant/application/agent/user/session/run metadata.

## Build / Test

```bash
# App
(cd app && mise exec -- mix format --check-formatted && mise exec -- mix test)
```

## Agent Operating Style

These guidelines are adapted from
`https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md`
and should be merged with the Wardwright-specific rules in this file.

- Think before coding. State assumptions when they matter, surface tradeoffs,
  ask when the request is genuinely ambiguous, and push back on unnecessary
  complexity.
- Prefer the minimum implementation that solves the requested problem. Do not
  add speculative features, one-off abstractions, configurability, or defensive
  branches for impossible states.
- Make surgical changes. Touch only files needed for the task, match existing
  style, clean up only unused code created by your change, and mention unrelated
  dead code instead of deleting it.
- Work from verifiable success criteria. For non-trivial changes, know what
  command, test, or behavior proves the task is done, and keep looping until
  that verification is clean or the blocker is explicit.

## Product Contract Rules

- Read `docs/architecture-ratchets.md` and `docs/testing-ratchets.md` before
  large feature work. They capture the anti-god-object, ownership, typed-data,
  concurrency, and behavior-test rules this repo expects agents to preserve.
- Keep the OpenAI-compatible serving surface stable unless the contract changes
  intentionally in `contracts/openapi.yaml`.
- Keep receipt summary shape consistent with the contract. In particular,
  `/v1/receipts` rows must include nested `caller` provenance.
- Keep generated/dynamic model tests portable across implementations when a
  second implementation is intentionally added.
- Treat storage as a product contract, not an implementation detail. Update
  `contracts/storage-provider-contract.md` when changing durable behavior.
- Treat policy language as an engine choice behind a shared ABI. Starlark is the
  first intended portable advanced language; built-in declarative governors
  should cover common cases first.
- UI must distinguish live backend state from mock/not-implemented state.

## Git

- Prefer feature branches and PRs once branch protection is enabled.
- Use descriptive branch names and PR titles that describe the work itself.
  Do not include agent branding such as `codex/` branch prefixes or `[codex]`
  PR-title tags.
- Do not push directly to `main` except for initial bootstrap/admin work before
  protections exist.
- Run `bash scripts/install-git-hooks.sh` in new clones.
- Before merging any PR, inspect every PR review comment and review thread,
  including automated reviewer comments. Address correct feedback in code or
  docs, and explicitly decide/document when a comment is not being changed
  because it is incorrect or out of scope. Do not merge while substantive
  review threads are unconsidered.
