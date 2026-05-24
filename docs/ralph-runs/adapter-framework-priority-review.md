---
title: Adapter Framework Priority Review
---

# Adapter Framework Priority Review

Date: 2026-05-23T22:37-04:00.

This review scopes the next adapter work after the local install-validation
loop. It treats "adapter" broadly: a framework adapter may be a package,
provider factory, middleware, callback, tracing processor, starter, or recipe
when the framework does not expose a durable local install surface.

The goal is not to support every popular project first. The goal is to choose
the few surfaces where Wardwright can provide a better-than-generic experience
with modest effort: stable model naming, caller provenance, policy/governance,
receipt correlation, and honest replay/fidelity labels.

## Decision Criteria

- Adoption signal: package downloads, GitHub activity, platform visibility, or
  enterprise relevance.
- Clean integration point: OpenAI-compatible base URL/client injection,
  provider abstraction, middleware, callback, tracing, advisor, plugin, or
  state/checkpoint hook.
- Wardwright value beyond a README snippet: provenance headers, receipt lookup,
  policy/routing evidence, replay/checkpoint correlation, or verified adapter
  identity.
- Modest first slice: can be tested without owning the host framework's whole
  runtime, memory, planner, or UI.
- Fidelity discipline: no claims that Wardwright can import hidden framework
  state unless a real framework hook proves it.

## Recommended First-Class Shortlist

1. **LangChain and LangGraph**
   - Why: LangChain remains the broadest agent/framework gravity well, and
     LangGraph adds explicit state/checkpoint semantics that map well to
     Wardwright receipts and replay evidence.
   - Hooks: OpenAI-compatible model configuration, custom middleware/callbacks,
     LangGraph checkpointers, thread/checkpoint history.
   - First slice: `wardwright-langchain` recipes or helpers for Python and
     TypeScript that configure Wardwright as the model endpoint, inject caller
     provenance, and attach Wardwright receipt ids to LangChain/LangGraph run
     metadata or checkpoints.
   - Risk: LangChain and LangGraph may transform prompts, messages, and tool
     calls before the model request. Receipts must say whether they represent
     framework-normalized model input, not raw user intent.
   - Sources:
     <https://docs.langchain.com/oss/python/langchain-models>,
     <https://docs.langchain.com/oss/python/langchain/middleware/custom>,
     <https://docs.langchain.com/oss/python/langgraph/persistence>,
     <https://docs.langchain.com/oss/javascript/langchain/middleware>,
     <https://docs.langchain.com/oss/javascript/langgraph/persistence>.

2. **Vercel AI SDK**
   - Why: It has very large JavaScript/TypeScript install signal, a clean model
     provider abstraction, and it is adjacent to OpenCode's provider model.
   - Hooks: OpenAI-compatible provider/base URL, `customProvider`,
     `wrapLanguageModel` middleware, and OpenTelemetry metadata.
   - First slice: `@wardwright/ai-sdk-provider` or a small provider/middleware
     package that points model calls at Wardwright, injects caller provenance,
     and captures receipt ids from response headers.
   - Risk: The AI SDK is a client/model layer rather than a durable workflow
     runtime; replay or session import should remain outside this adapter.
   - Sources:
     <https://vercel.com/docs/ai-gateway/sdks-and-apis>,
     <https://v5.ai-sdk.dev/docs/reference/ai-sdk-core/custom-provider>,
     <https://v5.ai-sdk.dev/docs/ai-sdk-core/middleware>,
     <https://v5.ai-sdk.dev/docs/ai-sdk-core/telemetry>.

3. **Pydantic AI**
   - Why: It has high current Python adoption, typed agent concepts, dependency
     injection, usage controls, graph support, and clean provider configuration.
   - Hooks: `OpenAIProvider(base_url=...)`, custom provider/client injection,
     typed dependencies, graph persistence, and OpenTelemetry instrumentation.
   - First slice: a `WardwrightProvider` wrapper or recipe that configures the
     OpenAI-compatible endpoint, exposes typed caller/receipt fields, and maps
     Wardwright model capability notes into Pydantic AI usage/structured-output
     guidance.
   - Risk: Structured output and tool-call fidelity depend on Wardwright's
     downstream model capability contract. The adapter should fail clearly when
     a selected Wardwright model cannot preserve a requested feature.
   - Sources:
     <https://pydantic.dev/docs/ai/models/openai/>,
     <https://pydantic.dev/docs/ai/core-concepts/agent/>,
     <https://pydantic.dev/docs/ai/graph/graph/>,
     <https://pydantic.dev/docs/ai/api/pydantic-ai/capabilities/>.

