---
title: Framework Adapter Validation Ralph Loop Supervisor
---

# Framework Adapter Validation Ralph Loop Supervisor

This file is the durable tracker for the framework adapter validation Ralph
loop. The build target is
[`framework-adapter-validation-requirements.md`](framework-adapter-validation-requirements.html).

Status: complete. The local adapter install-validation loop is complete; this
separate follow-on loop for high-adoption framework integrations and e2e smoke
validation has completed the recipe-only foundation and recorded its remaining
fidelity limits.

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
  - Post-review trace-privacy fix repeated the Python syntax check, focused
    OpenAI Agents SDK smoke, and whitespace check above: passed.
  - Post-review credential-metadata fix repeated the Python syntax check,
    focused Pydantic smoke, combined framework smoke set, format check, docs
    check, and whitespace check above: passed.
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

### Loop 4 - Pydantic AI Recipe Smoke

- Timestamp: 2026-05-23T23:19-04:00.
- Starting commit: `76c30eb`.
- Intended ending commit: Pydantic AI recipe smoke with post-commit review
  recorded.
- Scope: add the third framework-specific implementation slice for Pydantic AI
  without claiming installed package support, native framework state, graph
  durability, or structured-output/tool-call fidelity. The slice adds an
  adapter-owned Python helper that follows the Pydantic AI OpenAI-compatible
  provider path, maps typed run context into Wardwright provenance headers,
  captures `x-wardwright-receipt-id` into Pydantic-style run metadata,
  documents the recipe/status, and adds a local Python smoke through a real
  Wardwright router.
- Validation:
  - `python3 -m py_compile app/priv/framework_adapters/pydantic_ai/wardwright_pydantic_ai.py app/priv/framework_adapters/pydantic_ai/smoke.py`:
    passed.
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/pydantic_ai_adapter_smoke_test.exs`:
    passed, 1 test.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs test/pydantic_ai_adapter_smoke_test.exs`:
    passed, 9 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
- Skipped probes: no Python packages were installed and no live Pydantic AI
  project was generated in this default slice. The committed smoke avoids
  external package fetches and proves the framework-visible metadata contract
  against Wardwright directly. Real Pydantic AI provider hooks, graph
  durability, streaming behavior, structured output, and tool-call capability
  preservation remain deferred rather than implied.
- Adversarial review:
  - Architecture: initial post-commit review found one blocker in the helper
    boundary: accepting an API key and returning it inside the provider config
    could make adapter-owned smoke reports or user metadata capture a provider
    credential. The helper now returns only the environment variable name
    `WARDWRIGHT_MODEL_API_KEY`; docs read the environment value at the
    framework boundary instead of storing it in adapter metadata. No other
    architecture blocker found. The slice stays recipe-only, keeps Pydantic AI
    in the framework SDK lane, and does not claim native Pydantic AI state,
    graph durability, streaming, structured-output fidelity, or tool-call
    fidelity.
  - Code/comment quality: the Python helper is small and boundary-oriented:
    typed run context, provenance headers, base URL normalization, receipt
    capture, and capability-limit wording. No comments were needed in code;
    the docs carry the integration caveat that real Pydantic AI usage needs a
    provider hook or owned HTTP client wrapper to attach headers and capture
    response headers.
  - Test quality: the smoke is capable of failing for the missing product
    behavior under review: wrong Wardwright model routing, dropped provenance,
    missing receipt header capture, missing Pydantic-style run metadata,
    leaked API-key config, missing capability-limit wording, or overclaimed
    generic fallback. It uses a real local Wardwright router and synthetic
    prompts. It does not prove the installed Pydantic AI package, graph
    durability, streaming behavior, structured output, or tool-call
    preservation; those are recorded as skipped/deferred probes.
- Next open item: add OpenAI Agents SDK support on the Chat Completions path
  and record the `/v1/responses` gap unless implemented.

### Loop 5 - OpenAI Agents SDK Recipe Smoke

- Timestamp: 2026-05-23T23:29-04:00.
- Starting commit: `0284546`.
- Intended ending commit: OpenAI Agents SDK recipe smoke with post-commit
  review recorded.
