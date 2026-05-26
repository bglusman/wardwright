defmodule Wardwright.GleamFrameworkAdapterTest do
  use ExUnit.Case, async: true

  test "contract version marks framework adapters as separate from local install adapters" do
    assert :wardwright@framework_adapter.contract_version() ==
             "wardwright.framework_adapter.v0"
  end

  test "surface classification keeps framework SDKs separate from local coding agents" do
    assert :wardwright@framework_adapter.surface_family("vercel-ai-sdk") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("langchain") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("langgraph") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("pydantic-ai") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("openai-agents-sdk") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("microsoft-extensions-ai") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("semantic-kernel") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("llamaindex") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("jido") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("jido-ai") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("alloy-ex") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("glopenai") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("starlet") == "framework_sdk"
    assert :wardwright@framework_adapter.surface_family("glean") == "framework_sdk"

    assert :wardwright@framework_adapter.surface_family("opencode") == "local_coding_agent"
    assert :wardwright@framework_adapter.surface_family("openclaw") == "local_coding_agent"
    assert :wardwright@framework_adapter.surface_family("aider") == "local_coding_agent"

    assert :wardwright@framework_adapter.surface_family("unknown-agent") == "unsupported"
  end

  test "support tier classification prefers the strongest proven integration point" do
    assert :wardwright@framework_adapter.support_tier(true, false, false, false) == "recipe_only"
    assert :wardwright@framework_adapter.support_tier(true, true, false, false) == "helper_package"
    assert :wardwright@framework_adapter.support_tier(true, true, true, false) == "middleware"

    assert :wardwright@framework_adapter.support_tier(true, true, true, true) ==
             "native_runtime_adapter"

    assert :wardwright@framework_adapter.support_tier(false, false, false, false) == "unsupported"
  end

  test "fidelity wording does not upgrade generic gateway traffic without provenance and receipt evidence" do
    assert :wardwright@framework_adapter.framework_fidelity(true, false, false, false) ==
             "generic_openai_compatible"

    assert :wardwright@framework_adapter.framework_fidelity(true, true, false, false) ==
             "generic_openai_compatible"

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, true) ==
             "native_framework_state_verified"

    assert :wardwright@framework_adapter.framework_fidelity(false, true, true, true) == "unsupported"
  end

  test "smoke status fails closed and names the missing behavior" do
    assert :wardwright@framework_adapter.smoke_status(true, true, true, true, true) == "passed"

    assert :wardwright@framework_adapter.smoke_status(true, false, true, true, false) == "failed"

    assert :wardwright@framework_adapter.missing_smoke_requirements(
             true,
             false,
             true,
             true,
             false
           ) == [
             "provenance_reaches_wardwright",
             "fallback_honest"
           ]
  end

  test "framework receipt correlation requires a framework surface plus provenance and receipt evidence" do
    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "vercel-ai-sdk",
             true,
             true
           )

    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "jido-ai",
             true,
             true
           )

    refute :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "vercel-ai-sdk",
             true,
             false
           )

    refute :wardwright@framework_adapter.framework_receipt_correlation_ready(
             "opencode",
             true,
             true
           )
  end
end
