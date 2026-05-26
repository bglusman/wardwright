---
layout: default
title: Framework Adapters
description: Framework integration status, recipes, smoke evidence, and fidelity limits.
---

# Framework Adapters

Status: framework adapter validation is complete for the recipe-only
foundation. The shared contract is `wardwright.framework_adapter.v0`.

Framework adapters are separate from local coding-agent adapters. OpenCode,
OpenClaw, Pi, OMP, Aider, Claude Code, and Codex stay documented in
[`agent-adapters.md`](agent-adapters.html). This page covers SDK and
application-framework integrations such as Vercel AI SDK, LangChain,
LangGraph, Pydantic AI, OpenAI Agents SDK, Microsoft.Extensions.AI, Semantic
Kernel, LlamaIndex, and the Jido-backed in-page authoring assistant.

The completed recipe-only track proves a common baseline for each implemented
framework: a stable Wardwright model id is requested, caller provenance reaches
Wardwright, `x-wardwright-receipt-id` is captured in framework-visible
metadata, fallback generic OpenAI-compatible usage stays honest, and privacy
limits are enforced by synthetic app-local smokes. The default test suite does
not install live framework packages. The `0.0.11` release validation pass also
ran live npm/pip package-manager smokes where the local machine had the needed
runtime, plus a Proxmox LXC NuGet smoke for the .NET recipe. None of
those checks prove broad tool-call preservation, native framework state, or
exact replay.

Wardwright also does not claim native framework tool-loop integration through
the OpenAI-compatible Chat Completions recipes. Vercel AI SDK,
LangChain/LangGraph, OpenAI Agents SDK, Microsoft.Extensions.AI, and Semantic
Kernel each have their own local tool execution, provider-hosted tool,
approval, tracing, or graph state semantics. Wardwright `0.0.11` keeps those
semantics visible: it can normalize and receipt request-visible or
provider-exposed tool facts, and it has a minimal Wardwright-hosted server-tool
extension framework with a read-only built-in plus trusted local Dune and BEAM
module extension points, but it does not make those tools participate in
framework-native approval, graph checkpoint, or planner state.

## Current Support And Backlog

The `0.0.11` scope should stay honest about proof level:

| Surface | Status | What is proven | Before claiming more |
| --- | --- | --- | --- |
| Vercel AI SDK | Implemented recipe-only helper and smoke. | OpenAI-compatible provider options route current `ai` and `@ai-sdk/openai-compatible` packages to Wardwright, pass provenance headers, capture `x-wardwright-receipt-id`, and keep generic fallback honest. Current `streamText` also captures the receipt through the same fetch wrapper. | Test tool-call preservation before claiming tool fidelity. |
| LangChain and LangGraph | Implemented recipe-only helper and smoke. | Current `langchain`, `langchain-openai`, and `langgraph` packages can call Wardwright through `ChatOpenAI`, expose receipt headers for non-streaming calls, and carry the receipt through minimal graph state. Current `ChatOpenAI.stream()` returns text but does not expose Wardwright receipt headers in stream chunk metadata. | Test real callbacks/checkpointers before claiming graph durability or streaming receipt correlation. |
| Pydantic AI | Implemented recipe-only helper and smoke. | Current `pydantic-ai` can construct `OpenAIProvider`/`OpenAIChatModel` against Wardwright and run a basic agent call. | Test structured-output and tool-call capability checks before claiming fidelity there. |
| OpenAI Agents SDK | Implemented recipe-only helper and smoke. | Current `openai-agents` can use `OpenAIChatCompletionsModel` with Wardwright without claiming Responses API parity. | Add `/v1/responses` behavior intentionally before claiming full Agents SDK parity. |
| Microsoft.Extensions.AI and Semantic Kernel | Implemented recipe-only Python smoke plus live NuGet smoke. | Current `Microsoft.Extensions.AI.OpenAI`, `OpenAI`, and `Microsoft.SemanticKernel` packages can call Wardwright through `OpenAIChatClient`, and Semantic Kernel can register the same `IChatClient`. The native `ChatResponse` did not expose Wardwright response headers. | Keep receipt correlation behind a delegating or owned HTTP client; test filters/plugins before claiming Semantic Kernel planner/tool fidelity. |
| LlamaIndex | Implemented recipe-only helper and smoke. | Current `llama-index-llms-openai-like` can use `OpenAILike` against Wardwright without claiming index lineage ownership. | Test callbacks/workflows before claiming retrieval/tool fidelity. |
| Jido / Jido AI in-page authoring | Implemented in-product recipe and app-local smoke. | Wardwright's `WardwrightWeb.AuthoringAgent` can run through its Jido-compatible client seam to a local Wardwright `/v1/chat/completions` model, pass caller provenance headers, require the `authoring_tool_plan_v1` structured-output schema in dogfood mode, and capture `x-wardwright-receipt-id` in adapter-visible response metadata. | Test a live `Jido.AI` package call against a released artifact before claiming live package-manager evidence; test `Jido.AI.Agent` tools/streaming before claiming native Jido runtime fidelity. |

