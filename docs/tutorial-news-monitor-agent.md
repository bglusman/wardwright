---
layout: default
title: Build A Lightweight News Monitor
description: A tutorial-style Wardwright example for developing and debugging a specialized local-model agent.
---

# Build A Lightweight News Monitor

This tutorial is a concrete use case for Wardwright during development: build a
small news-monitoring agent that screens feed items for PR-relevant articles
about a company, then use Wardwright to validate, debug, and tighten the model
contract before trusting the agent unattended.

The point is not that Wardwright replaces a feed reader, crawler, vector store,
or notification system. The point is that a narrow agent can call one stable
Wardwright model while Wardwright owns the model route, provenance, policy
checks, scenarios, and receipts used to debug why a result was accepted,
ignored, retried, or escalated.

## Example Shape

Assume a developer has a lightweight local model available through an
OpenAI-compatible endpoint, such as an Ollama model or another local runtime.
The agent reads normalized feed items and asks Wardwright:

```text
model: wardwright/pr-news-screener
task: Classify whether this article is PR-relevant for ExampleCo.
```

The agent should send caller provenance on every request:

```text
X-Wardwright-Tenant-Id: exampleco
X-Wardwright-Application-Id: news-monitor
X-Wardwright-Consuming-Agent-Id: pr-feed-screener
X-Wardwright-Session-Id: rss-2026-05-24
X-Wardwright-Run-Id: feed-batch-001
X-Client-Request-Id: article-https-example-com-story-123
```

Those fields make receipts searchable by company, feed run, source article, and
agent build. Without them, a bad result becomes another anonymous model call.

## Wardwright Model Contract

The first Wardwright model should be small and explicit:

- stable public model id: `pr-news-screener`
- primary target: local 4B-class or similarly lightweight model
- fallback target: optional stronger model only when the local model cannot
  produce valid structured output
- structured output: one JSON object per article
- policy behavior: retry invalid JSON once, then fail closed
- receipt behavior: record route, retry, validation, confidence, and caller
  provenance

The expected output should be boring enough to test:

```json
{
  "company": "ExampleCo",
  "article_url": "https://example.test/story",
  "relevant": true,
  "confidence": "medium",
  "reason": "The article discusses a product recall affecting ExampleCo.",
  "risk_tags": ["customer-impact", "reputation"],
  "recommended_action": "review"
}
```

Do not ask the local model to browse, remember the company strategy, or infer
private context. The feed reader supplies article text and metadata. The model
only classifies the item under a reviewed contract.

## Development Loop

1. Run Wardwright locally and open `/admin`.
2. Register or draft `pr-news-screener` with the local target and structured
   output requirement.
3. Save at least four scenarios before wiring real feeds:
   - a clearly relevant article;
   - an unrelated article with the company name in boilerplate;
   - an ambiguous article that should be `review`, not `ignore`;
   - a malformed or unsupported model output that must retry or fail closed.
4. Simulate each scenario in the workbench.
5. Call the model from the feed agent through the OpenAI-compatible API or one
   of the framework recipes.
6. Inspect receipts for route choice, output validation, retry behavior,
   confidence, and caller provenance.
7. Pin any surprising result as a regression case before changing prompts or
   model targets.

This is where Wardwright is useful during development: the developer and an AI
assistant can discuss a failed receipt, draft a narrower rule or output schema,
rerun the scenario, and keep the deterministic model artifact as the reviewed
source of truth.

## Framework Recipe Options

Use the simplest integration that matches the agent:

- **LangChain/LangGraph** if the feed monitor already uses chains, graph state,
  checkpoints, or run metadata. Capture the Wardwright receipt id in run or
  checkpoint metadata so a flagged article points back to the exact model
  decision.
- **Vercel AI SDK** if the monitor is a TypeScript/Node worker. Use the
  OpenAI-compatible provider recipe, inject provenance headers, and capture
  `x-wardwright-receipt-id` in the worker's article result record.
- **Pydantic AI** if the monitor is Python and benefits from typed dependencies
  and structured agent context.
- **OpenAI Agents SDK** only for the Chat Completions-shaped path until
  Wardwright intentionally supports broader Responses API behavior.

The current framework recipes prove provenance and receipt correlation with
app-local smokes. The `0.1.0-rc.1` validation pass also exercised live package
installs for Vercel AI SDK, LangChain/LangGraph, Pydantic AI, OpenAI Agents SDK,
LlamaIndex, and Microsoft.Extensions.AI/Semantic Kernel. Vercel AI SDK
streaming receipt capture is proven through the Wardwright fetch wrapper;
LangChain streaming returns text but did not expose receipt headers in stream
chunk metadata. These recipes still do not prove broad tool-call preservation,
native framework state, retrieval lineage, or exact replay. Treat the first live
feed monitor as an integration test and keep the receipts.

## Debugging A Bad Result

When the agent misses a relevant article, do not start by changing the feed
agent. Start from the receipt:

1. Was the request routed to the intended local model?
2. Did the caller provenance identify the feed, article, run, and agent build?
3. Did the model produce valid structured output?
4. Did confidence or `recommended_action` disagree with the article facts?
5. Did retry or fallback behavior happen?
6. Is there now a saved scenario that reproduces the miss?

If the local model is too weak for the ambiguous cases, the Wardwright model can
route only those cases to a stronger target, or it can require human review when
confidence is low. That keeps the common case cheap while making the expensive
or uncertain path visible in receipts.

## Release-Quality Evidence

A tutorial like this becomes release-quality when it has:

- a runnable local fixture with synthetic feed items;
- one TypeScript example using the Vercel AI SDK recipe or one Python example
  using the LangChain/LangGraph recipe;
- receipts that show provenance and structured-output validation;
- saved scenarios that fail before the policy/model change and pass after it;
- docs that state which parts are real and which parts are still recipes.

For `0.1.0-rc.1`, the core product claim should stay conservative: Wardwright
can help build, inspect, and debug a specialized lightweight model agent by
owning the model contract and receipts. It should not claim the framework
recipes are published packages or that a local model can monitor live news
without a separate feed ingestion and alerting layer.