4. **OpenAI Agents SDK**
   - Why: It is a high-velocity official agent SDK with agents, tools,
     handoffs, sessions, guardrails, and tracing.
   - Hooks: OpenAI-compatible Chat Completions model configuration,
     non-OpenAI model providers, environment/config base URL settings, and
     custom tracing processors.
   - First slice: a Chat Completions-focused Wardwright recipe plus a tracing
     processor that correlates OpenAI Agents spans to Wardwright receipt ids.
   - Risk: The default Responses API path may exceed Wardwright's current
     OpenAI-compatible serving surface. Start with the Chat Completions path and
     do not claim full Agents SDK parity until `/v1/responses` behavior is
     intentionally supported.
   - Sources:
     <https://openai.github.io/openai-agents-python/agents/>,
     <https://openai.github.io/openai-agents-python/models/>,
     <https://openai.github.io/openai-agents-python/config/>,
     <https://openai.github.io/openai-agents-python/tracing/>.

5. **Microsoft.Extensions.AI and Semantic Kernel**
   - Why: .NET is not represented in the current local-agent work, but the
     adoption and enterprise fit are too large to ignore. `Microsoft.Extensions.AI`
     is the cleaner low-level target; Semantic Kernel is the higher-level
     orchestration/plugin layer.
   - Hooks: `IChatClient`, `ChatClientBuilder` middleware,
     `DelegatingChatClient`, OpenAI client adapters, OpenTelemetry, Semantic
     Kernel OpenAI chat completion configuration, plugins, and filters.
   - First slice: a small `AddWardwrightChatClient(...)` extension plus optional
     Semantic Kernel filter/plugin examples that attach caller provenance and
     capture receipt ids.
   - Risk: .NET abstractions are still moving across .NET releases, and
     Semantic Kernel has overlapping governance/plugin concepts. Wardwright
     should stay the governed model endpoint and receipt source, not become a
     second planner.
   - Sources:
     <https://learn.microsoft.com/en-us/dotnet/ai/ichatclient>,
     <https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.ai.openaiclientextensions>,
     <https://learn.microsoft.com/en-us/semantic-kernel/concepts/kernel>,
     <https://learn.microsoft.com/en-gb/semantic-kernel/concepts/enterprise-readiness/filters>.

6. **LlamaIndex**
   - Why: It is still a major RAG/agent framework, and Wardwright's receipts can
     complement retrieval and model-call lineage without owning index internals.
   - Hooks: OpenAI/OpenAI-like LLM `api_base` configuration, custom HTTP
     clients, callback manager, observability/instrumentation, tools and
     workflows.
   - First slice: recipe plus callback handler that routes LlamaIndex model
     calls through Wardwright and correlates retrieval/tool context to receipt
     metadata.
   - Risk: LlamaIndex's core value is retrieval lineage and index behavior.
     Wardwright should not duplicate index internals in receipts.
   - Sources:
     <https://docs.llamaindex.ai/en/stable/api_reference/llms/openai/>,
     <https://docs.llamaindex.ai/en/stable/api_reference/llms/openai_like/>,
     <https://docs.llamaindex.ai/en/stable/api_reference/callbacks/>,
     <https://docs.llamaindex.ai/en/latest/module_guides/observability/>.

## Keep First-Class Local Agent Tracks Separate

The SDK/framework shortlist does not replace the local coding-agent work.

- **OpenCode** remains first-class as its own surface. Current Wardwright
  support covers Pi/OMP-backed OpenCode and explicit OpenCode surface probing.
  Future work should package the OpenCode-native plugin/import scaffold and
  preserve `session_import_best_effort` until stronger tests prove more.
  Sources: <https://opencode.ai/docs/providers/>,
  <https://opencode.ai/docs/config>.
- **OpenClaw** remains first-class and distinct from OpenCode. First-class
  support means Wardwright-governed OpenClaw runs with accurate runtime
  provenance, especially separate Pi and native Codex paths. Do not collapse
  OpenClaw into OpenCode. Sources:
  <https://docs.openclaw.ai/plugins/codex-harness>,
  <https://docs.openclaw.ai/providers/litellm>,
  <https://docs.openclaw.ai/plugins/codex-native-plugins>.
- **Aider** is worth a CLI-handoff track, not a deep runtime adapter. It can
  use OpenAI-compatible base URL and model settings, but native session import
  should not be claimed. Sources:
  <https://aider.chat/docs/config/options.html>,
  <https://aider.chat/docs/config/adv-model-settings.html>.

## Watch Or Recipe-Only Candidates

- **CrewAI**: useful role/task/crew audience, but likely docs/config first
  because LiteLLM and memory/task orchestration can obscure model-call truth.
  Sources: <https://docs.crewai.com/en/learn/llm-connections>,
  <https://docs.crewai.com/en/concepts/memory>.
