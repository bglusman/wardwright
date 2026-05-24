defmodule Wardwright.LangChainLangGraphAdapterSmokeTest do
  use Wardwright.RouterCase

  test "LangChain callback recipe routes through Wardwright and records receipt metadata for LangGraph" do
    config =
      unit_policy_config()
      |> Map.put("governance", [])
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["langchain langgraph smoke ok"],
          "context_window" => 256,
          "model" => "canned/langchain-langgraph",
          "provider_kind" => "canned_sequence"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    python =
      System.find_executable("python3") ||
        System.find_executable("python") ||
        flunk("python is required for the LangChain/LangGraph smoke")

    smoke = Path.expand("../priv/framework_adapters/langchain_langgraph/smoke.py", __DIR__)

    {output, status} =
      System.cmd(
        python,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = JSON.decode!(output)

    assert report["framework"] == "langchain-langgraph"
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == "canned/langchain-langgraph"
    assert report["state_import"] == "not_claimed"
    assert report["streaming"] == "deferred"
    assert report["captured_receipts"] == [report["receipt_id"]]

    assert get_in(report, ["langchain", "run_metadata", "wardwright_receipt_id"]) ==
             report["receipt_id"]

    assert get_in(report, ["langchain", "run_metadata", "wardwright_fidelity"]) ==
             "framework_receipt_correlated"

    assert get_in(report, ["langgraph", "checkpoint_metadata", "wardwright", "receipt_id"]) ==
             report["receipt_id"]

    assert get_in(report, [
             "langgraph",
             "checkpoint_metadata",
             "wardwright",
             "native_checkpoint_durability_claimed"
           ]) == false

    assert get_in(report, ["langgraph", "native_checkpoint_durability_claimed"]) == false

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    receipt = Wardwright.ReceiptStore.get(report["receipt_id"])

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => "tenant-langchain-smoke"
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) == "app-langchain-langgraph"
    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == "agent-langchain"
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == "user-langchain-smoke"
    assert get_in(receipt, ["caller", "session_id", "value"]) == "thread-langgraph-smoke"
    assert get_in(receipt, ["caller", "run_id", "value"]) == "run-langchain-smoke"

    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~
             "langchain-langgraph-smoke-"

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "langchain",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "langgraph",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end
end
