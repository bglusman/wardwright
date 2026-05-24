---
title: Framework Adapter Validation Requirements
---

# Framework Adapter Validation Requirements

This is the build/test target for the Ralph loop that follows the local adapter
install-validation loop. The local installer loop proved Wardwright can install,
pair, probe, and clean up supported local agent adapters. This loop extends
Wardwright into high-adoption SDK and framework surfaces without weakening the
existing fidelity discipline.

## Release Goal

Wardwright should be able to say:

> Popular agent frameworks can call Wardwright as their governed
> OpenAI-compatible model endpoint, while Wardwright preserves caller
> provenance, policy evidence, receipt correlation, and honest replay/fidelity
> labels.

The release must not claim native framework state import, exact agent resume,
or tool/runtime parity unless a framework-specific smoke test proves it.

## Required Reading

Each loop must read:

- `AGENTS.md`
- `CLAUDE.md`
- `docs/architecture-ratchets.md`
- `docs/testing-ratchets.md`
- `docs/agent-adapters.md`
- `docs/ralph-runs/adapter-framework-priority-review.md`
- this file
- `docs/ralph-runs/framework-adapter-validation-loop-supervisor.md`

## Scope

### Framework Adapter Contract Foundation

Before implementing individual SDK integrations, define the shared framework
adapter contract:

- adapter/support tiers, such as recipe-only, helper package, middleware, and
  native/runtime adapter;
- caller provenance fields and how they map into headers, metadata, callbacks,
  tracing spans, advisors, or framework state;
- receipt-id propagation from Wardwright responses back into
  framework-visible metadata;
- adapter/fidelity wording that distinguishes generic OpenAI-compatible traffic
  from framework-aware integration;
- smoke-test requirements for every framework adapter;
- privacy rules for prompts, completions, credentials, framework traces, and
  local adapter files.

### First-Class Framework Targets

The initial implementation priority is:

1. Vercel AI SDK.
2. LangChain and LangGraph.
3. Pydantic AI.
4. OpenAI Agents SDK, starting with Chat Completions compatibility.
5. Microsoft.Extensions.AI, with Semantic Kernel guidance or follow-up support.
6. LlamaIndex.

The loop may adjust ordering only after recording evidence in the supervisor.

### Local Coding-Agent Tracks

The framework loop must keep local coding-agent surfaces separate from SDK
frameworks:

- OpenCode remains first-class as its own surface.
- OpenClaw remains first-class and distinct from OpenCode.
- OpenClaw Pi and native Codex paths must be proven separately.
- Aider is a CLI-handoff/config target unless a deeper state hook is found.

OpenCode-native, OpenClaw upstream config/native Codex support, and Aider
config generation can become follow-up cycles after the shared framework
contract is in place, but they should not be collapsed into LangChain,
Vercel AI SDK, or other SDK work.

## Integration Test Contract

Every implemented framework adapter must have a runnable smoke test that uses
synthetic data and isolated state. A valid smoke test should:

1. Start a packaged or app-local Wardwright gateway with temp storage,
   receipts, transcripts, and secrets.
2. Create a temp framework project or minimal script.
3. Configure the framework through its native integration point, such as base
   URL, provider, middleware, callback, tracing processor, advisor, or client
   wrapper.
4. Make a small model call with synthetic prompt content.
5. Assert Wardwright receives the request through a stable Wardwright model
   name.
6. Assert caller provenance reaches Wardwright.
7. Assert a Wardwright receipt id is captured in framework-visible state,
   callback output, trace metadata, middleware state, or logs that the adapter
   owns.
8. Assert no provider credentials, admin tokens, raw user secrets, or adapter
   signing secrets are written to committed fixtures or adapter-owned files.
9. Assert fallback behavior remains honest: generic OpenAI-compatible use still
   works without framework adapter helpers, but does not claim framework-aware
   receipt propagation or adapter-scoped recording.

External packages may be installed during local validation only when the loop
uses temp caches and synthetic inputs. Committed tests should be deterministic,
reasonably fast, and should skip external-network package fetches unless an
explicit live-probe flag is set.

## Per-Framework Minimums

### Vercel AI SDK

Minimum support should prove a TypeScript/Node call through a Wardwright
provider or middleware path:

- Wardwright endpoint/model configuration.
- caller provenance injection;
- receipt-id capture from response headers or provider result metadata;
- streaming behavior considered or explicitly deferred.

### LangChain And LangGraph

Minimum support should prove Python first unless TypeScript is clearly smaller:

- model configuration through OpenAI-compatible base URL;
- middleware, callback, or runnable metadata path for provenance;
- receipt-id correlation to a LangChain run and, for LangGraph, a graph run,
  thread, or checkpoint metadata path;
- no claim that Wardwright owns LangGraph checkpoint durability.

### Pydantic AI

Minimum support should prove:

- `OpenAIProvider` or equivalent provider configuration through Wardwright;
- typed caller/provenance dependency or context mapping;
- receipt-id capture;
- clear failure or documented limitation for structured output/tool capability
  mismatches.

### OpenAI Agents SDK

Minimum support should prove:

- Chat Completions path through Wardwright;
- tracing processor or callback correlation to Wardwright receipts;
- explicit note that `/v1/responses` parity is not claimed unless implemented
  and tested.

### Microsoft.Extensions.AI And Semantic Kernel

Minimum support should prove:

- an `IChatClient` or equivalent OpenAI-compatible client path through
  Wardwright;
- middleware or delegating client receipt/provenance correlation;
- Semantic Kernel guidance or filter/plugin support without turning Wardwright
  into a second planner.

### LlamaIndex

Minimum support should prove:

- OpenAI/OpenAI-like LLM configuration through Wardwright;
- callback or instrumentation path for receipt correlation;
- retrieval/tool context correlation only where LlamaIndex exposes it cleanly.

## Documentation Requirements

Documentation must:

- show the exact framework configuration or code snippet;
- state the supported Wardwright version or contract version;
- distinguish recipe-only support from helper-package support;
- explain where receipt ids appear;
- explain what the adapter does not preserve;
- link back to `docs/agent-adapters.md` for local coding-agent adapter
  fidelity limits;
- keep OpenCode and OpenClaw separate.

## Completion Criteria

The loop is complete only when:

- the shared framework adapter contract exists and is documented;
- at least the first selected implementation slice has runnable smoke coverage;
- every implemented framework has behavior-focused tests or a recorded reason
  for deferral;
- docs accurately distinguish first-class, recipe-only, watch, and unsupported
  candidates;
- local coding-agent follow-ups are scoped separately;
- `mise run check:docs` passes;
- focused app tests and smoke tests for touched code pass;
- adversarial reviews for every committed loop are recorded in the supervisor;
- skipped probes are recorded with concrete reasons;
- the local completion sentinel is created:
  `$(git rev-parse --git-path ralph-runs/framework-adapter-validation/complete)`.

Do not create the sentinel while framework adapter implementation or validation
is still making progress.