- Scope: add the fourth framework-specific implementation slice for OpenAI
  Agents SDK without claiming installed package support, `/v1/responses`
  parity, native Agents sessions, tool-call fidelity, streaming behavior,
  native framework state import, or exact replay. The slice adds an
  adapter-owned Python helper that follows the Chat Completions model path,
  maps caller provenance into Wardwright headers, captures
  `x-wardwright-receipt-id` into tracing-processor-style trace and generation
  metadata, documents the recipe/status, and adds a local Python smoke through
  a real Wardwright router.
- Validation:
  - `python3 -m py_compile app/priv/framework_adapters/openai_agents_sdk/wardwright_openai_agents.py app/priv/framework_adapters/openai_agents_sdk/smoke.py`:
    passed.
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/openai_agents_sdk_adapter_smoke_test.exs`:
    passed, 1 test.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs test/pydantic_ai_adapter_smoke_test.exs test/openai_agents_sdk_adapter_smoke_test.exs`:
    passed, 10 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
- Skipped probes: no Python packages were installed and no live OpenAI Agents
  SDK project was generated in this default slice. The committed smoke avoids
  external package fetches and proves the framework-visible metadata contract
  against Wardwright directly. Real Agents SDK execution, `/v1/responses`,
  native sessions, tools, streaming behavior, and trace exporter integration
  remain deferred rather than implied.
- Adversarial review:
  - Architecture: initial post-commit review found one pre-push blocker in the
    trace processor boundary: the real SDK callback path could store an
    exported trace object too broadly. The helper now records only allowlisted
    trace fields and provenance/receipt metadata, and the smoke includes a
    sensitive trace probe proving raw prompt/completion metadata is not
    retained. No other architecture blocker found. The slice stays
    recipe-only, keeps OpenAI Agents SDK in the framework SDK lane, and does
    not claim `/v1/responses`, native sessions, tools, streaming, native state
    import, or exact replay.
  - Code/comment quality: the Python helper is boundary-oriented: base URL
    normalization, provenance headers, Chat Completions request execution,
    tracing-processor-style receipt capture, and safe trace metadata
    allowlisting. No provider credentials are stored in adapter metadata; the
    config reports only `WARDWRIGHT_MODEL_API_KEY`.
  - Test quality: the smoke is capable of failing for the missing product
    behavior under review: wrong Wardwright model routing, dropped provenance,
    missing receipt header capture, missing trace/generation metadata, leaked
    API-key config, raw trace payload retention, or overclaimed generic
    fallback. It uses a real local Wardwright router and synthetic prompts. It
    does not prove the installed OpenAI Agents SDK package, `/v1/responses`,
    native sessions, tools, streaming behavior, or trace exporter integration;
    those are recorded as skipped/deferred probes.
- Next open item: add Microsoft.Extensions.AI support, then Semantic Kernel
  guidance or filter/plugin support, with a smoke proving
  provenance/receipt-correlation through the .NET client path.

### Loop 6 - Microsoft.Extensions.AI Recipe Smoke

- Timestamp: 2026-05-23T23:41-04:00.
- Starting commit: `a144423`.
- Intended ending commit: Microsoft.Extensions.AI recipe smoke with
  post-commit review recorded.
- Scope: add the fifth framework-specific implementation slice for
  Microsoft.Extensions.AI with Semantic Kernel guidance without claiming
  installed NuGet package support, `dotnet` runtime execution, Semantic Kernel
  planner behavior, native framework state, streaming, tool-call fidelity, or
  exact replay. The slice adds an adapter-owned Python helper that follows the
  `IChatClient` and `DelegatingChatClient` integration shape, maps caller
  provenance into Wardwright headers, captures `x-wardwright-receipt-id` into
  Microsoft.Extensions.AI-style `ChatResponse.AdditionalProperties`,
  documents Semantic Kernel as guidance on the same `IChatClient` path, and
  adds a local Python smoke through a real Wardwright router.
