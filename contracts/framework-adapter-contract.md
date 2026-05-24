---
layout: default
title: Framework Adapter Contract
description: Shared support, provenance, receipt, smoke-test, and fidelity rules for Wardwright SDK and framework adapters.
---

# Framework Adapter Contract

This contract covers SDK and application-framework integrations such as Vercel
AI SDK, LangChain, LangGraph, Pydantic AI, OpenAI Agents SDK,
Microsoft.Extensions.AI, Semantic Kernel, and LlamaIndex. It is separate from
local coding-agent adapters such as OpenCode, OpenClaw, Pi, OMP, Aider, Claude
Code, and Codex.

Framework adapters make framework-owned model calls go through Wardwright as a
governed OpenAI-compatible endpoint. They should preserve caller provenance,
surface Wardwright receipt ids in framework-visible state, and keep replay or
state-fidelity wording honest.

## Contract Version

Pure framework adapter classification logic is versioned as
`wardwright.framework_adapter.v0`.

Local coding-agent install and harness-export contracts keep their own version
namespaces:

- `wardwright.adapter_install.v0`
- `wardwright.harness_adapter.v0`

## Surface Families

| Family | Examples | Rule |
| --- | --- | --- |
| `framework_sdk` | Vercel AI SDK, LangChain, LangGraph, Pydantic AI, OpenAI Agents SDK, Microsoft.Extensions.AI, Semantic Kernel, LlamaIndex | Framework-level helpers, middleware, callbacks, tracing processors, providers, advisors, recipes, or client wrappers. |
| `local_coding_agent` | OpenCode, OpenClaw, Aider, Pi, OMP, Claude Code, Codex | Local agent installation, pairing, probing, import/export, or CLI handoff. Do not collapse these into framework SDK support. |
| `unsupported` | Unknown or unreviewed surfaces | No support claim beyond generic OpenAI-compatible use. |

## Support Tiers

| Tier | Meaning |
| --- | --- |
| `recipe_only` | Documentation or generated sample code configures a framework to call Wardwright. No maintained package is claimed. |
| `helper_package` | A small Wardwright-owned package configures the framework endpoint and metadata fields. |
| `middleware` | The adapter participates in a framework hook such as middleware, callback, tracing processor, advisor, provider wrapper, or delegating client. |
| `native_runtime_adapter` | The framework exposes a stable runtime/state hook and Wardwright has a smoke test proving the stronger behavior. No initial framework adapter should claim this by default. |
| `unsupported` | No reviewed support surface exists. |

When more than one integration point exists, the tier is the strongest behavior
proved by tests, not the strongest hook that appears possible.

## Caller Provenance

Framework adapters should prefer existing Wardwright caller metadata fields
instead of creating framework-specific receipt shapes:

| Wardwright field | HTTP header | Framework mapping examples |
| --- | --- | --- |
| `tenant_id` | `x-wardwright-tenant-id` | workspace, organization, tenant, project |
| `application_id` | `x-wardwright-application-id` | app name, service name, deployment |
| `consuming_agent_id` | `x-wardwright-agent-id` | agent name, graph node, workflow id |
| `consuming_user_id` | `x-wardwright-user-id` | end-user id or synthetic test user |
| `session_id` | `x-wardwright-session-id` | thread id, conversation id, graph thread id |
| `run_id` | `x-wardwright-run-id` | framework run id, trace id, checkpoint id |
| `client_request_id` | `x-client-request-id` | idempotency key or framework request id |

Adapters may also use framework-native metadata, tags, tracing attributes,
callbacks, or checkpoint metadata when that is the framework's idiomatic path.
The gateway-facing request still needs to carry enough provenance for receipts.

## Receipt Propagation

Wardwright returns the receipt id in `x-wardwright-receipt-id`. A framework
adapter is framework-aware only when that id is captured somewhere the framework
user can inspect, such as:

- provider result metadata;
- middleware state;
- callback output;
- trace/span attributes;
- checkpoint or thread metadata;
- adapter-owned local smoke-test output.

