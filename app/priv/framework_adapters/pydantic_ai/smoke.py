#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time

from wardwright_pydantic_ai import (
    PydanticAiCapabilityRequest,
    WardwrightPydanticContext,
    WardwrightPydanticReceiptCapture,
    chat_completion,
    wardwright_pydantic_ai_model_config,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="coding-balanced")
    args = parser.parse_args()

    context = WardwrightPydanticContext(
        tenant_id="tenant-pydantic-ai-smoke",
        application_id="app-pydantic-ai",
        consuming_agent_id="agent-pydantic-ai",
        consuming_user_id="user-pydantic-ai-smoke",
        session_id="session-pydantic-ai-smoke",
        run_id="run-pydantic-ai-smoke",
        client_request_id=f"pydantic-ai-smoke-{int(time.time() * 1000)}",
    )
    config = wardwright_pydantic_ai_model_config(
        base_url=args.base_url,
        model=args.model,
        context=context,
    )
    receipt_capture = WardwrightPydanticReceiptCapture()
    capability_request = PydanticAiCapabilityRequest(
        structured_output=True,
        tool_calls=True,
    )
    run_metadata = {
        "agent_name": "wardwright-pydantic-ai-smoke",
        "deps": config["deps"],
    }

    framework_aware = chat_completion(
        base_url=config["provider"]["base_url"],
        model=config["model"],
        headers=config["default_headers"],
        messages=[
            {
                "role": "user",
                "content": "Synthetic Wardwright Pydantic AI smoke prompt.",
            }
        ],
        receipt_capture=receipt_capture,
        run_metadata=run_metadata,
        capability_request=capability_request,
    )
    generic_fallback = chat_completion(
        base_url=config["provider"]["base_url"],
        model=config["model"],
        messages=[
            {
                "role": "user",
                "content": "Synthetic generic OpenAI-compatible fallback prompt.",
            }
        ],
    )

    assert framework_aware["ok"], "framework-aware request failed"
    assert generic_fallback["ok"], "generic OpenAI-compatible fallback request failed"
    assert framework_aware["receipt_id"], "Wardwright receipt header was not returned"
    assert framework_aware["selected_model"], "Wardwright selected model header was not returned"
    assert receipt_capture.receipts, "Pydantic AI receipt capture did not store evidence"
    assert (
        run_metadata.get("wardwright", {}).get("receipt_id") == framework_aware["receipt_id"]
    ), "Pydantic AI run metadata does not contain the Wardwright receipt id"

    report = {
        "framework": "pydantic-ai",
        "support_tier": "recipe_only",
        "fidelity": "framework_receipt_correlated",
        "requested_model": args.model,
        "selected_model": framework_aware["selected_model"],
        "receipt_id": framework_aware["receipt_id"],
        "captured_receipts": [
            receipt["receipt_id"] for receipt in receipt_capture.receipts
        ],
        "provenance": context.metadata(),
        "pydantic_ai": {
            "model_config": config,
            "run_metadata": run_metadata,
        },
        "fallback": {
            "generic_openai_compatible": generic_fallback["ok"],
            "adapter_receipt_claim": False,
        },
        "capability_limits": capability_request.limits(),
        "state_import": "not_claimed",
        "streaming": "deferred",
    }

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
