from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Mapping


RECEIPT_HEADER = "x-wardwright-receipt-id"
SELECTED_MODEL_HEADER = "x-wardwright-selected-model"


@dataclass(frozen=True)
class WardwrightPydanticContext:
    tenant_id: str
    application_id: str
    consuming_agent_id: str
    consuming_user_id: str
    session_id: str
    run_id: str
    client_request_id: str

    def provenance_headers(self) -> dict[str, str]:
        return {
            "x-wardwright-tenant-id": self.tenant_id,
            "x-wardwright-application-id": self.application_id,
            "x-wardwright-agent-id": self.consuming_agent_id,
            "x-wardwright-user-id": self.consuming_user_id,
            "x-wardwright-session-id": self.session_id,
            "x-wardwright-run-id": self.run_id,
            "x-client-request-id": self.client_request_id,
        }

    def metadata(self) -> dict[str, str]:
        return {
            "tenant_id": self.tenant_id,
            "application_id": self.application_id,
            "consuming_agent_id": self.consuming_agent_id,
            "consuming_user_id": self.consuming_user_id,
            "session_id": self.session_id,
            "run_id": self.run_id,
            "client_request_id": self.client_request_id,
        }


@dataclass(frozen=True)
class PydanticAiCapabilityRequest:
    structured_output: bool = False
    tool_calls: bool = False

    def limits(self) -> dict[str, str]:
        return {
            "structured_output": capability_limit(self.structured_output),
            "tool_calls": capability_limit(self.tool_calls),
        }


class WardwrightPydanticReceiptCapture:
    def __init__(self) -> None:
        self.receipts: list[dict[str, str]] = []

    def capture(
        self,
        headers: Mapping[str, str],
        *,
        run_metadata: dict[str, Any] | None = None,
        capability_request: PydanticAiCapabilityRequest | None = None,
    ) -> str | None:
        receipt_id = header_value(headers, RECEIPT_HEADER)

        if not receipt_id:
            return None

        evidence = {
            "receipt_id": receipt_id,
            "header": RECEIPT_HEADER,
            "source": "pydantic-ai-run-metadata",
        }
        self.receipts.append(evidence)

        if run_metadata is not None:
            run_metadata.setdefault("wardwright", {})
            run_metadata["wardwright"].update(
                {
                    "receipt_id": receipt_id,
                    "fidelity": "framework_receipt_correlated",
                    "native_state_import_claimed": False,
                    "capability_limits": (
                        capability_request or PydanticAiCapabilityRequest()
                    ).limits(),
                }
            )

        return receipt_id


def normalize_wardwright_base_url(base_url: str) -> str:
    if not isinstance(base_url, str) or not base_url.strip():
        raise ValueError("Wardwright base URL is required")

    normalized = base_url.strip().rstrip("/")
    return normalized if normalized.endswith("/v1") else f"{normalized}/v1"


def wardwright_pydantic_ai_model_config(
    *,
    base_url: str,
    model: str,
    context: WardwrightPydanticContext,
) -> dict[str, Any]:
    return {
        "model": model,
        "provider": {
            "class": "pydantic_ai.providers.openai.OpenAIProvider",
            "base_url": normalize_wardwright_base_url(base_url),
            "api_key_env": "WARDWRIGHT_MODEL_API_KEY",
        },
        "model_class": "pydantic_ai.models.openai.OpenAIChatModel",
        "default_headers": context.provenance_headers(),
        "deps": context.metadata(),
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
    receipt_capture: WardwrightPydanticReceiptCapture | None = None,
    run_metadata: dict[str, Any] | None = None,
    capability_request: PydanticAiCapabilityRequest | None = None,
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

    if receipt_capture is not None:
        receipt_capture.capture(
            response_headers,
            run_metadata=run_metadata,
            capability_request=capability_request,
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


def capability_limit(requested: bool) -> str:
    if requested:
        return "not_proven_by_recipe_smoke_requires_model_capability_contract"

    return "not_requested"


def header_value(headers: Mapping[str, str], name: str) -> str | None:
    wanted = name.lower()

    for key, value in headers.items():
        if key.lower() == wanted:
            return value

    return None
