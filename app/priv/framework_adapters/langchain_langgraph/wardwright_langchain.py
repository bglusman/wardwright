from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Mapping


RECEIPT_HEADER = "x-wardwright-receipt-id"
SELECTED_MODEL_HEADER = "x-wardwright-selected-model"

PROVENANCE_HEADER_NAMES = {
    "tenant_id": "x-wardwright-tenant-id",
    "tenantId": "x-wardwright-tenant-id",
    "application_id": "x-wardwright-application-id",
    "applicationId": "x-wardwright-application-id",
    "consuming_agent_id": "x-wardwright-agent-id",
    "consumingAgentId": "x-wardwright-agent-id",
    "agent_id": "x-wardwright-agent-id",
    "agentId": "x-wardwright-agent-id",
    "consuming_user_id": "x-wardwright-user-id",
    "consumingUserId": "x-wardwright-user-id",
    "user_id": "x-wardwright-user-id",
    "userId": "x-wardwright-user-id",
    "session_id": "x-wardwright-session-id",
    "sessionId": "x-wardwright-session-id",
    "run_id": "x-wardwright-run-id",
    "runId": "x-wardwright-run-id",
    "client_request_id": "x-client-request-id",
    "clientRequestId": "x-client-request-id",
}


@dataclass
class WardwrightReceiptCallback:
    receipts: list[dict[str, str]] = field(default_factory=list)

    def capture(
        self,
        headers: Mapping[str, str],
        *,
        langchain_run_metadata: dict[str, Any] | None = None,
        langgraph_checkpoint_metadata: dict[str, Any] | None = None,
    ) -> str | None:
        receipt_id = header_value(headers, RECEIPT_HEADER)

        if not receipt_id:
            return None

        evidence = {
            "receipt_id": receipt_id,
            "header": RECEIPT_HEADER,
            "source": "langchain-callback-metadata",
        }
        self.receipts.append(evidence)

        if langchain_run_metadata is not None:
            langchain_run_metadata["wardwright_receipt_id"] = receipt_id
            langchain_run_metadata["wardwright_fidelity"] = "framework_receipt_correlated"

        if langgraph_checkpoint_metadata is not None:
            langgraph_checkpoint_metadata.setdefault("wardwright", {})
            langgraph_checkpoint_metadata["wardwright"].update(
                {
                    "receipt_id": receipt_id,
                    "fidelity": "framework_receipt_correlated",
                    "native_checkpoint_durability_claimed": False,
                }
            )

        return receipt_id


def wardwright_provenance_headers(provenance: Mapping[str, Any] | None = None) -> dict[str, str]:
    headers: dict[str, str] = {}

    for key, header_name in PROVENANCE_HEADER_NAMES.items():
        value = (provenance or {}).get(key)

        if value is not None and str(value).strip():
            headers[header_name] = str(value).strip()

    return headers


def normalize_wardwright_base_url(base_url: str) -> str:
    if not isinstance(base_url, str) or not base_url.strip():
        raise ValueError("Wardwright base URL is required")

    normalized = base_url.strip().rstrip("/")
    return normalized if normalized.endswith("/v1") else f"{normalized}/v1"


def wardwright_langchain_model_config(
    *,
    base_url: str,
    model: str,
    provenance: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "base_url": normalize_wardwright_base_url(base_url),
        "model": model,
        "default_headers": wardwright_provenance_headers(provenance),
        "metadata": {
            "wardwright_contract": "wardwright.framework_adapter.v0",
            "wardwright_support_tier": "recipe_only",
        },
    }


def chat_completion(
    *,
    base_url: str,
    model: str,
    messages: list[dict[str, str]],
    headers: Mapping[str, str] | None = None,
    callback: WardwrightReceiptCallback | None = None,
    langchain_run_metadata: dict[str, Any] | None = None,
    langgraph_checkpoint_metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = json.dumps({"model": model, "messages": messages}).encode("utf-8")
    request_headers = {"content-type": "application/json", **dict(headers or {})}
    request = urllib.request.Request(
        f"{normalize_wardwright_base_url(base_url)}/chat/completions",
        data=payload,
        headers=request_headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            body = json.loads(response.read().decode("utf-8"))
            response_headers = dict(response.headers.items())
            status = response.status
    except urllib.error.HTTPError as error:
        body = json.loads(error.read().decode("utf-8") or "{}")
        response_headers = dict(error.headers.items())
        status = error.code

    if callback is not None:
        callback.capture(
            response_headers,
            langchain_run_metadata=langchain_run_metadata,
            langgraph_checkpoint_metadata=langgraph_checkpoint_metadata,
        )

    content = body.get("choices", [{}])[0].get("message", {}).get("content")

    return {
        "ok": 200 <= status < 300,
        "status": status,
        "content": content,
        "body": body,
        "receipt_id": header_value(response_headers, RECEIPT_HEADER),
        "selected_model": header_value(response_headers, SELECTED_MODEL_HEADER),
    }


def header_value(headers: Mapping[str, str], name: str) -> str | None:
    wanted = name.lower()

    for key, value in headers.items():
        if key.lower() == wanted:
            return value

    return None
