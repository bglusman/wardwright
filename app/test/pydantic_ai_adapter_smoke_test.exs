defmodule Wardwright.PydanticAiAdapterSmokeTest do
  use Wardwright.RouterCase

  test "Pydantic AI recipe routes through Wardwright and records receipt metadata with capability limits" do
    config =
      unit_policy_config()
      |> Map.put("governance", [])
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["pydantic ai smoke ok"],
          "context_window" => 256,
          "model" => "canned/pydantic-ai",
          "provider_kind" => "canned_sequence"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    python =
      System.find_executable("python3") ||
        System.find_executable("python") ||
        flunk("python is required for the Pydantic AI smoke")

    smoke = Path.expand("../priv/framework_adapters/pydantic_ai/smoke.py", __DIR__)

    {output, status} =
      System.cmd(
        python,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = JSON.decode!(output)

    assert report["framework"] == "pydantic-ai"
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == "canned/pydantic-ai"
    assert report["state_import"] == "not_claimed"
    assert report["streaming"] == "deferred"
    assert report["captured_receipts"] == [report["receipt_id"]]

    assert get_in(report, ["pydantic_ai", "model_config", "provider", "class"]) ==
             "pydantic_ai.providers.openai.OpenAIProvider"

    assert get_in(report, ["pydantic_ai", "model_config", "provider", "api_key_env"]) ==
             "WARDWRIGHT_MODEL_API_KEY"

    refute Map.has_key?(get_in(report, ["pydantic_ai", "model_config", "provider"]), "api_key")

    assert get_in(report, ["pydantic_ai", "model_config", "model_class"]) ==
             "pydantic_ai.models.openai.OpenAIChatModel"

    assert get_in(report, ["pydantic_ai", "run_metadata", "wardwright", "receipt_id"]) ==
             report["receipt_id"]

    assert get_in(report, ["pydantic_ai", "run_metadata", "wardwright", "fidelity"]) ==
             "framework_receipt_correlated"

    refute get_in(report, [
             "pydantic_ai",
             "run_metadata",
             "wardwright",
             "native_state_import_claimed"
           ])

    capability_limit = "not_proven_by_recipe_smoke_requires_model_capability_contract"

    assert report["capability_limits"] == %{
             "structured_output" => capability_limit,
             "tool_calls" => capability_limit
           }

    assert get_in(report, [
             "pydantic_ai",
             "run_metadata",
             "wardwright",
             "capability_limits"
           ]) == report["capability_limits"]

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    receipt = Wardwright.ReceiptStore.get(report["receipt_id"])

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => "tenant-pydantic-ai-smoke"
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) == "app-pydantic-ai"
    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == "agent-pydantic-ai"
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == "user-pydantic-ai-smoke"
    assert get_in(receipt, ["caller", "session_id", "value"]) == "session-pydantic-ai-smoke"
    assert get_in(receipt, ["caller", "run_id", "value"]) == "run-pydantic-ai-smoke"

    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~
             "pydantic-ai-smoke-"

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "pydantic-ai",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end
end