The highest-value integration targets for the release are
LangChain/LangGraph and Vercel AI SDK. They now have live package-manager
evidence in addition to app-local smokes. Pydantic AI, OpenAI Agents SDK, and
LlamaIndex also have live basic-call evidence. Jido now has app-local dogfood
evidence through Wardwright's in-page authoring adapter, but it does not yet
have a live external package-manager smoke. The .NET track now has live
NuGet execution evidence for basic chat and Semantic Kernel registration, but
receipt propagation still needs a wrapper because the native response object did
not expose Wardwright headers.

Watch or follow-up candidates remain outside the `0.0.11` support claim:
Alloy/Alloy EX, Gleam `glopenai`, Gleam `starlet`, Gleam `glean`, Aider,
CrewAI, Agno, AutoGen/AG2, DSPy, Haystack, Mastra, Spring AI, LangChain4j, n8n,
Dify, Flowise, OpenHands, CloudWeGo Eino, Genkit, Open Interpreter, AutoGPT,
and smolagents. These should start as recipes or integration tests unless one
of them exposes a durable hook that lets Wardwright verify more than generic
OpenAI-compatible traffic. Current research puts Alloy at recipe-only backlog
because its OpenAI-compatible provider can pass provenance headers but does not
yet expose response headers for receipt correlation. Among Gleam packages,
`glopenai` is the best first recipe candidate because its sans-IO shape lets
the caller own HTTP headers and receipt capture; `starlet` and `glean` need
additional proof before any support claim.

## Live Package-Manager Recipe Checks

On 2026-05-24, the release validation pass started the local
`wardwright_darwin_arm64` Burrito artifact from the `0.0.11` release-prep tree
and ran these package-manager smokes against `http://127.0.0.1:8798/v1`:

- `ai@6.0.191` and `@ai-sdk/openai-compatible@2.0.48`: `generateText` returned
  a completion and the Wardwright fetch wrapper captured a real receipt id. A
  follow-up `streamText` smoke also returned streamed text and captured a real
  receipt id through the same fetch wrapper.
- `langchain@1.3.1`, `langchain-openai@1.2.2`, and `langgraph@1.2.1`:
  `ChatOpenAI` returned a completion with Wardwright response headers, and a
  minimal `StateGraph` carried the receipt id through graph state. A follow-up
  `ChatOpenAI.stream()` smoke returned streamed text, but streamed chunk
  metadata did not expose Wardwright response headers.
- `pydantic-ai@1.102.0`: `OpenAIProvider` and `OpenAIChatModel` ran a basic
  `Agent.run_sync` call against Wardwright.
- `openai-agents@0.17.3`: `OpenAIChatCompletionsModel` and `Runner.run` called
  Wardwright through an `AsyncOpenAI` client. The SDK skipped trace export
  because no OpenAI tracing key was configured; the model call passed.
