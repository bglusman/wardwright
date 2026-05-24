defmodule Wardwright.VercelAiSdkAdapterSmokeTest do
  use Wardwright.FrameworkAdapterSmokeCase

  test "Vercel AI SDK fetch helper routes through Wardwright with provenance and captures the receipt id" do
    report =
      run_framework_adapter_smoke(%{
        caller: %{
          application_id: "app-vercel-ai-sdk",
          client_request_id_prefix: "vercel-ai-sdk-smoke-",
          consuming_agent_id: "agent-vercel-ai-sdk",
          consuming_user_id: "user-vercel-smoke",
          run_id: "run-vercel-smoke",
          session_id: "session-vercel-smoke",
          tenant_id: "tenant-vercel-smoke"
        },
        canned_model: "canned/vercel-ai-sdk",
        canned_output: "vercel ai sdk smoke ok",
        name: "Vercel AI SDK",
        runtime: :node,
        smoke: "vercel_ai_sdk/smoke.mjs"
      })

    assert report["framework"] == "vercel-ai-sdk"
    assert report["streaming"] == "deferred"

    assert_framework_receipt_ready!("vercel-ai-sdk")
  end
end