- **Agno**: strong hooks and sessions, but fast-moving and overlapping control
  plane. Watch for user pull. Sources: <https://docs.agno.com/sdk>,
  <https://docs.agno.com/hooks/overview>.
- **AutoGen and AG2**: split ecosystem. Support both with separate config
  examples before writing one "AutoGen adapter." Sources:
  <https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/models.html>,
  <https://docs.ag2.ai/latest/docs/api-reference/autogen/OpenAIWrapper/>.
- **DSPy**: good docs-only target for optimization/eval-heavy users. A deep
  adapter is low ROI until receipt-aware optimizer/eval workflows are requested.
  Source: <https://dspy.ai/>.
- **Haystack**: enterprise RAG candidate; begin with `OpenAIChatGenerator`
  configuration and optional receipt component. Sources:
  <https://docs.haystack.deepset.ai/docs/openaigenerator>,
  <https://docs.haystack.deepset.ai/docs/agent>.
- **Mastra**: plausible TypeScript recipe/provider target, but its runtime,
  storage, memory, traces, and router overlap Wardwright's own product
  vocabulary. Sources: <https://mastra.ai/docs/server-db/storage>,
  <https://mastra.ai/docs/workflows/suspend-and-resume>.
- **Spring AI and LangChain4j**: strong Java second wave. Spring AI has the
  better Spring-native advisor/config story; LangChain4j has broader Java
  agent/RAG patterns. Sources:
  <https://docs.spring.io/spring-ai/reference/api/chat/openai-chat.html>,
  <https://docs.spring.io/spring-ai/reference/api/advisors.html>,
  <https://docs.langchain4j.dev/integrations/language-models/openai-compatible>,
  <https://docs.langchain4j.dev/tutorials/observability>.
- **n8n, Dify, Flowise**: visually important platforms, but integration should
  start as templates/plugins only after the SDK adapters are real. Sources:
  <https://docs.n8n.io/advanced-ai/langchain/langchain-n8n/>,
  <https://docs.dify.ai/en/develop-plugin/getting-started/choose-plugin-type>,
  <https://docs.flowiseai.com/contributing/building-node>.
- **OpenHands**: important coding-agent platform; route through OpenAI/LiteLLM
  configuration first, avoid native resume claims. Sources:
  <https://docs.openhands.dev/modules/usage/llms/openai-llms>,
  <https://docs.openhands.dev/sdk/arch/llm>.
- **CloudWeGo Eino and Genkit**: watch for Go-oriented demand. Sources:
  <https://www.cloudwego.io/docs/eino/overview/>,
  <https://genkit.dev/go/docs/plugin-authoring>.
- **Open Interpreter**: easy endpoint recipe, but low priority because local
  computer-control safety and action-state semantics are the real issue.
  Source: <https://docs.openinterpreter.com/language-models/local-models/custom-endpoint>.
- **AutoGPT**: do not prioritize now. Its current platform/block shape does
  not expose a better modest Wardwright adapter target than the options above.
  Source: <https://docs.agpt.co/platform/blocks/blocks/>.
- **smolagents**: recipe only. Source:
  <https://huggingface.co/docs/smolagents/en/index>.

## Proposed Ralph Cycle Order

1. **Framework adapter contract foundation**: define SDK adapter tiers, caller
   provenance headers/metadata, receipt-id propagation, versioned recipe shape,
   and the minimum smoke test each framework adapter must pass.
2. **Vercel AI SDK adapter**: provider/middleware package or generated example
   with a local Node smoke proving model calls reach Wardwright and receipt ids
   are captured.
3. **LangChain/LangGraph adapter**: Python first, then TypeScript if the
   provider/middleware shape can be shared. Include graph checkpoint or run
   metadata receipt correlation.
4. **Pydantic AI and OpenAI Agents SDK recipes/adapters**: start with
   Chat Completions and typed provider/tracing hooks. Record any Responses API
   gap explicitly.
5. **.NET adapter**: implement `Microsoft.Extensions.AI` first, then document
   Semantic Kernel on top of it or beside it.
6. **LlamaIndex callback recipe**: route through Wardwright and correlate
   retrieval/tool context with receipts without duplicating index internals.
7. **Local coding-agent follow-ups**: OpenCode-native scaffold, OpenClaw direct
   upstream config discovery, OpenClaw native Codex path, and Aider config
   generation should continue as separate local-agent cycles.

This order intentionally favors small integration packages and recipes before
deep platform plugins. It should be revised only when a candidate exposes a
durable hook that lets Wardwright verify more than generic OpenAI-compatible
traffic.