- `llama-index-llms-openai-like@0.7.2`: `OpenAILike.complete` called
  Wardwright successfully.
- Proxmox LXC Ubuntu 24.04, .NET SDK `8.0.126`,
  `Microsoft.Extensions.AI@10.6.0`, `Microsoft.Extensions.AI.OpenAI@10.6.0`,
  `OpenAI@2.10.0`, and `Microsoft.SemanticKernel@1.76.0`: a real
  `OpenAIChatClient` call reached the released Linux Wardwright artifact and
  Semantic Kernel registered the same `IChatClient`.

The .NET smoke found that `ChatResponse.AdditionalProperties` was empty for the
native `OpenAIChatClient` response, so Wardwright receipt capture still needs
the documented delegating client or another owned HTTP-client wrapper.

## Jido / Jido AI In-Page Authoring

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

Wardwright uses `jido_ai` for the experimental in-page model-authoring
assistant. The integration stays behind `WardwrightWeb.AuthoringAgent` so the
UI, prompt contract, local route selection, structured-output guard, and tool
execution boundary are testable without provider credentials.

Direct-provider mode calls an OpenAI-compatible backend through Jido AI. Dogfood
mode routes the same assistant through a local Wardwright model:

```sh
WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
WARDWRIGHT_AUTHORING_AGENT_ROUTE=wardwright
WARDWRIGHT_AUTHORING_AGENT_MODEL=local-fast-draft
WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY_FILE=/path/to/local/model-key
WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=16384
WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=120000
```

For a local Gemma 4 26B dogfood baseline, register
`config/local-gemma-authoring.model.json` and set
`WARDWRIGHT_AUTHORING_AGENT_MODEL=local-gemma-authoring`. That model routes to
`ollama/gemma4:26b-a4b-it-q4_K_M` with no governance, stream, prompt-transform,
or tool-mediation rules. The structured-output schema is intentionally retained
because the Jido-backed in-page assistant needs Wardwright to validate tool-plan
JSON before it executes authoring tools.

Dogfood mode is intentionally stricter than direct-provider mode. The selected
local Wardwright model must expose
`structured_output.schemas.authoring_tool_plan_v1`, so Wardwright validates the
assistant's `{answer, tool_calls, next_steps}` JSON before read-only or
draft-only authoring tools execute.

The committed `app/test/jido_adapter_smoke_test.exs` smoke starts an app-local
Wardwright router, configures the in-page assistant for the Wardwright route,
uses a Jido-compatible client seam to make a real `/v1/chat/completions`
request, passes synthetic caller provenance headers, and captures
`x-wardwright-receipt-id` in adapter-visible response metadata. That proves the
in-product dogfood path. It does not claim a live package-manager Jido install,
Jido `AgentServer` state, Jido runtime tool registration, streaming receipt
propagation, native Jido telemetry, or exact replay.

## Vercel AI SDK

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

The first Vercel AI SDK slice uses the AI SDK's OpenAI-compatible provider
shape: configure Wardwright as the provider `baseURL`, pass caller provenance
as request headers, and use a custom `fetch` wrapper to capture
`x-wardwright-receipt-id` from Wardwright responses. It does not ship a
published npm package yet, and it does not claim native Vercel runtime state,
chat UI state, streaming resume, or exact replay fidelity.

Install the normal AI SDK dependencies in the framework project:

```bash
npm add ai @ai-sdk/openai-compatible
```

Use Wardwright as an OpenAI-compatible provider:

```js
import { generateText } from "ai";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import {
  createWardwrightOpenAICompatibleProviderOptions,
} from "./wardwright-ai-sdk.mjs";

const capturedReceipts = [];

const wardwright = createOpenAICompatible(
  createWardwrightOpenAICompatibleProviderOptions({
    baseURL: process.env.WARDWRIGHT_GATEWAY_URL ?? "http://127.0.0.1:8787/v1",
    apiKey: process.env.WARDWRIGHT_MODEL_API_KEY,
    receipts: capturedReceipts,
    provenance: {
      tenantId: "example-tenant",
      applicationId: "example-app",
      consumingAgentId: "example-agent",
      consumingUserId: "example-user",
      sessionId: "example-session",
      runId: "example-run",
      clientRequestId: "example-request",
    },
  }),
);

await generateText({
  model: wardwright("coding-balanced"),
  prompt: "Synthetic framework request.",
});

console.log(capturedReceipts.at(-1)?.receiptId);
```

