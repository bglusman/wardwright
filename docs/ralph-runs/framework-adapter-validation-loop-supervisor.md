---
title: Framework Adapter Validation Ralph Loop Supervisor
---

# Framework Adapter Validation Ralph Loop Supervisor

This file is the durable tracker for the framework adapter validation Ralph
loop. The build target is
[`framework-adapter-validation-requirements.md`](framework-adapter-validation-requirements.html).

Status: active. The local adapter install-validation loop is complete; this is
a separate follow-on loop for high-adoption framework integrations and e2e
smoke validation.

## Branch Policy

- Continue on `codex/pi-replay-spike` / PR #71.
- Do not create a branch or pull request per loop.
- Prefer one coherent commit per loop, pushed to the existing PR branch.
- Keep raw logs, package caches, generated framework projects, and oversized
  smoke artifacts out of the repo.
- Commit only source, tests, docs, scripts, fixtures, and concise evidence that
  are reviewable.

## Cadence

- Runner: `scripts/run-framework-adapter-ralph-loop.sh`.
- Successful iterations chain immediately into the next iteration.
- Retry delay after a failed iteration: 15 minutes by default, configurable via
  `RALPH_RETRY_DELAY_SECONDS`.
- Completion sentinel:
  `$(git rev-parse --git-path ralph-runs/framework-adapter-validation/complete)`.
- The loop should stop only after the exit criteria in the requirements file
  are implemented, validated, documented, and recorded here.

## Requirements Review

The next work is not "support every popular framework." It is to define a
repeatable framework-adapter contract and then implement the few integrations
where Wardwright can add real value beyond generic OpenAI-compatible routing:
caller provenance, receipt correlation, policy evidence, and honest fidelity
labels.

Execution constraints:

- Keep framework adapters separate from local coding-agent adapters.
- OpenCode and OpenClaw are distinct first-class local surfaces.
- Prefer small helper packages, middleware, callbacks, tracing processors,
  advisors, or recipes before deep platform plugins.
- Do not claim hidden framework state import or equivalent agent resume unless
  an implementation test proves it.
- Use typed Gleam for pure adapter decision/fidelity logic when the work enters
  Wardwright core; keep filesystem, process, HTTP, JSON, package-manager, and
  Phoenix boundaries in Elixir or scripts.
- Every committed implementation loop must include behavior-focused tests or a
  clear documentation-only reason.
- After every commit, conduct and record an adversarial review covering
  architecture, code/comment quality, and test quality.

## Ordered Backlog

1. Define the shared framework adapter contract and smoke-test shape.
2. Add Vercel AI SDK support with a provider/middleware or generated example
   and a local Node smoke.
3. Add LangChain/LangGraph support, starting with Python unless TypeScript is a
   smaller, higher-confidence slice.
4. Add Pydantic AI support with provider/context/receipt correlation.
5. Add OpenAI Agents SDK support on the Chat Completions path and record the
   `/v1/responses` gap unless implemented.
6. Add Microsoft.Extensions.AI support, then Semantic Kernel guidance or
   filter/plugin support.
7. Add LlamaIndex callback/recipe support without duplicating index internals.
8. Scope local coding-agent follow-ups separately: OpenCode-native scaffold,
   OpenClaw direct config/native Codex, and Aider config handoff.
9. Promote reusable framework e2e smoke infrastructure without requiring
   external package fetches in the default test suite.
10. Final docs pass and completion sentinel.

## Continuation Log

### Loop 0 - Kickoff

- Timestamp: 2026-05-23T22:50-04:00.
- Starting commit: `284a7e1`.
- Scope: created the framework adapter validation requirements, supervisor,
  loop prompt, and runner script so the new Ralph track can run independently
  from the completed local installer loop.
- Validation:
  - `mise run check:docs`: passed.
  - `bash -n scripts/run-framework-adapter-ralph-loop.sh`: passed.
  - `git diff --check`: passed.
- Adversarial review:
  - Architecture: no blocker found. The framework loop has its own prompt,
    supervisor, state directory, lock, logs, and completion sentinel, so it
    will not be blocked by the completed install-validation sentinel. The
    duplication with `run-adapter-ralph-loop.sh` is acceptable for this setup
    slice because the prompts and completion criteria are materially different;
    a later cleanup could generalize the runner only after both loops have
    proven stable.
  - Code/comment quality: no comments were needed in the runner because the
    variable names and log lines describe the lifecycle directly. The prompt
    order intentionally updates the supervisor before commit and records
    post-commit review before push, avoiding the stale-log problem from the
    earlier loop prompt.
  - Test quality: this is setup work, so validation is docs rendering, shell
    syntax, and whitespace checks rather than product behavior tests. Loop 1
    must add behavior-focused contract or smoke coverage before claiming any
    framework adapter support.
