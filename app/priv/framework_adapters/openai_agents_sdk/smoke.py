#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time

from wardwright_openai_agents import (
    WardwrightAgentsContext,
    WardwrightAgentsTraceProcessor,
    chat_completion,
    wardwright_openai_agents_config,
)


class FakeSensitiveTrace:
    workflow_name = "wardwright-openai-agents-sensitive-probe"
    group_id = "session-openai-agents-sensitive-probe"
    trace_id = "trace-openai-agents-sensitive-probe"
    metadata = {
        "tenant_id": "tenant-openai-agents-smoke",
        "run_id": "run-openai-agents-smoke",
        "raw_prompt": "Synthetic prompt text that must not be retained.",
        "raw_completion": "Synthetic completion text that must not be retained.",
    }

    def export(self) -> dict[str, object]:
        return {
            "workflow_name": self.workflow_name,
            "group_id": self.group_id,
            "trace_id": self.trace_id,
            "metadata": self.metadata,
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="coding-balanced")
    args = parser.parse_args()

    context = WardwrightAgentsContext(
        tenant_id="tenant-openai-agents-smoke",
        application_id="app-openai-agents",
        consuming_agent_id="agent-openai-agents",
        consuming_user_id="user-openai-agents-smoke",
        session_id="session-openai-agents-smoke",
        run_id="run-openai-agents-smoke",
        client_request_id=f"openai-agents-smoke-{int(time.time() * 1000)}",
    )
    config = wardwright_openai_agents_config(
        base_url=args.base_url,
        model=args.model,
        context=context,
    )
    trace_processor = WardwrightAgentsTraceProcessor()
    trace_processor.start_trace(
        workflow_name="wardwright-openai-agents-smoke",
        group_id=context.session_id,
        metadata=config["run_config"]["metadata"],
    )
    privacy_probe = WardwrightAgentsTraceProcessor()
    privacy_probe.on_trace_start(FakeSensitiveTrace())

    framework_aware = chat_completion(
        base_url=config["model"]["client"]["base_url"],
        model=config["model"]["model"],
        headers=config["model"]["client"]["default_headers"],
        messages=[
            {
                "role": "user",
                "content": "Synthetic Wardwright OpenAI Agents SDK smoke prompt.",
            }
        ],
        trace_processor=trace_processor,
    )
    generic_fallback = chat_completion(
        base_url=config["model"]["client"]["base_url"],
        model=config["model"]["model"],
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
    assert trace_processor.receipts, "OpenAI Agents trace processor did not store receipt evidence"
    assert (
        trace_processor.trace_metadata.get("metadata", {}).get("wardwright_receipt_id")
        == framework_aware["receipt_id"]
    ), "OpenAI Agents trace metadata does not contain the Wardwright receipt id"

    report = {
        "framework": "openai-agents-sdk",
        "support_tier": "recipe_only",
        "fidelity": "framework_receipt_correlated",
        "requested_model": args.model,
        "selected_model": framework_aware["selected_model"],
        "receipt_id": framework_aware["receipt_id"],
        "captured_receipts": [
            receipt["receipt_id"] for receipt in trace_processor.receipts
        ],
        "provenance": context.trace_metadata(),
        "openai_agents": {
            "config": config,
            "trace": trace_processor.trace_metadata,
            "generation_spans": trace_processor.generation_spans,
            "trace_privacy_probe": privacy_probe.trace_metadata,
        },
        "fallback": {
            "generic_openai_compatible": generic_fallback["ok"],
            "adapter_receipt_claim": False,
        },
        "chat_completions": "tested",
        "responses_api": "not_implemented_not_claimed",
        "streaming": "deferred",
        "tools": "deferred",
        "native_sessions": "not_claimed",
    }

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