The committed helper source lives at
`app/priv/framework_adapters/vercel_ai_sdk/wardwright-ai-sdk.mjs`. The default
test suite runs a local Node smoke without downloading npm packages. That
smoke starts from the same OpenAI-compatible provider options and proves:

- a stable Wardwright model id is requested;
- caller provenance reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in adapter-owned state;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- streaming receipt capture is proven for `streamText` through the same fetch
  wrapper;
- tool-call preservation is deferred instead of implied.

## LangChain And LangGraph

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

The first LangChain/LangGraph slice uses the OpenAI-compatible model
configuration path: configure Wardwright as the model `base_url`, pass caller
provenance as request headers, and attach a callback-style receipt capture
that writes `x-wardwright-receipt-id` into LangChain-visible run metadata and
LangGraph-visible checkpoint metadata. It does not ship a published Python
package, and it does not claim LangGraph checkpoint durability, native state
import, streaming resume, or exact replay fidelity.

Install normal framework dependencies in the framework project when using the
recipe against real LangChain/LangGraph code:

```bash
pip install langchain langchain-openai langgraph
```

Use Wardwright as the OpenAI-compatible endpoint and keep receipt correlation
in framework metadata:

```python
from wardwright_langchain import (
    WardwrightReceiptCallback,
    chat_completion,
    wardwright_langchain_model_config,
)

run_metadata = {"run_id": "example-run"}
checkpoint_metadata = {"thread_id": "example-thread"}
callback = WardwrightReceiptCallback()

config = wardwright_langchain_model_config(
    base_url="http://127.0.0.1:8787/v1",
    model="coding-balanced",
    provenance={
        "tenant_id": "example-tenant",
        "application_id": "example-app",
        "consuming_agent_id": "example-agent",
        "consuming_user_id": "example-user",
        "session_id": "example-thread",
        "run_id": "example-run",
        "client_request_id": "example-request",
    },
)

chat_completion(
    base_url=config["base_url"],
    model=config["model"],
    headers=config["default_headers"],
    messages=[{"role": "user", "content": "Synthetic framework request."}],
    callback=callback,
    langchain_run_metadata=run_metadata,
    langgraph_checkpoint_metadata=checkpoint_metadata,
)

print(run_metadata["wardwright_receipt_id"])
print(checkpoint_metadata["wardwright"]["receipt_id"])
```

The committed helper source lives at
`app/priv/framework_adapters/langchain_langgraph/wardwright_langchain.py`. The
default test suite runs a local Python smoke without downloading packages.
That smoke proves:

- a stable Wardwright model id is requested;
- caller provenance reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in LangChain-style run metadata;
- the same receipt id is present in LangGraph-style checkpoint metadata;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- LangGraph checkpoint durability is deferred instead of implied;
- streaming text is proven for `ChatOpenAI.stream()`, but streaming receipt
  capture is not proven because current chunk metadata did not expose
  Wardwright response headers.

## Pydantic AI

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

The first Pydantic AI slice uses the documented OpenAI-compatible provider
path: configure `OpenAIChatModel` with `OpenAIProvider(base_url=...)`, carry
typed caller context through the run, map that context into Wardwright
provenance headers, and attach `x-wardwright-receipt-id` to Pydantic-style run
metadata. It does not ship a published Python package, and it does not claim
native Pydantic AI state import, graph durability, structured-output fidelity,
tool-call fidelity, streaming resume, or exact replay fidelity.

Install normal framework dependencies in the framework project when using the
recipe against real Pydantic AI code:

```bash
pip install pydantic-ai
```

Use Wardwright as the OpenAI-compatible provider and keep receipt correlation
in run metadata:

```python
from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider
import os
from wardwright_pydantic_ai import (
    WardwrightPydanticContext,
    WardwrightPydanticReceiptCapture,
    wardwright_pydantic_ai_model_config,
)

context = WardwrightPydanticContext(
    tenant_id="example-tenant",
    application_id="example-app",
    consuming_agent_id="example-agent",
    consuming_user_id="example-user",
    session_id="example-session",
    run_id="example-run",
    client_request_id="example-request",
)
config = wardwright_pydantic_ai_model_config(
    base_url="http://127.0.0.1:8787/v1",
    model="coding-balanced",
    context=context,
)
receipt_capture = WardwrightPydanticReceiptCapture()
run_metadata = {"deps": config["deps"]}

provider_args = {"base_url": config["provider"]["base_url"]}
api_key = os.environ.get(config["provider"]["api_key_env"])
if api_key:
    provider_args["api_key"] = api_key

model = OpenAIChatModel(
    config["model"],
    provider=OpenAIProvider(**provider_args),
)
agent = Agent(model, deps_type=type(context))

# In real Pydantic AI code, pass context as deps and use a model/provider hook
# or owned HTTP client wrapper to add config["default_headers"] and call
# receipt_capture.capture(...) with the response headers.
```

The committed helper source lives at
`app/priv/framework_adapters/pydantic_ai/wardwright_pydantic_ai.py`. The
default test suite runs a local Python smoke without downloading packages.
That smoke proves:

- a stable Wardwright model id is requested;
- caller provenance from typed context reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in Pydantic-style run metadata;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- structured-output and tool-call fidelity are explicitly limited to the
  future Wardwright model capability contract rather than implied by the
  recipe;
- native state import and streaming support are deferred instead of implied.

## OpenAI Agents SDK

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

The first OpenAI Agents SDK slice uses the Chat Completions-compatible model
path: configure an OpenAI client with Wardwright as `base_url`, pass caller
provenance as request headers, and attach `x-wardwright-receipt-id` to
tracing-processor-style trace metadata and generation span metadata. It does
not ship a published Python package, and it does not claim `/v1/responses`
parity, native Agents sessions, tool-call fidelity, streaming resume, native
state import, or exact replay fidelity.

Install the normal Agents SDK dependency in the framework project when using
the recipe against real OpenAI Agents SDK code:

```bash
pip install openai-agents
```

Use Wardwright as the Chat Completions endpoint and keep receipt correlation
in tracing metadata:

```python
from openai import AsyncOpenAI
from agents import Agent, RunConfig, Runner, set_trace_processors
from agents.models.openai_chatcompletions import OpenAIChatCompletionsModel
import os
from wardwright_openai_agents import (
    WardwrightAgentsContext,
    WardwrightAgentsTraceProcessor,
    wardwright_openai_agents_config,
)

context = WardwrightAgentsContext(
    tenant_id="example-tenant",
    application_id="example-app",
    consuming_agent_id="example-agent",
    consuming_user_id="example-user",
    session_id="example-session",
    run_id="example-run",
    client_request_id="example-request",
)
config = wardwright_openai_agents_config(
    base_url="http://127.0.0.1:8787/v1",
    model="coding-balanced",
    context=context,
)
processor = WardwrightAgentsTraceProcessor()
set_trace_processors([processor])

client_args = {
    "base_url": config["model"]["client"]["base_url"],
    "default_headers": config["model"]["client"]["default_headers"],
}
api_key = os.environ.get(config["model"]["client"]["api_key_env"])
if api_key:
    client_args["api_key"] = api_key

model = OpenAIChatCompletionsModel(
    model=config["model"]["model"],
    openai_client=AsyncOpenAI(**client_args),
)
agent = Agent(name=config["agent"]["name"], model=model)

# In real Agents SDK code, run with tracing configured not to include sensitive
# data, then call processor.capture_generation(...) from an owned tracing or
# client wrapper when the Wardwright response headers are available.
await Runner.run(
    agent,
    "Synthetic framework request.",
    run_config=RunConfig(
        trace_include_sensitive_data=config["run_config"]["trace_include_sensitive_data"],
    ),
)
```

