#!/usr/bin/env node
import {
  createWardwrightOpenAICompatibleProviderOptions,
} from "./wardwright-ai-sdk.mjs";

const args = parseArgs(process.argv.slice(2));
const baseURL = args["base-url"] || process.env.WARDWRIGHT_GATEWAY_URL;
const model = args.model || "coding-balanced";
const receipts = [];
const provenance = {
  tenantId: "tenant-vercel-smoke",
  applicationId: "app-vercel-ai-sdk",
  consumingAgentId: "agent-vercel-ai-sdk",
  consumingUserId: "user-vercel-smoke",
  sessionId: "session-vercel-smoke",
  runId: "run-vercel-smoke",
  clientRequestId: `vercel-ai-sdk-smoke-${Date.now()}`,
};

try {
  const providerOptions = createWardwrightOpenAICompatibleProviderOptions({
    baseURL,
    provenance,
    receipts,
  });

  const frameworkAware = await chatCompletion({
    fetch: providerOptions.fetch,
    baseURL: providerOptions.baseURL,
    headers: providerOptions.headers,
    model,
  });

  const genericFallback = await chatCompletion({
    fetch: globalThis.fetch,
    baseURL: providerOptions.baseURL,
    headers: {},
    model,
  });

  const receiptId = frameworkAware.response.headers.get("x-wardwright-receipt-id");
  const selectedModel = frameworkAware.response.headers.get("x-wardwright-selected-model");

  assert(frameworkAware.response.ok, "framework-aware request failed");
  assert(genericFallback.response.ok, "generic OpenAI-compatible fallback request failed");
  assert(receiptId, "framework-aware request did not expose x-wardwright-receipt-id");
  assert(
    receipts.some((receipt) => receipt.receiptId === receiptId),
    "Wardwright fetch wrapper did not capture the receipt id",
  );
  assert(selectedModel, "Wardwright did not expose the selected model header");

  const report = {
    framework: "vercel-ai-sdk",
    support_tier: "recipe_only",
    fidelity: "framework_receipt_correlated",
    requested_model: model,
    selected_model: selectedModel,
    receipt_id: receiptId,
    captured_receipts: receipts.map((receipt) => receipt.receiptId),
    provenance,
    fallback: {
      generic_openai_compatible: genericFallback.response.ok,
      adapter_receipt_claim: false,
    },
    streaming: "deferred",
  };

  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  console.error(error.stack || error.message);
  process.exit(1);
}

async function chatCompletion({ fetch, baseURL, headers, model }) {
  const response = await fetch(`${baseURL}/chat/completions`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "user",
          content: "Synthetic Wardwright Vercel AI SDK smoke prompt.",
        },
      ],
    }),
  });

  const body = await response.json();
  const content = body?.choices?.[0]?.message?.content;

  assert(response.ok, `chat completion returned HTTP ${response.status}`);
  assert(typeof content === "string" && content.length > 0, "chat completion did not return text");

  return { body, response };
}

function parseArgs(argv) {
  const parsed = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    if (arg.startsWith("--")) {
      parsed[arg.slice(2)] = argv[index + 1];
      index += 1;
    }
  }

  return parsed;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
