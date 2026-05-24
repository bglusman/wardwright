---
layout: default
title: Framework Adapters
description: Framework integration status, recipes, smoke evidence, and fidelity limits.
---

# Framework Adapters

Status: framework adapter validation is active. The shared contract is
`wardwright.framework_adapter.v0`.

Framework adapters are separate from local coding-agent adapters. OpenCode,
OpenClaw, Pi, OMP, Aider, Claude Code, and Codex stay documented in
[`agent-adapters.md`](agent-adapters.html). This page covers SDK and
application-framework integrations such as Vercel AI SDK, LangChain,
LangGraph, Pydantic AI, OpenAI Agents SDK, Microsoft.Extensions.AI, Semantic
Kernel, and LlamaIndex.

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
- streaming support is deferred instead of implied.

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
- LangGraph checkpoint durability and streaming support are deferred instead
  of implied.

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
`ChatResponse.AdditionalProperties`. It does not ship a NuGet package, does
not execute the real Microsoft.Extensions.AI package in the default smoke, and
does not claim streaming, tool-calling, Semantic Kernel planner behavior,
native framework state, or exact replay fidelity.

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
packages or requiring a `dotnet` runtime. That smoke proves:

- a stable Wardwright model id is requested;
- caller provenance reaches Wardwright as headers;
- `x-wardwright-receipt-id` is captured in Microsoft.Extensions.AI-style
  `ChatResponse.AdditionalProperties`;
- Semantic Kernel is documented as guidance on the same `IChatClient` path,
  not as separate planner or native-state support;
- generic OpenAI-compatible fallback still works without claiming
  framework-aware receipt propagation;
- .NET package execution, streaming, tool calling, Semantic Kernel filters,
  and native framework state are deferred instead of implied.

## Privacy

Framework helpers must not persist raw prompts, completions, provider
credentials, admin tokens, bearer tokens, adapter signing secrets, or full
framework traces by default. The committed framework smokes use synthetic
prompt content and return only sanitized evidence: model ids, receipt id,
provenance ids, fidelity label, framework metadata paths, and fallback status.

## Next Targets

The remaining first-class framework target is LlamaIndex. It needs its own
runnable smoke before Wardwright claims framework-aware support.