The committed helper source lives at
`app/priv/framework_adapters/openai_agents_sdk/wardwright_openai_agents.py`.
The default test suite runs a local Python smoke without downloading packages.
That smoke proves:

- a stable Wardwright model id is requested through the Chat Completions path;
- caller provenance reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in trace metadata and generation span
  metadata;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- `/v1/responses` parity, native Agents sessions, tools, and streaming support
  are deferred instead of implied.

## Microsoft.Extensions.AI And Semantic Kernel

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

The first Microsoft.Extensions.AI slice uses the `IChatClient` pipeline shape:
configure the underlying OpenAI-compatible chat client with Wardwright as the
`base_url`, pass caller provenance as request headers, and wrap the client with
a delegating client that copies `x-wardwright-receipt-id` into
`ChatResponse.AdditionalProperties`. It does not ship a NuGet package and does
not claim native header propagation from `OpenAIChatClient`, streaming,
tool-calling, Semantic Kernel planner behavior, native framework state, or
exact replay fidelity.

Install normal .NET dependencies in the framework project when using the
recipe against real Microsoft.Extensions.AI or Semantic Kernel code:

```bash
dotnet add package Microsoft.Extensions.AI
dotnet add package Microsoft.Extensions.AI.OpenAI
dotnet add package OpenAI
dotnet add package Microsoft.SemanticKernel
```

Use Wardwright as the governed OpenAI-compatible endpoint and keep receipt
correlation in chat response metadata:

```csharp
using Microsoft.Extensions.AI;
using OpenAI;
using System.ClientModel;

var apiKey = Environment.GetEnvironmentVariable("WARDWRIGHT_MODEL_API_KEY");
ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);

var provenanceHeaders = new Dictionary<string, string>
{
    ["x-wardwright-tenant-id"] = "example-tenant",
    ["x-wardwright-application-id"] = "example-app",
    ["x-wardwright-agent-id"] = "example-agent",
    ["x-wardwright-user-id"] = "example-user",
    ["x-wardwright-session-id"] = "example-session",
    ["x-wardwright-run-id"] = "example-run",
    ["x-client-request-id"] = "example-request",
};

var openAI = new OpenAIClient(
    credential: new ApiKeyCredential(apiKey),
    options: new OpenAIClientOptions
    {
        Endpoint = new Uri("http://127.0.0.1:8787/v1"),
    }
);

IChatClient client = openAI
    .GetChatClient("coding-balanced")
    .AsIChatClient();

client = new WardwrightReceiptDelegatingChatClient(
    client,
    provenanceHeaders
);

ChatResponse response = await client.GetResponseAsync(
    "Synthetic framework request."
);

Console.WriteLine(response.AdditionalProperties?["wardwright_receipt_id"]);
```

Semantic Kernel should sit on top of the same Wardwright-configured
`IChatClient` path. Use `IFunctionInvocationFilter`, `IPromptRenderFilter`, or
`IAutoFunctionInvocationFilter` only for Semantic Kernel-owned function or
prompt visibility. Those filters do not make Wardwright a second planner and
do not prove kernel state import.

The committed helper source lives at
`app/priv/framework_adapters/microsoft_extensions_ai/wardwright_microsoft_extensions_ai.py`.
The default test suite runs a local Python smoke without downloading NuGet
packages or requiring a `dotnet` runtime. The Proxmox LXC smoke installed the
current NuGet packages and proved that:

- a released Linux Wardwright artifact serves the OpenAI-compatible endpoint;
- `OpenAIClient.GetChatClient("coding-balanced").AsIChatClient()` returns a
  working `Microsoft.Extensions.AI.OpenAIChatClient`;
