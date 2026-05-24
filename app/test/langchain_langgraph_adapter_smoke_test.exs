defmodule Wardwright.LangChainLangGraphAdapterSmokeTest do
  use Wardwright.FrameworkAdapterSmokeCase

  test "LangChain callback recipe routes through Wardwright and records receipt metadata for LangGraph" do
    report =
      run_framework_adapter_smoke(%{
        caller: %{
          application_id: "app-langchain-langgraph",
          client_request_id_prefix: "langchain-langgraph-smoke-",
          consuming_agent_id: "agent-langchain",
          consuming_user_id: "user-langchain-smoke",
          run_id: "run-langchain-smoke",
          session_id: "thread-langgraph-smoke",
          tenant_id: "tenant-langchain-smoke"
        },
        canned_model: "canned/langchain-langgraph",
        canned_output: "langchain langgraph smoke ok",
        name: "LangChain/LangGraph",
        runtime: :python,
        smoke: "langchain_langgraph/smoke.py"
      })

    assert report["framework"] == "langchain-langgraph"
    assert report["state_import"] == "not_claimed"
    assert report["streaming"] == "deferred"

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

    assert_framework_receipt_ready!("langchain")
    assert_framework_receipt_ready!("langgraph")
  end
end