- Validation:
  - `python3 -m py_compile app/priv/framework_adapters/microsoft_extensions_ai/wardwright_microsoft_extensions_ai.py app/priv/framework_adapters/microsoft_extensions_ai/smoke.py`:
    passed.
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/microsoft_extensions_ai_adapter_smoke_test.exs`:
    passed, 1 test.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs test/pydantic_ai_adapter_smoke_test.exs test/openai_agents_sdk_adapter_smoke_test.exs test/microsoft_extensions_ai_adapter_smoke_test.exs`:
    passed, 11 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
  - Commit hook full app/docs/gitleaks gate: passed, including 423 app tests
    with 21 properties and 6 excluded tests.
- Skipped probes: no NuGet packages were installed, no live
  Microsoft.Extensions.AI or Semantic Kernel project was generated, and no
  `dotnet` runtime smoke was executed because `dotnet` is not available in
  this environment. The committed smoke avoids external package fetches and
  proves the framework-visible metadata contract against Wardwright directly.
  Streaming, tool calling, real `DelegatingChatClient` execution, Semantic
  Kernel filters/plugins, and native framework state remain deferred rather
  than implied.
- Adversarial review:
  - Architecture: no blocker found. The slice keeps .NET framework support in
    the framework SDK lane and leaves OpenCode/OpenClaw/local coding-agent
    adapters untouched. The helper models the current `IChatClient` plus
    delegating-client receipt path and records Semantic Kernel as guidance on
    top of that path rather than a second planner. The remaining architecture
    gap is intentional for `recipe_only`: the smoke proves Wardwright metadata
    behavior through direct HTTP, not real Microsoft.Extensions.AI package
    lifecycle, DI ordering, streaming, tool invocation, or Semantic Kernel
    filter execution.
  - Code/comment quality: no blocker found. The Python helper stays at the
    boundary: base URL normalization, provenance header mapping, receipt-header
    capture, and sanitized metadata shaping. It does not store provider API
    keys or raw response bodies in the smoke report. The C# docs show the
    intended integration point, but a future helper package should provide a
    compiled `WardwrightReceiptDelegatingChatClient` sample before claiming
    more than recipe support.
  - Test quality: the smoke is capable of failing for the missing product
    behavior under review: wrong Wardwright model routing, dropped provenance,
    missing receipt header capture, missing `ChatResponse.AdditionalProperties`
    metadata, leaked API-key config, overclaimed Semantic Kernel support, or
    overclaimed generic fallback. It uses a real local Wardwright router and
    synthetic prompts. It does not prove installed .NET packages, a `dotnet`
    runtime, Semantic Kernel filters/plugins, streaming, tool calling, or
    native framework state; those are recorded as skipped/deferred probes.
- Next open item: add LlamaIndex callback/recipe support with a smoke proving
  Wardwright model routing, caller provenance, and receipt correlation without
  duplicating retrieval/index internals.

### Loop 7 - LlamaIndex Recipe Smoke

- Timestamp: 2026-05-23T23:48-04:00.
- Starting commit: `3378f76`.
- Intended ending commit: `7fe7746` before post-review documentation amend.
- Scope: add the sixth framework-specific implementation slice for LlamaIndex
  without claiming installed package support, retrieval lineage ownership,
  index durability, native framework state, tool-call fidelity, streaming
  behavior, or exact replay. The slice adds an adapter-owned Python helper
  that follows the `OpenAILike` OpenAI-compatible model path, maps caller
  provenance into Wardwright headers, captures `x-wardwright-receipt-id` into
  LlamaIndex-style LLM event metadata and retrieval-context metadata, documents
  the recipe/status, and adds a local Python smoke through a real Wardwright
  router.
