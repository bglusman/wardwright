defmodule Wardwright.PydanticAiAdapterSmokeTest do
  use Wardwright.FrameworkAdapterSmokeCase

  test "Pydantic AI recipe routes through Wardwright and records receipt metadata with capability limits" do
    report =
      run_framework_adapter_smoke(%{
        caller: %{
          application_id: "app-pydantic-ai",
          client_request_id_prefix: "pydantic-ai-smoke-",
          consuming_agent_id: "agent-pydantic-ai",
          consuming_user_id: "user-pydantic-ai-smoke",
          run_id: "run-pydantic-ai-smoke",
          session_id: "session-pydantic-ai-smoke",
          tenant_id: "tenant-pydantic-ai-smoke"
        },
        canned_model: "canned/pydantic-ai",
        canned_output: "pydantic ai smoke ok",
        name: "Pydantic AI",
        runtime: :python,
        smoke: "pydantic_ai/smoke.py"
      })

    assert report["framework"] == "pydantic-ai"
    assert report["state_import"] == "not_claimed"
    assert report["streaming"] == "deferred"

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

    assert_framework_receipt_ready!("pydantic-ai")
  end
end
