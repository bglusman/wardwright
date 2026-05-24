#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time

from wardwright_microsoft_extensions_ai import (
    WardwrightDotNetContext,
    WardwrightReceiptDelegatingClient,
    chat_completion,
    wardwright_microsoft_extensions_ai_config,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="coding-balanced")
    args = parser.parse_args()

    context = WardwrightDotNetContext(
        tenant_id="tenant-dotnet-smoke",
        application_id="app-microsoft-extensions-ai",
        consuming_agent_id="agent-dotnet",
        consuming_user_id="user-dotnet-smoke",
        session_id="session-dotnet-smoke",
        run_id="run-dotnet-smoke",
        client_request_id=f"dotnet-smoke-{int(time.time() * 1000)}",
    )
    config = wardwright_microsoft_extensions_ai_config(
        base_url=args.base_url,
        model=args.model,
        context=context,
    )
    receipt_client = WardwrightReceiptDelegatingClient()

    framework_aware = chat_completion(
        base_url=config["chat_client"]["base_url"],
        model=config["chat_client"]["model_id"],
        headers=config["chat_client"]["default_headers"],
        messages=[
            {
                "role": "user",
                "content": "Synthetic Wardwright Microsoft.Extensions.AI smoke prompt.",
            }
        ],
        receipt_client=receipt_client,
    )
    generic_fallback = chat_completion(
        base_url=config["chat_client"]["base_url"],
        model=config["chat_client"]["model_id"],
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
    assert receipt_client.receipts, "delegating client did not store receipt evidence"
    assert (
        receipt_client.chat_response_additional_properties.get("wardwright_receipt_id")
        == framework_aware["receipt_id"]
    ), "ChatResponse additional properties do not contain the Wardwright receipt id"

    report = {
        "framework": "microsoft-extensions-ai",
        "support_tier": "recipe_only",
        "fidelity": "framework_receipt_correlated",
        "requested_model": args.model,
        "selected_model": framework_aware["selected_model"],
        "receipt_id": framework_aware["receipt_id"],
        "captured_receipts": [
            receipt["receipt_id"] for receipt in receipt_client.receipts
        ],
        "provenance": context.metadata(),
        "microsoft_extensions_ai": {
            "config": config,
            "chat_response_additional_properties": receipt_client.chat_response_additional_properties,
        },
        "semantic_kernel": {
            "guidance": config["semantic_kernel"],
            "support_level": "guidance_on_microsoft_extensions_ai_path",
            "filter_or_plugin_smoke": "deferred",
        },
        "fallback": {
            "generic_openai_compatible": generic_fallback["ok"],
            "adapter_receipt_claim": False,
        },
        "streaming": "deferred",
        "tool_calling": "deferred",
        "native_framework_state": "not_claimed",
        "dotnet_package_runtime": "not_executed_in_default_smoke",
    }

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
