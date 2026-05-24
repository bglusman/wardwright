defmodule Wardwright.MicrosoftExtensionsAiAdapterSmokeTest do
  use Wardwright.RouterCase

  test "Microsoft.Extensions.AI recipe routes chat through Wardwright and records ChatResponse receipt metadata" do
    config =
      unit_policy_config()
      |> Map.put("governance", [])
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["microsoft extensions ai smoke ok"],
          "context_window" => 256,
          "model" => "canned/microsoft-extensions-ai",
          "provider_kind" => "canned_sequence"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    python =
      System.find_executable("python3") ||
        System.find_executable("python") ||
        flunk("python is required for the Microsoft.Extensions.AI smoke")

    smoke = Path.expand("../priv/framework_adapters/microsoft_extensions_ai/smoke.py", __DIR__)

    {output, status} =
      System.cmd(
        python,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = JSON.decode!(output)

    assert report["framework"] == "microsoft-extensions-ai"
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == "canned/microsoft-extensions-ai"
    assert report["streaming"] == "deferred"
    assert report["tool_calling"] == "deferred"
    assert report["native_framework_state"] == "not_claimed"
    assert report["dotnet_package_runtime"] == "not_executed_in_default_smoke"
    assert report["captured_receipts"] == [report["receipt_id"]]

    assert get_in(report, ["microsoft_extensions_ai", "config", "chat_client", "interface"]) ==
             "Microsoft.Extensions.AI.IChatClient"

    assert get_in(report, ["microsoft_extensions_ai", "config", "chat_client", "api_key_env"]) ==
             "WARDWRIGHT_MODEL_API_KEY"

    refute Map.has_key?(get_in(report, ["microsoft_extensions_ai", "config", "chat_client"]), "api_key")

    assert get_in(report, ["microsoft_extensions_ai", "config", "middleware", "base"]) ==
             "Microsoft.Extensions.AI.DelegatingChatClient"

    assert get_in(report, ["microsoft_extensions_ai", "config", "middleware", "records"]) ==
             "ChatResponse.AdditionalProperties"

    assert get_in(report, [
             "microsoft_extensions_ai",
             "chat_response_additional_properties",
             "wardwright_receipt_id"
           ]) == report["receipt_id"]

    assert get_in(report, [
             "microsoft_extensions_ai",
             "chat_response_additional_properties",
             "wardwright_fidelity"
           ]) == "framework_receipt_correlated"

    refute get_in(report, [
             "microsoft_extensions_ai",
             "chat_response_additional_properties",
             "native_framework_state_claimed"
           ])

    assert get_in(report, ["semantic_kernel", "support_level"]) ==
             "guidance_on_microsoft_extensions_ai_path"

    assert get_in(report, ["semantic_kernel", "filter_or_plugin_smoke"]) == "deferred"

    assert get_in(report, ["semantic_kernel", "guidance", "service_registration"]) ==
             "IChatClient"

    assert get_in(report, ["semantic_kernel", "guidance", "filters"]) == [
             "IFunctionInvocationFilter",
             "IPromptRenderFilter",
             "IAutoFunctionInvocationFilter"
           ]

    refute get_in(report, ["semantic_kernel", "guidance", "wardwright_planner_claimed"])
    refute get_in(report, ["semantic_kernel", "guidance", "native_kernel_state_claimed"])

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    receipt = Wardwright.ReceiptStore.get(report["receipt_id"])

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => "tenant-dotnet-smoke"
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) ==
             "app-microsoft-extensions-ai"

    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == "agent-dotnet"
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == "user-dotnet-smoke"
    assert get_in(receipt, ["caller", "session_id", "value"]) == "session-dotnet-smoke"
    assert get_in(receipt, ["caller", "run_id", "value"]) == "run-dotnet-smoke"
    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~ "dotnet-smoke-"

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "microsoft-extensions-ai",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "semantic-kernel",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end
end
