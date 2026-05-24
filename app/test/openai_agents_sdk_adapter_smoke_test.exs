defmodule Wardwright.OpenAIAgentsSdkAdapterSmokeTest do
  use Wardwright.RouterCase

  test "OpenAI Agents SDK recipe routes Chat Completions through Wardwright and records trace receipt metadata" do
    config =
      unit_policy_config()
      |> Map.put("governance", [])
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["openai agents sdk smoke ok"],
          "context_window" => 256,
          "model" => "canned/openai-agents-sdk",
          "provider_kind" => "canned_sequence"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    python =
      System.find_executable("python3") ||
        System.find_executable("python") ||
        flunk("python is required for the OpenAI Agents SDK smoke")

    smoke = Path.expand("../priv/framework_adapters/openai_agents_sdk/smoke.py", __DIR__)

    {output, status} =
      System.cmd(
        python,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = JSON.decode!(output)

    assert report["framework"] == "openai-agents-sdk"
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == "canned/openai-agents-sdk"
    assert report["chat_completions"] == "tested"
    assert report["responses_api"] == "not_implemented_not_claimed"
    assert report["streaming"] == "deferred"
    assert report["tools"] == "deferred"
    assert report["native_sessions"] == "not_claimed"
    assert report["captured_receipts"] == [report["receipt_id"]]

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

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    receipt = Wardwright.ReceiptStore.get(report["receipt_id"])

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => "tenant-openai-agents-smoke"
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) == "app-openai-agents"
    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == "agent-openai-agents"
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == "user-openai-agents-smoke"
    assert get_in(receipt, ["caller", "session_id", "value"]) == "session-openai-agents-smoke"
    assert get_in(receipt, ["caller", "run_id", "value"]) == "run-openai-agents-smoke"

    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~
             "openai-agents-smoke-"

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "openai-agents-sdk",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end
end