- Skipped probes: no framework SDKs were installed or executed in this setup
  slice. The runner should start loop 1, which will pick the framework adapter
  contract foundation as the first implementation item.
- Current status: ready to start loop 1.

### Loop 1 - Framework Adapter Contract Foundation

- Timestamp: 2026-05-23T22:51-04:00.
- Starting commit: `d4e74e6`.
- Intended ending commit: framework adapter contract foundation.
- Scope: define the shared SDK/framework adapter contract before implementing
  individual framework packages. The slice adds typed Gleam classification for
  framework surface family, support tier, framework fidelity wording,
  receipt-correlation readiness, and fail-closed smoke status. It
  also documents the contract in `contracts/framework-adapter-contract.md`,
  including provenance fields, receipt-id propagation, privacy rules, fallback
  behavior, and the separation from OpenCode/OpenClaw/local coding-agent
  tracks.
- Validation:
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
  - Commit hook full app/docs/gitleaks gate: passed, including 419 app tests
    with 21 properties and 6 excluded tests.
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs`:
    passed, 6 tests.
  - Note: direct file-targeted `mise exec -- mix test ...` variants still hit
    this repo/toolchain's known path parsing issue and treated the test path as
    an unknown dependency; compiling in `MIX_ENV=test` and then using
    `--no-compile` is the working focused invocation for this Gleam-backed test.
  - Post-review rename validation repeated the focused compile/test, docs,
    format, and whitespace checks above: passed.
- Skipped probes: no Vercel AI SDK, LangChain, or other framework package was
  installed or executed in this foundation slice. The contract intentionally
  avoids claiming framework-specific support until a later loop adds a runnable
  smoke.
- Adversarial review:
  - Architecture: initial review found one pre-push blocker in the pure Gleam
    API name `framework_aware_recording_allowed`; it could imply automatic
    recording permission from framework surface plus receipt correlation alone.
    The function was renamed to `framework_receipt_correlation_ready` so future
    recording policy stays separate from receipt propagation evidence. No other
    architecture blocker found. The new contract keeps SDK/framework support
    separate from OpenCode/OpenClaw/local coding-agent adapters and does not
    claim native framework state or package support.
  - Code/comment quality: the core logic is small, typed, and label-oriented.
    There are no comments because the public function names and contract doc
    carry the meaning. The string surface catalog is acceptable for this
    foundation slice, but a later adapter package should avoid scattering these
    ids across more modules.
  - Test quality: tests are behavior-focused for the contract layer: they prove
    framework/local-agent separation, strongest-proven-tier selection,
    fail-closed fidelity wording, smoke failure reporting, and receipt
    correlation preconditions. They do not prove any real framework SDK call;
    that remains the next backlog item and is recorded as a skipped probe.
- Next open item: add Vercel AI SDK support with a provider or middleware smoke
  proving Wardwright model routing, caller provenance, and receipt-id capture.

### Loop 2 - Vercel AI SDK Recipe Smoke

- Timestamp: 2026-05-23T23:04-04:00.
- Starting commit: `ed355c7`.
- Intended ending commit: Vercel AI SDK recipe smoke.
- Scope: add the first framework-specific implementation slice for Vercel AI
  SDK without claiming a published package or native framework state. The slice
  adds an adapter-owned Node helper that matches the AI SDK OpenAI-compatible
  provider shape, maps caller provenance into Wardwright headers, captures
  `x-wardwright-receipt-id` through a custom `fetch` wrapper, documents the
  recipe/status, and adds a local Node smoke through a real Wardwright router.
- Validation:
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `node --check app/priv/framework_adapters/vercel_ai_sdk/wardwright-ai-sdk.mjs && node --check app/priv/framework_adapters/vercel_ai_sdk/smoke.mjs`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/vercel_ai_sdk_adapter_smoke_test.exs`: passed, 1 test.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs`: passed, 7 tests.
  - `mise exec -- mix format --check-formatted`: passed after formatting the new test.
  - `mise exec -- gleam format --check src`: passed.
  - `mise exec -- gleam check --target erlang`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
- Skipped probes: no npm packages were installed and no live Vercel AI SDK
  project was generated in this default slice. The committed smoke deliberately
  avoids external package fetches and proves the provider options/fetch wrapper
  contract against Wardwright directly. Streaming receipt propagation is
  recorded as deferred rather than implied.
- Adversarial review:
  - Architecture: no blocker found after one fix. The slice stays recipe-only
    and uses a provider-options/fetch-wrapper boundary rather than pretending to
    own Vercel AI SDK internals. It keeps local coding-agent adapters out of the
    framework path and records streaming as deferred. A future package should
    move this helper out of `app/priv` into an explicit distribution boundary
    before claiming `helper_package`.
  - Code/comment quality: initial post-commit review found a real issue in the
    default helper options: using a placeholder `apiKey` could teach users to
    send a fake bearer token. That default was removed, and the docs now pass
    `WARDWRIGHT_MODEL_API_KEY` only when present. No extra comments were needed;
    the helper names and smoke report carry the behavior.
  - Test quality: the smoke test is capable of failing for the missing product
    behavior under review: wrong model route, missing provenance headers, lost
    receipt capture, or overclaimed generic fallback. It uses a real local
    Wardwright router and synthetic data. It does not prove the installed AI SDK
    package's current runtime wiring or streaming behavior; those remain
    explicitly skipped/deferred.
- Next open item: add LangChain/LangGraph support, starting with Python unless
  a smaller TypeScript slice gives better confidence, and prove receipt
  correlation to framework-visible run or checkpoint metadata.

### Loop 3 - LangChain/LangGraph Recipe Smoke

- Timestamp: 2026-05-23T23:12-04:00.
- Starting commit: `22180a1`.
- Intended ending commit: LangChain/LangGraph recipe smoke with post-commit
  review recorded.
- Scope: add the second framework-specific implementation slice for
  LangChain/LangGraph without claiming installed package support, native graph
  state, or checkpoint durability. The slice adds an adapter-owned Python
  helper that follows the OpenAI-compatible model configuration path, maps
  caller provenance into Wardwright headers, captures
  `x-wardwright-receipt-id` through a callback-style object, writes the receipt
  into LangChain-style run metadata and LangGraph-style checkpoint metadata,
  documents the recipe/status, and adds a local Python smoke through a real
  Wardwright router.
- Validation:
  - `python3 -m py_compile app/priv/framework_adapters/langchain_langgraph/wardwright_langchain.py app/priv/framework_adapters/langchain_langgraph/smoke.py`: passed.
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/langchain_langgraph_adapter_smoke_test.exs`:
    passed, 1 test.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs`:
    passed, 8 tests.
  - `mise exec -- mix format --check-formatted`: passed after formatting the
    new test file.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
  - Commit hook full app/docs/gitleaks gate: passed, including 420 app tests
    with 21 properties and 6 excluded tests.
- Skipped probes: no Python packages were installed and no live
  LangChain/LangGraph project was generated in this default slice. The
  committed smoke deliberately avoids external package fetches and proves the
  framework-visible metadata contract against Wardwright directly. Streaming,
  real LangChain callback wiring, and LangGraph checkpoint durability remain
  deferred rather than implied.
- Adversarial review:
  - Architecture: no blocker found. The slice stays recipe-only and keeps
    LangChain/LangGraph in the framework SDK lane rather than mixing them with
    OpenCode/OpenClaw/local coding-agent adapters. The helper writes receipt ids
    into framework-style run/checkpoint metadata but explicitly avoids claiming
    LangGraph checkpoint durability or native state import. The remaining
    architecture gap is expected for this tier: direct stdlib HTTP proves the
    Wardwright metadata contract, not the real LangChain package callback
    lifecycle.
  - Code/comment quality: no blocker found. The Python helper is small and
    boundary-oriented: base URL normalization, provenance header mapping,
    receipt capture, and a smoke-only chat-completion call. It does not include
    placeholder API keys or persisted trace payloads. Error handling is minimal
    but adequate for a deterministic smoke; a future helper package should
    adopt the real framework client's exception and callback surfaces instead
    of expanding this stdlib wrapper.
  - Test quality: the smoke is capable of failing for the missing product
    behavior under review: wrong Wardwright model routing, dropped provenance,
    missing receipt header capture, missing LangChain run metadata, missing
    LangGraph checkpoint metadata, or overclaimed generic fallback. It uses a
    real local Wardwright router and synthetic prompts. It does not prove the
    installed LangChain/LangGraph packages, streaming behavior, or checkpoint
    persistence; those are recorded as skipped/deferred probes.
- Next open item: add Pydantic AI support with provider/context/receipt
  correlation and clear structured-output or tool-capability limitation
  wording.
