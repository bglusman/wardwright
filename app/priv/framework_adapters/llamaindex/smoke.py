#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time

from wardwright_llamaindex import (
    WardwrightLlamaIndexCallback,
    WardwrightLlamaIndexContext,
    chat_completion,
    wardwright_llamaindex_config,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="coding-balanced")
    args = parser.parse_args()

    context = WardwrightLlamaIndexContext(
        tenant_id="tenant-llamaindex-smoke",
        application_id="app-llamaindex",
        consuming_agent_id="agent-llamaindex",
        consuming_user_id="user-llamaindex-smoke",
        session_id="query-llamaindex-smoke",
        run_id="run-llamaindex-smoke",
        client_request_id=f"llamaindex-smoke-{int(time.time() * 1000)}",
    )
    config = wardwright_llamaindex_config(
        base_url=args.base_url,
        model=args.model,
        context=context,
    )
    callback = WardwrightLlamaIndexCallback()
    llm_event_metadata = {
        "event_type": "llm",
        "query_id": context.session_id,
    }
    retrieval_context_metadata = {
        "query_id": context.session_id,
        "retriever": "synthetic-retriever",
    }

    framework_aware = chat_completion(
        base_url=config["llm"]["api_base"],
        model=config["llm"]["model"],
        headers=config["llm"]["default_headers"],
        messages=[
            {
                "role": "user",
                "content": "Synthetic Wardwright LlamaIndex smoke prompt.",
            }
        ],
        callback=callback,
        llm_event_metadata=llm_event_metadata,
        retrieval_context_metadata=retrieval_context_metadata,
    )
    generic_fallback = chat_completion(
        base_url=config["llm"]["api_base"],
        model=config["llm"]["model"],
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
    assert callback.receipts, "LlamaIndex callback did not store receipt evidence"
    assert (
        llm_event_metadata.get("wardwright_receipt_id") == framework_aware["receipt_id"]
    ), "LlamaIndex LLM event metadata does not contain the Wardwright receipt id"
    assert (
        retrieval_context_metadata.get("wardwright", {}).get("receipt_id")
        == framework_aware["receipt_id"]
    ), "LlamaIndex retrieval context metadata does not contain the Wardwright receipt id"

    report = {
        "framework": "llamaindex",
        "support_tier": "recipe_only",
        "fidelity": "framework_receipt_correlated",
        "requested_model": args.model,
        "selected_model": framework_aware["selected_model"],
        "receipt_id": framework_aware["receipt_id"],
        "captured_receipts": [receipt["receipt_id"] for receipt in callback.receipts],
        "provenance": context.metadata(),
        "llamaindex": {
            "config": config,
            "llm_event_metadata": llm_event_metadata,
            "retrieval_context_metadata": retrieval_context_metadata,
        },
        "fallback": {
            "generic_openai_compatible": generic_fallback["ok"],
            "adapter_receipt_claim": False,
        },
        "retrieval_lineage": "not_claimed",
        "index_state": "not_claimed",
        "streaming": "deferred",
        "tool_calling": "deferred",
        "llamaindex_package_runtime": "not_executed_in_default_smoke",
    }

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