- Validation:
  - `python3 -m py_compile app/priv/framework_adapters/llamaindex/wardwright_llamaindex.py app/priv/framework_adapters/llamaindex/smoke.py`:
    passed.
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/llamaindex_adapter_smoke_test.exs`:
    passed, 1 test.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs test/pydantic_ai_adapter_smoke_test.exs test/openai_agents_sdk_adapter_smoke_test.exs test/microsoft_extensions_ai_adapter_smoke_test.exs test/llamaindex_adapter_smoke_test.exs`:
    passed, 12 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise exec -- gleam format --check src`: passed.
  - `mise exec -- gleam check --target erlang`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
  - Commit hook full app/docs/gitleaks gate: passed, including 424 app tests
    with 21 properties and 6 excluded tests.
- Skipped probes: no Python packages were installed and no live LlamaIndex
  project was generated in this default slice. The committed smoke avoids
  external package fetches and proves the framework-visible metadata contract
  against Wardwright directly. Real LlamaIndex execution, callback manager
  wiring, retrieval/index persistence, streaming behavior, and tool-call
  preservation remain deferred rather than implied.
- Adversarial review:
  - Architecture: no blocker found. The slice stays recipe-only and keeps
    LlamaIndex in the framework SDK lane rather than mixing it with
    OpenCode/OpenClaw/local coding-agent adapters. It records receipt
    correlation in LlamaIndex-style LLM event metadata and retrieval-context
    metadata, but explicitly refuses retrieval lineage ownership, index
    durability, native framework state import, tool-call fidelity, streaming,
    or exact replay. The remaining architecture gap is intentional for
    `recipe_only`: direct stdlib HTTP proves the Wardwright metadata contract,
    not the real LlamaIndex package callback lifecycle.
  - Code/comment quality: initial post-commit review found a docs clarity issue
    where the example imported `CallbackManager` even though the committed
    helper is not a native LlamaIndex callback handler. The example now points
    users to an owned LlamaIndex callback handler or HTTP wrapper for
    `callback.capture(...)`. The helper itself stays small and boundary-owned:
    base URL normalization, provenance headers, receipt capture, and sanitized
    metadata shaping. It does not store provider API keys, raw prompts, or raw
    response bodies in the smoke report.
  - Test quality: the smoke is capable of failing for the missing product
    behavior under review: wrong Wardwright model routing, dropped provenance,
    missing receipt header capture, missing LLM event metadata, missing
    retrieval-context receipt metadata, leaked API-key config, overclaimed
    retrieval/index support, or overclaimed generic fallback. It uses a real
    local Wardwright router and synthetic prompts. It does not prove the
    installed LlamaIndex package, callback manager wiring, retrieval/index
    persistence, streaming behavior, or tool-call preservation; those remain
    explicitly skipped/deferred probes.
- Next open item: promote reusable framework e2e smoke infrastructure without
  requiring external package fetches in the default test suite, then run the
  final docs/completion pass if the completion criteria are otherwise met.

### Loop 8 - Reusable Framework Smoke Infrastructure

- Timestamp: 2026-05-23T23:58-04:00.
- Starting commit: `12f793f`.
- Intended ending commit: `2c77038`.
- Scope: promote the repeated framework adapter smoke setup into shared ExUnit
  test support without changing the recipe-only support claims. The slice adds
  `Wardwright.FrameworkAdapterSmokeCase` to configure an app-local Wardwright
  router with a canned target, execute the adapter-owned Node or Python smoke,
  assert common framework smoke contract behavior, and verify caller
  provenance in Wardwright receipts. Existing framework smoke tests now use
  that helper while retaining their framework-specific assertions and deferred
  fidelity limits.
- Validation:
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs test/pydantic_ai_adapter_smoke_test.exs test/openai_agents_sdk_adapter_smoke_test.exs test/microsoft_extensions_ai_adapter_smoke_test.exs test/llamaindex_adapter_smoke_test.exs`:
    passed, 6 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
  - Commit hook full app/docs/gitleaks gate: passed, including 424 app tests
    with 21 properties and 6 excluded tests.
- Skipped probes: no external npm, pip, or NuGet packages were installed, and
  no live framework projects were generated. This infrastructure keeps default
  smokes deterministic and app-local; real package-manager probes remain
  opt-in future work.
