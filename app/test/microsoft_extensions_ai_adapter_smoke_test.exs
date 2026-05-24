defmodule Wardwright.MicrosoftExtensionsAiAdapterSmokeTest do
  use Wardwright.FrameworkAdapterSmokeCase

  test "Microsoft.Extensions.AI recipe routes chat through Wardwright and records ChatResponse receipt metadata" do
    report =
      run_framework_adapter_smoke(%{
        caller: %{
          application_id: "app-microsoft-extensions-ai",
          client_request_id_prefix: "dotnet-smoke-",
          consuming_agent_id: "agent-dotnet",
          consuming_user_id: "user-dotnet-smoke",
          run_id: "run-dotnet-smoke",
          session_id: "session-dotnet-smoke",
          tenant_id: "tenant-dotnet-smoke"
        },
        canned_model: "canned/microsoft-extensions-ai",
        canned_output: "microsoft extensions ai smoke ok",
        name: "Microsoft.Extensions.AI",
        runtime: :python,
        smoke: "microsoft_extensions_ai/smoke.py"
      })

    assert report["framework"] == "microsoft-extensions-ai"
    assert report["streaming"] == "deferred"
    assert report["tool_calling"] == "deferred"
    assert report["native_framework_state"] == "not_claimed"
    assert report["dotnet_package_runtime"] == "not_executed_in_default_smoke"

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

    assert_framework_receipt_ready!("microsoft-extensions-ai")
    assert_framework_receipt_ready!("semantic-kernel")
  end
end
