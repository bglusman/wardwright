#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time

from wardwright_langchain import (
    WardwrightReceiptCallback,
    chat_completion,
    wardwright_langchain_model_config,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="coding-balanced")
    args = parser.parse_args()

    provenance = {
        "tenant_id": "tenant-langchain-smoke",
        "application_id": "app-langchain-langgraph",
        "consuming_agent_id": "agent-langchain",
        "consuming_user_id": "user-langchain-smoke",
        "session_id": "thread-langgraph-smoke",
        "run_id": "run-langchain-smoke",
        "client_request_id": f"langchain-langgraph-smoke-{int(time.time() * 1000)}",
    }
    config = wardwright_langchain_model_config(
        base_url=args.base_url,
        model=args.model,
        provenance=provenance,
    )
    callback = WardwrightReceiptCallback()
    langchain_run_metadata = {
        "run_id": provenance["run_id"],
        "tags": ["wardwright-smoke", "synthetic"],
    }
    langgraph_checkpoint_metadata = {
        "thread_id": provenance["session_id"],
        "checkpoint_id": "checkpoint-langgraph-smoke",
    }

    framework_aware = chat_completion(
        base_url=config["base_url"],
        model=config["model"],
        headers=config["default_headers"],
        messages=[
            {
                "role": "user",
                "content": "Synthetic Wardwright LangChain and LangGraph smoke prompt.",
            }
        ],
        callback=callback,
        langchain_run_metadata=langchain_run_metadata,
        langgraph_checkpoint_metadata=langgraph_checkpoint_metadata,
    )
    generic_fallback = chat_completion(
        base_url=config["base_url"],
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
    assert callback.receipts, "LangChain callback did not capture the receipt id"
    assert (
        langchain_run_metadata.get("wardwright_receipt_id") == framework_aware["receipt_id"]
    ), "LangChain run metadata does not contain the Wardwright receipt id"
    assert (
        langgraph_checkpoint_metadata.get("wardwright", {}).get("receipt_id")
        == framework_aware["receipt_id"]
    ), "LangGraph checkpoint metadata does not contain the Wardwright receipt id"

    report = {
        "framework": "langchain-langgraph",
        "support_tier": "recipe_only",
        "fidelity": "framework_receipt_correlated",
        "requested_model": args.model,
        "selected_model": framework_aware["selected_model"],
        "receipt_id": framework_aware["receipt_id"],
        "captured_receipts": [receipt["receipt_id"] for receipt in callback.receipts],
        "provenance": provenance,
        "langchain": {
            "run_metadata": langchain_run_metadata,
        },
        "langgraph": {
            "checkpoint_metadata": langgraph_checkpoint_metadata,
            "native_checkpoint_durability_claimed": False,
        },
        "fallback": {
            "generic_openai_compatible": generic_fallback["ok"],
            "adapter_receipt_claim": False,
        },
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
