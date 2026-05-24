defmodule Wardwright.LlamaIndexAdapterSmokeTest do
  use Wardwright.FrameworkAdapterSmokeCase

  test "LlamaIndex callback recipe routes through Wardwright and records receipt metadata" do
    report =
      run_framework_adapter_smoke(%{
        caller: %{
          application_id: "app-llamaindex",
          client_request_id_prefix: "llamaindex-smoke-",
          consuming_agent_id: "agent-llamaindex",
          consuming_user_id: "user-llamaindex-smoke",
          run_id: "run-llamaindex-smoke",
          session_id: "query-llamaindex-smoke",
          tenant_id: "tenant-llamaindex-smoke"
        },
        canned_model: "canned/llamaindex",
        canned_output: "llamaindex smoke ok",
        name: "LlamaIndex",
        runtime: :python,
        smoke: "llamaindex/smoke.py"
      })

    assert report["framework"] == "llamaindex"
    assert report["retrieval_lineage"] == "not_claimed"
    assert report["index_state"] == "not_claimed"
    assert report["streaming"] == "deferred"
    assert report["tool_calling"] == "deferred"
    assert report["llamaindex_package_runtime"] == "not_executed_in_default_smoke"

    assert get_in(report, ["llamaindex", "config", "llm", "class"]) ==
             "llama_index.llms.openai_like.OpenAILike"

    assert get_in(report, ["llamaindex", "config", "llm", "api_key_env"]) ==
             "WARDWRIGHT_MODEL_API_KEY"

    refute Map.has_key?(get_in(report, ["llamaindex", "config", "llm"]), "api_key")

    assert get_in(report, ["llamaindex", "config", "llm", "is_chat_model"])
    refute get_in(report, ["llamaindex", "config", "llm", "is_function_calling_model"])

    assert get_in(report, ["llamaindex", "config", "callback", "records"]) == [
             "llm_event_metadata.wardwright_receipt_id",
             "retrieval_context_metadata.wardwright.receipt_id"
           ]

    assert get_in(report, ["llamaindex", "llm_event_metadata", "wardwright_receipt_id"]) ==
             report["receipt_id"]

    assert get_in(report, ["llamaindex", "llm_event_metadata", "wardwright_fidelity"]) ==
             "framework_receipt_correlated"

    refute get_in(report, ["llamaindex", "llm_event_metadata", "native_index_state_claimed"])

    assert get_in(report, [
             "llamaindex",
             "retrieval_context_metadata",
             "wardwright",
             "receipt_id"
           ]) == report["receipt_id"]

    assert get_in(report, [
             "llamaindex",
             "retrieval_context_metadata",
             "wardwright",
             "fidelity"
           ]) == "framework_receipt_correlated"

    refute get_in(report, [
             "llamaindex",
             "retrieval_context_metadata",
             "wardwright",
             "retrieval_lineage_claimed"
           ])

    refute get_in(report, [
             "llamaindex",
             "retrieval_context_metadata",
             "wardwright",
             "index_state_claimed"
           ])

    assert_framework_receipt_ready!("llamaindex")
  end
end