Printing a receipt id to an unstructured raw log is acceptable as temporary
evidence for a recipe-only smoke, but it is not enough to claim middleware or
native runtime support.

## Fidelity Labels

| Label | Meaning |
| --- | --- |
| `generic_openai_compatible` | The framework can call Wardwright through a base URL or OpenAI-compatible provider, but provenance or receipt correlation has not been proved. |
| `framework_receipt_correlated` | A smoke test proves the request reached Wardwright, caller provenance reached the gateway, and the framework-visible path captured `x-wardwright-receipt-id`. |
| `native_framework_state_verified` | A smoke test proves framework-native state, checkpoint, trace, or runtime semantics in addition to receipt correlation. This is not claimed unless the framework exposes a stable hook and the test proves it. |
| `unsupported` | The request does not reach Wardwright through a reviewed framework surface. |

These labels do not imply local agent resume or hidden session import. Local
agent handoff and replay fidelity remain covered by
[`agent-harness-adapter-contract.md`](agent-harness-adapter-contract.html) and
[`docs/agent-adapters.md`](../docs/agent-adapters.html).

## Smoke-Test Requirements

Every implemented framework adapter must have a runnable smoke test with
synthetic data and isolated state. A passing smoke must prove:

1. A stable Wardwright model name is used.
2. The model request reaches a packaged or app-local Wardwright gateway.
3. Caller provenance reaches Wardwright through headers or framework metadata
   that the adapter maps to the gateway request.
4. `x-wardwright-receipt-id` is captured in framework-visible state.
5. Adapter-owned files and committed fixtures do not contain provider
   credentials, admin tokens, adapter signing secrets, raw user secrets, or raw
   private prompts/completions.
6. Fallback behavior remains honest: generic OpenAI-compatible configuration
   still works, but does not claim framework-aware receipt propagation,
   adapter-scoped recording, native state import, or exact replay.

Default committed tests should be deterministic and should not fetch external
packages from the network. Live package-manager probes belong behind an
explicit opt-in flag and must use temp caches and synthetic inputs.

## Privacy Rules

Framework adapters must not persist raw prompts, completions, provider
credentials, admin tokens, bearer tokens, adapter signing secrets, or framework
trace payloads by default. Receipt metadata should stay allowlisted and
structured. If a framework exposes rich traces, the adapter should store only
the receipt id, provenance fields, adapter version, framework name/version,
model name, and sanitized status evidence unless a user explicitly opts into a
broader recording mode.

## Current Implementation Status

Vercel AI SDK recipe-only support is backed by an adapter-owned Node smoke. It
uses the AI SDK OpenAI-compatible provider shape: Wardwright is the `baseURL`,
provenance is mapped into Wardwright headers, and a custom `fetch` wrapper
captures `x-wardwright-receipt-id` in framework-visible adapter state.

This proves `framework_receipt_correlated` for the tested non-streaming path.
It does not claim a published npm package, AI SDK middleware ownership,
streaming receipt propagation, Vercel chat UI state, native framework state, or
exact replay fidelity.

LangChain/LangGraph recipe-only support is backed by an adapter-owned Python
smoke. It uses the OpenAI-compatible model configuration path, maps caller
provenance into Wardwright headers, and records the Wardwright receipt id into
LangChain-style run metadata plus LangGraph-style checkpoint metadata.

This proves `framework_receipt_correlated` for the tested non-streaming path.
It does not claim an installed LangChain package, LangGraph checkpoint
durability, native framework state import, streaming receipt propagation, or
exact replay fidelity.

Pydantic AI recipe-only support is backed by an adapter-owned Python smoke. It
uses the OpenAI-compatible `OpenAIProvider(base_url=...)` model configuration
path, maps typed run context into Wardwright provenance headers, and records
the Wardwright receipt id into Pydantic-style run metadata.

This proves `framework_receipt_correlated` for the tested non-streaming path.
It does not claim an installed Pydantic AI package, native state import,
streaming receipt propagation, exact replay fidelity, or structured-output and
tool-call fidelity beyond what Wardwright's model capability contract can prove
in a later slice.
