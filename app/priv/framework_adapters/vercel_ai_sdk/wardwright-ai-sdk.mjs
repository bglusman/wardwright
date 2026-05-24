const receiptHeader = "x-wardwright-receipt-id";

const provenanceHeaderNames = {
  tenantId: "x-wardwright-tenant-id",
  tenant_id: "x-wardwright-tenant-id",
  applicationId: "x-wardwright-application-id",
  application_id: "x-wardwright-application-id",
  consumingAgentId: "x-wardwright-agent-id",
  consuming_agent_id: "x-wardwright-agent-id",
  agentId: "x-wardwright-agent-id",
  agent_id: "x-wardwright-agent-id",
  consumingUserId: "x-wardwright-user-id",
  consuming_user_id: "x-wardwright-user-id",
  userId: "x-wardwright-user-id",
  user_id: "x-wardwright-user-id",
  sessionId: "x-wardwright-session-id",
  session_id: "x-wardwright-session-id",
  runId: "x-wardwright-run-id",
  run_id: "x-wardwright-run-id",
  clientRequestId: "x-client-request-id",
  client_request_id: "x-client-request-id",
};

export function wardwrightProvenanceHeaders(provenance = {}) {
  const headers = {};

  for (const [key, headerName] of Object.entries(provenanceHeaderNames)) {
    const value = provenance[key];

    if (value !== undefined && value !== null && String(value).trim() !== "") {
      headers[headerName] = String(value).trim();
    }
  }

  return headers;
}

export function normalizeWardwrightBaseURL(baseURL) {
  if (typeof baseURL !== "string" || baseURL.trim() === "") {
    throw new Error("Wardwright baseURL is required");
  }

  const normalized = baseURL.trim().replace(/\/+$/, "");
  return normalized.endsWith("/v1") ? normalized : `${normalized}/v1`;
}

export function createWardwrightFetch({
  fetch: fetchImplementation = globalThis.fetch,
  provenance = {},
  receipts = [],
  onReceipt,
} = {}) {
  if (typeof fetchImplementation !== "function") {
    throw new Error("A fetch implementation is required for Wardwright AI SDK requests");
  }

  const provenanceHeaders = wardwrightProvenanceHeaders(provenance);

  return async function wardwrightFetch(input, init = {}) {
    const headers = mergeHeaders(input, init.headers, provenanceHeaders);
    const response = await fetchImplementation(input, { ...init, headers });
    const receiptId = response.headers.get(receiptHeader);

    if (receiptId) {
      const evidence = {
        receiptId,
        header: receiptHeader,
        source: "vercel-ai-sdk-fetch",
      };

      receipts.push(evidence);

      if (typeof onReceipt === "function") {
        onReceipt(evidence);
      }
    }

    return response;
  };
}

export function createWardwrightOpenAICompatibleProviderOptions({
  baseURL,
  apiKey,
  provenance = {},
  fetch,
  receipts,
  onReceipt,
} = {}) {
  return {
    name: "wardwright",
    baseURL: normalizeWardwrightBaseURL(baseURL),
    apiKey,
    headers: wardwrightProvenanceHeaders(provenance),
    fetch: createWardwrightFetch({ fetch, provenance, receipts, onReceipt }),
  };
}

function mergeHeaders(input, initHeaders, addedHeaders) {
  const headers = new Headers();

  if (isRequest(input)) {
    copyHeaders(input.headers, headers);
  }

  copyHeaders(initHeaders, headers);

  for (const [key, value] of Object.entries(addedHeaders)) {
    if (!headers.has(key)) {
      headers.set(key, value);
    }
  }

  return headers;
}

function copyHeaders(source, target) {
  if (!source) {
    return;
  }

  for (const [key, value] of new Headers(source).entries()) {
    target.set(key, value);
  }
}

function isRequest(value) {
  return typeof Request !== "undefined" && value instanceof Request;
}
