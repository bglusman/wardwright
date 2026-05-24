from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Mapping


RECEIPT_HEADER = "x-wardwright-receipt-id"
SELECTED_MODEL_HEADER = "x-wardwright-selected-model"


@dataclass(frozen=True)
class WardwrightAgentsContext:
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

    def trace_metadata(self) -> dict[str, str]:
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
class WardwrightAgentsTraceProcessor:
    trace_metadata: dict[str, Any] = field(default_factory=dict)
    generation_spans: list[dict[str, Any]] = field(default_factory=list)
    receipts: list[dict[str, str]] = field(default_factory=list)

    def on_trace_start(self, trace: Any) -> None:
        self.trace_metadata = safe_trace_record(trace)

    def on_trace_end(self, trace: Any) -> None:
        if not self.trace_metadata:
            self.trace_metadata = safe_trace_record(trace)

    def on_span_start(self, span: Any) -> None:
        _ = span

    def on_span_end(self, span: Any) -> None:
        exported = safe_export(span)
        span_data = exported.get("span_data", exported.get("data", {}))

        if span_data.get("type") == "generation":
            self.generation_spans.append(
                {
                    "model": span_data.get("model"),
                    "endpoint": "agents_sdk_generation_span",
                    "wardwright_fidelity": "generic_openai_compatible",
                }
            )

    def shutdown(self) -> None:
        self.force_flush()

    def force_flush(self) -> None:
        return None

    def start_trace(self, *, workflow_name: str, group_id: str, metadata: Mapping[str, Any]) -> None:
        self.trace_metadata = {
            "workflow_name": workflow_name,
            "group_id": group_id,
            "metadata": dict(metadata),
            "trace_include_sensitive_data": False,
        }

    def capture_generation(
        self,
        headers: Mapping[str, str],
        *,
        span_metadata: dict[str, Any] | None = None,
    ) -> str | None:
        receipt_id = header_value(headers, RECEIPT_HEADER)

        if not receipt_id:
            return None

        evidence = {
            "receipt_id": receipt_id,
            "header": RECEIPT_HEADER,
            "source": "openai-agents-trace-processor",
        }
        self.receipts.append(evidence)

        generation_metadata = {
            "wardwright_receipt_id": receipt_id,
            "wardwright_fidelity": "framework_receipt_correlated",
            "responses_api_parity_claimed": False,
            "native_session_import_claimed": False,
        }
        generation_metadata.update(span_metadata or {})
        self.generation_spans.append(generation_metadata)

        self.trace_metadata.setdefault("metadata", {})
        self.trace_metadata["metadata"].update(
            {
                "wardwright_receipt_id": receipt_id,
                "wardwright_fidelity": "framework_receipt_correlated",
                "responses_api_parity_claimed": False,
            }
        )

        return receipt_id


def normalize_wardwright_base_url(base_url: str) -> str:
    if not isinstance(base_url, str) or not base_url.strip():
        raise ValueError("Wardwright base URL is required")

    normalized = base_url.strip().rstrip("/")
    return normalized if normalized.endswith("/v1") else f"{normalized}/v1"


def wardwright_openai_agents_config(
    *,
    base_url: str,
    model: str,
    context: WardwrightAgentsContext,
) -> dict[str, Any]:
    return {
        "agent": {
            "class": "agents.Agent",
            "name": "wardwright-agents-smoke",
            "model": model,
        },
        "model": {
            "class": "agents.models.openai_chatcompletions.OpenAIChatCompletionsModel",
            "model": model,
            "client": {
                "class": "openai.AsyncOpenAI",
                "base_url": normalize_wardwright_base_url(base_url),
                "api_key_env": "WARDWRIGHT_MODEL_API_KEY",
                "default_headers": context.provenance_headers(),
            },
        },
        "run_config": {
            "trace_include_sensitive_data": False,
            "metadata": context.trace_metadata(),
        },
        "trace_processor": {
            "class": "WardwrightAgentsTraceProcessor",
            "correlates": RECEIPT_HEADER,
        },
        "metadata": {
            "wardwright_contract": "wardwright.framework_adapter.v0",
            "wardwright_support_tier": "recipe_only",
            "chat_completions_path": True,
            "responses_api_parity": "not_claimed",
        },
    }


def chat_completion(
    *,
    base_url: str,
    model: str,
    messages: list[dict[str, str]],
    headers: Mapping[str, str] | None = None,
    trace_processor: WardwrightAgentsTraceProcessor | None = None,
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

    if trace_processor is not None:
        trace_processor.capture_generation(
            response_headers,
            span_metadata={"model": model, "endpoint": "chat_completions"},
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


def safe_export(value: Any) -> dict[str, Any]:
    export = getattr(value, "export", None)

    if callable(export):
        exported = export()
        return exported if isinstance(exported, dict) else {}

    return {}


def safe_trace_record(trace: Any) -> dict[str, Any]:
    exported = safe_export(trace)
    metadata = getattr(trace, "metadata", None) or exported.get("metadata", {})

    return {
        "workflow_name": getattr(trace, "workflow_name", None) or exported.get("workflow_name"),
        "group_id": getattr(trace, "group_id", None) or exported.get("group_id"),
        "trace_id": getattr(trace, "trace_id", None) or exported.get("trace_id"),
        "metadata": allowlisted_trace_metadata(metadata),
        "trace_include_sensitive_data": False,
    }


def allowlisted_trace_metadata(metadata: Any) -> dict[str, Any]:
    if not isinstance(metadata, Mapping):
        return {}

    allowed = {
        "tenant_id",
        "application_id",
        "consuming_agent_id",
        "consuming_user_id",
        "session_id",
        "run_id",
        "client_request_id",
        "wardwright_receipt_id",
        "wardwright_fidelity",
        "responses_api_parity_claimed",
    }

    return {key: metadata[key] for key in allowed if key in metadata}
