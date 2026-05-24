defmodule Wardwright.OpenAIAgentsSdkAdapterSmokeTest do
  use Wardwright.FrameworkAdapterSmokeCase

  test "OpenAI Agents SDK recipe routes Chat Completions through Wardwright and records trace receipt metadata" do
    report =
      run_framework_adapter_smoke(%{
        caller: %{
          application_id: "app-openai-agents",
          client_request_id_prefix: "openai-agents-smoke-",
          consuming_agent_id: "agent-openai-agents",
          consuming_user_id: "user-openai-agents-smoke",
          run_id: "run-openai-agents-smoke",
          session_id: "session-openai-agents-smoke",
          tenant_id: "tenant-openai-agents-smoke"
        },
        canned_model: "canned/openai-agents-sdk",
        canned_output: "openai agents sdk smoke ok",
        name: "OpenAI Agents SDK",
        runtime: :python,
        smoke: "openai_agents_sdk/smoke.py"
      })

    assert report["framework"] == "openai-agents-sdk"
    assert report["chat_completions"] == "tested"
    assert report["responses_api"] == "not_implemented_not_claimed"
    assert report["streaming"] == "deferred"
    assert report["tools"] == "deferred"
    assert report["native_sessions"] == "not_claimed"

    assert get_in(report, ["openai_agents", "config", "model", "class"]) ==
             "agents.models.openai_chatcompletions.OpenAIChatCompletionsModel"

    assert get_in(report, ["openai_agents", "config", "model", "client", "class"]) ==
             "openai.AsyncOpenAI"

    assert get_in(report, ["openai_agents", "config", "model", "client", "api_key_env"]) ==
             "WARDWRIGHT_MODEL_API_KEY"

    refute Map.has_key?(get_in(report, ["openai_agents", "config", "model", "client"]), "api_key")

    assert get_in(report, ["openai_agents", "config", "trace_processor", "class"]) ==
             "WardwrightAgentsTraceProcessor"

    assert get_in(report, ["openai_agents", "config", "run_config", "trace_include_sensitive_data"]) ==
             false

    assert get_in(report, ["openai_agents", "trace", "metadata", "wardwright_receipt_id"]) ==
             report["receipt_id"]

    assert get_in(report, ["openai_agents", "trace", "metadata", "wardwright_fidelity"]) ==
             "framework_receipt_correlated"

    refute get_in(report, ["openai_agents", "trace", "metadata", "responses_api_parity_claimed"])

    assert get_in(report, ["openai_agents", "trace", "trace_include_sensitive_data"]) == false

    assert get_in(report, ["openai_agents", "trace_privacy_probe", "metadata"]) == %{
             "run_id" => "run-openai-agents-smoke",
             "tenant_id" => "tenant-openai-agents-smoke"
           }

    refute get_in(report, ["openai_agents", "trace_privacy_probe", "metadata", "raw_prompt"])
    refute get_in(report, ["openai_agents", "trace_privacy_probe", "metadata", "raw_completion"])

    assert [
             %{
               "endpoint" => "chat_completions",
               "model" => "unit-model",
               "native_session_import_claimed" => false,
               "responses_api_parity_claimed" => false,
               "wardwright_fidelity" => "framework_receipt_correlated",
               "wardwright_receipt_id" => receipt_id
             }
           ] = get_in(report, ["openai_agents", "generation_spans"])

    assert receipt_id == report["receipt_id"]

    assert_framework_receipt_ready!("openai-agents-sdk")
  end
end