- `ChatResponse.Text` contains a Wardwright completion;
- Semantic Kernel can register and resolve that same `IChatClient`;
- native `ChatResponse.AdditionalProperties` is empty for this path, so
  Wardwright receipt capture still needs a delegating or owned HTTP wrapper.

Together, the default and live smokes prove:

- a stable Wardwright model id is requested;
- caller provenance reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in Microsoft.Extensions.AI-style
  `ChatResponse.AdditionalProperties` when using the Wardwright-owned helper
  wrapper;
- Semantic Kernel is documented as guidance on the same `IChatClient` path,
  not as separate planner or native-state support;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- streaming, tool calling, Semantic Kernel filters, and native framework state
  are deferred instead of implied.

## LlamaIndex

Current support tier: `recipe_only`.

Current fidelity label after the committed smoke passes:
`framework_receipt_correlated`.

The first LlamaIndex slice uses the OpenAI-compatible `OpenAILike` path:
configure Wardwright as `api_base`, pass caller provenance as request headers,
and attach `x-wardwright-receipt-id` to callback-style LLM event metadata and
retrieval-context metadata. It does not ship a Python package, does not execute
the real LlamaIndex package in the default smoke, and does not claim retrieval
lineage ownership, index durability, native framework state, tool-call
fidelity, streaming resume, or exact replay fidelity.

Install normal LlamaIndex dependencies in the framework project when using the
recipe against real LlamaIndex code:

```bash
pip install llama-index llama-index-llms-openai-like
```

Use Wardwright as the governed OpenAI-compatible endpoint and keep receipt
correlation in callback-visible metadata:

```python
from llama_index.llms.openai_like import OpenAILike
import os
from wardwright_llamaindex import (
    WardwrightLlamaIndexCallback,
    WardwrightLlamaIndexContext,
    wardwright_llamaindex_config,
)

context = WardwrightLlamaIndexContext(
    tenant_id="example-tenant",
    application_id="example-app",
    consuming_agent_id="example-agent",
    consuming_user_id="example-user",
    session_id="example-query",
    run_id="example-run",
    client_request_id="example-request",
)
config = wardwright_llamaindex_config(
    base_url="http://127.0.0.1:8787/v1",
    model="coding-balanced",
    context=context,
)
callback = WardwrightLlamaIndexCallback()

llm_args = {
    "model": config["llm"]["model"],
    "api_base": config["llm"]["api_base"],
    "is_chat_model": config["llm"]["is_chat_model"],
    "is_function_calling_model": config["llm"]["is_function_calling_model"],
    "context_window": config["llm"]["context_window"],
    "default_headers": config["llm"]["default_headers"],
}
api_key = os.environ.get(config["llm"]["api_key_env"])
if api_key:
    llm_args["api_key"] = api_key

llm = OpenAILike(**llm_args)
llm_event_metadata = {"query_id": context.session_id}
retrieval_context_metadata = {"query_id": context.session_id}

# In real LlamaIndex code, call through the configured LLM and invoke
# callback.capture(...) from a LlamaIndex callback handler or owned HTTP
# wrapper when the Wardwright response headers are available.
```

The committed helper source lives at
`app/priv/framework_adapters/llamaindex/wardwright_llamaindex.py`. The default
test suite runs a local Python smoke without downloading packages. That smoke
proves:

- a stable Wardwright model id is requested;
- caller provenance reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in LlamaIndex-style LLM event
  metadata;
- the same receipt id is available in retrieval-context metadata without
  claiming retrieval lineage or index state ownership;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- streaming, tool calling, retrieval lineage, and native framework state are
  deferred instead of implied.

## Privacy

Framework helpers must not persist raw prompts, completions, provider
credentials, admin tokens, bearer tokens, adapter signing secrets, or full
framework traces by default. The committed framework smokes use synthetic
prompt content and return only sanitized evidence: model ids, receipt id,
provenance ids, fidelity label, framework metadata paths, and fallback status.
