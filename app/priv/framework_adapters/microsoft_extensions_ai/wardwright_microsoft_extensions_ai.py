from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Mapping


RECEIPT_HEADER = "x-wardwright-receipt-id"
SELECTED_MODEL_HEADER = "x-wardwright-selected-model"


@dataclass(frozen=True)
class WardwrightDotNetContext:
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


@dataclass
class WardwrightReceiptDelegatingClient:
    chat_response_additional_properties: dict[str, Any] = field(default_factory=dict)
    receipts: list[dict[str, str]] = field(default_factory=list)

    def capture_response_headers(
        self,
        headers: Mapping[str, str],
        *,
        model_id: str,
        framework_surface: str,
    ) -> str | None:
        receipt_id = header_value(headers, RECEIPT_HEADER)

        if not receipt_id:
            return None

        self.receipts.append(
            {
                "receipt_id": receipt_id,
                "header": RECEIPT_HEADER,
                "source": "microsoft-extensions-ai-delegating-client",
            }
        )
        self.chat_response_additional_properties.update(
            {
                "wardwright_receipt_id": receipt_id,
                "wardwright_fidelity": "framework_receipt_correlated",
                "wardwright_model_id": model_id,
                "wardwright_framework_surface": framework_surface,
                "native_framework_state_claimed": False,
                "semantic_kernel_planner_claimed": False,
            }
        )

        return receipt_id


def normalize_wardwright_base_url(base_url: str) -> str:
    if not isinstance(base_url, str) or not base_url.strip():
        raise ValueError("Wardwright base URL is required")

    normalized = base_url.strip().rstrip("/")
    return normalized if normalized.endswith("/v1") else f"{normalized}/v1"


def wardwright_microsoft_extensions_ai_config(
    *,
    base_url: str,
    model: str,
    context: WardwrightDotNetContext,
) -> dict[str, Any]:
    return {
        "chat_client": {
            "interface": "Microsoft.Extensions.AI.IChatClient",
            "base_url": normalize_wardwright_base_url(base_url),
            "model_id": model,
            "api_key_env": "WARDWRIGHT_MODEL_API_KEY",
            "default_headers": context.provenance_headers(),
        },
        "middleware": {
            "class": "WardwrightReceiptDelegatingChatClient",
            "base": "Microsoft.Extensions.AI.DelegatingChatClient",
            "captures": RECEIPT_HEADER,
            "records": "ChatResponse.AdditionalProperties",
        },
        "semantic_kernel": {
            "guidance": "Use the Wardwright-configured IChatClient as the chat completion service and add filters only for Semantic Kernel-owned function or prompt visibility.",
            "service_registration": "IChatClient",
            "filters": [
                "IFunctionInvocationFilter",
                "IPromptRenderFilter",
                "IAutoFunctionInvocationFilter",
            ],
            "wardwright_planner_claimed": False,
            "native_kernel_state_claimed": False,
        },
        "metadata": {
            "wardwright_contract": "wardwright.framework_adapter.v0",
            "wardwright_support_tier": "recipe_only",
            "dotnet_runtime_required_for_default_smoke": False,
        },
    }


def chat_completion(
    *,
    base_url: str,
    model: str,
    messages: list[dict[str, str]],
    headers: Mapping[str, str] | None = None,
    receipt_client: WardwrightReceiptDelegatingClient | None = None,
    framework_surface: str = "microsoft-extensions-ai",
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

    if receipt_client is not None:
        receipt_client.capture_response_headers(
            response_headers,
            model_id=model,
            framework_surface=framework_surface,
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
