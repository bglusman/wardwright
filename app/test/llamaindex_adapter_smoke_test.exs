defmodule Wardwright.LlamaIndexAdapterSmokeTest do
  use Wardwright.RouterCase

  test "LlamaIndex callback recipe routes through Wardwright and records receipt metadata" do
    config =
      unit_policy_config()
      |> Map.put("governance", [])
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["llamaindex smoke ok"],
          "context_window" => 256,
          "model" => "canned/llamaindex",
          "provider_kind" => "canned_sequence"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    python =
      System.find_executable("python3") ||
        System.find_executable("python") ||
        flunk("python is required for the LlamaIndex smoke")

    smoke = Path.expand("../priv/framework_adapters/llamaindex/smoke.py", __DIR__)

    {output, status} =
      System.cmd(
        python,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = JSON.decode!(output)

    assert report["framework"] == "llamaindex"
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == "canned/llamaindex"
    assert report["retrieval_lineage"] == "not_claimed"
    assert report["index_state"] == "not_claimed"
    assert report["streaming"] == "deferred"
    assert report["tool_calling"] == "deferred"
    assert report["llamaindex_package_runtime"] == "not_executed_in_default_smoke"
    assert report["captured_receipts"] == [report["receipt_id"]]

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

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    receipt = Wardwright.ReceiptStore.get(report["receipt_id"])

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => "tenant-llamaindex-smoke"
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) == "app-llamaindex"
    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == "agent-llamaindex"
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == "user-llamaindex-smoke"
    assert get_in(receipt, ["caller", "session_id", "value"]) == "query-llamaindex-smoke"
    assert get_in(receipt, ["caller", "run_id", "value"]) == "run-llamaindex-smoke"

    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~
             "llamaindex-smoke-"

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "llamaindex",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end
end
