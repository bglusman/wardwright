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

## Privacy

Framework helpers must not persist raw prompts, completions, provider
credentials, admin tokens, bearer tokens, adapter signing secrets, or full
framework traces by default. The committed framework smokes use synthetic
prompt content and return only sanitized evidence: model ids, receipt id,
provenance ids, fidelity label, framework metadata paths, and fallback status.

## Next Targets

The remaining first-class framework targets are Pydantic AI, OpenAI Agents SDK
on Chat Completions, Microsoft.Extensions.AI with Semantic Kernel guidance, and
LlamaIndex. Each target needs its own runnable smoke before Wardwright claims
framework-aware support.
