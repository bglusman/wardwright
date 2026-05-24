defmodule Wardwright.VercelAiSdkAdapterSmokeTest do
  use Wardwright.RouterCase

  test "Vercel AI SDK fetch helper routes through Wardwright with provenance and captures the receipt id" do
    config =
      unit_policy_config()
      |> Map.put("governance", [])
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["vercel ai sdk smoke ok"],
          "context_window" => 256,
          "model" => "canned/vercel-ai-sdk",
          "provider_kind" => "canned_sequence"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    node = System.find_executable("node") || flunk("node is required for the Vercel AI SDK smoke")
    smoke = Path.expand("../priv/framework_adapters/vercel_ai_sdk/smoke.mjs", __DIR__)

    {output, status} =
      System.cmd(
        node,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = JSON.decode!(output)

    assert report["framework"] == "vercel-ai-sdk"
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == "canned/vercel-ai-sdk"
    assert report["streaming"] == "deferred"
    assert report["captured_receipts"] == [report["receipt_id"]]

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    receipt = Wardwright.ReceiptStore.get(report["receipt_id"])

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => "tenant-vercel-smoke"
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) == "app-vercel-ai-sdk"
    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == "agent-vercel-ai-sdk"
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == "user-vercel-smoke"
    assert get_in(receipt, ["caller", "session_id", "value"]) == "session-vercel-smoke"
    assert get_in(receipt, ["caller", "run_id", "value"]) == "run-vercel-smoke"
    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~ "vercel-ai-sdk-smoke-"

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "vercel-ai-sdk",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end
end
