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

## Privacy

Framework helpers must not persist raw prompts, completions, provider
credentials, admin tokens, bearer tokens, adapter signing secrets, or full
framework traces by default. The Vercel smoke uses synthetic prompt content and
returns only sanitized evidence: model ids, receipt id, provenance ids,
fidelity label, and fallback status.

## Next Targets

The remaining first-class framework targets are LangChain/LangGraph, Pydantic
AI, OpenAI Agents SDK on Chat Completions, Microsoft.Extensions.AI with
Semantic Kernel guidance, and LlamaIndex. Each target needs its own runnable
smoke before Wardwright claims framework-aware support.