- Adversarial review:
  - Architecture: no blocker found. The shared smoke helper stays in test
    support and does not move framework SDK decisions into router/runtime code
    or local coding-agent adapters. It preserves the app-local gateway shape
    and recipe-only fidelity claims while making the repeated smoke contract
    easier to inspect. The remaining architecture gap is intentional: this
    still proves adapter-owned deterministic smokes, not live package-manager
    lifecycle or native framework hooks.
  - Code/comment quality: no blocker found. The helper is explicit about the
    required smoke spec, executable selection, canned target setup, common
    report assertions, and receipt caller assertions. It adds no comments
    because the helper names and test names carry the intent. The spec maps
    still repeat expected caller values per framework, which is acceptable
    because those values are part of each framework smoke's public evidence.
  - Test quality: no blocker found. The refactor keeps each framework's
    behavior-specific assertions while centralizing shared failure conditions:
    model routing, receipt capture, fallback honesty, smoke-contract status,
    and caller provenance in receipts. The tests remain capable of failing for
    dropped headers, wrong canned target selection, missing receipt capture, or
    overclaimed fallback behavior. They still do not prove installed framework
    packages, streaming, tool calls, or native framework state; those remain
    recorded skipped probes rather than hidden claims.
- Next open item: final docs pass and completion sentinel if the completion
  criteria are otherwise satisfied; otherwise record any remaining validation
  gap before stopping.

### Loop 9 - Final Docs Pass And Completion Sentinel

- Timestamp: 2026-05-24T00:02-04:00.
- Starting commit: `9b0bfab`.
- Intended ending commit: final framework adapter validation completion docs.
- Scope: perform the completion pass after the contract foundation, six
  framework recipe smokes, and reusable smoke infrastructure were implemented.
  The pass confirms the docs cover framework tiers, provenance metadata,
  receipt-id propagation, app-local smoke evidence, local coding-agent
  separation, fallback behavior, privacy rules, and fidelity limits without
  claiming live package execution or native framework state.
- Validation:
  - `MIX_ENV=test mise exec -- mix compile`: passed.
  - `MIX_ENV=test mise exec -- mix test --no-compile test/gleam_framework_adapter_test.exs test/vercel_ai_sdk_adapter_smoke_test.exs test/langchain_langgraph_adapter_smoke_test.exs test/pydantic_ai_adapter_smoke_test.exs test/openai_agents_sdk_adapter_smoke_test.exs test/microsoft_extensions_ai_adapter_smoke_test.exs test/llamaindex_adapter_smoke_test.exs`:
    passed, 12 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise run check:docs`: passed.
  - `git diff --check`: passed.
  - Commit hook docs/gitleaks gate: passed.
- Skipped probes: no external npm, pip, or NuGet package-manager probes are
  part of the default completion pass. Live framework package execution,
  streaming, tool calls, native framework state/checkpoints, and exact replay
  remain future opt-in probes because the committed recipe-only smokes prove
  only Wardwright routing, provenance, receipt correlation, fallback honesty,
  and privacy-safe evidence.
- Adversarial review:
  - Architecture: no blocker found. The completion pass changes only durable
    docs and supervisor state; it does not move framework adapter truth into
    runtime code, local coding-agent adapters, or package-manager side effects.
    The docs mark only the recipe-only foundation complete and keep stronger
    claims scoped to future opt-in probes, so the complete status does not
    overclaim native framework state, streaming, tool-call fidelity, or exact
    replay.
  - Code/comment quality: no blocker found. The added summary is short and
    matches the existing contract wording: framework tiers, provenance,
    receipt propagation, fallback, privacy, and fidelity limits are stated in
    product terms rather than implementation details. No code comments changed.
  - Test quality: no blocker found. This docs-only completion loop reran the
    behavior-focused Gleam contract test and all six framework recipe smokes,
    which are capable of failing for dropped provenance, missing receipt
    capture, wrong model routing, or overclaimed fallback behavior. The tests
    still intentionally do not prove live framework package execution,
    streaming, tool calls, or native state; those gaps remain recorded as
    skipped probes.
- Next open item: none for this Ralph track. Future work should be new cycles:
  live package-manager probes behind opt-in flags, helper-package promotion for
  selected frameworks, streaming receipt propagation, and separate local
  coding-agent follow-ups for OpenCode-native, OpenClaw, and Aider.
