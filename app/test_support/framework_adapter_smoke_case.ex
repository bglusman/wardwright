defmodule Wardwright.FrameworkAdapterSmokeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import ExUnit.Assertions
  import Wardwright.RouterCase

  using do
    quote do
      use Wardwright.RouterCase

      import Wardwright.FrameworkAdapterSmokeCase
    end
  end

  def run_framework_adapter_smoke(spec) do
    assert call(:post, "/__test/config", framework_smoke_config(spec)).status == 200

    executable = framework_smoke_executable!(Map.fetch!(spec, :runtime), Map.fetch!(spec, :name))
    smoke = Path.expand("../priv/framework_adapters/#{Map.fetch!(spec, :smoke)}", __DIR__)

    {output, status} =
      System.cmd(
        executable,
        [smoke, "--base-url", wardwright_router_base_url(), "--model", "unit-model"],
        stderr_to_stdout: true
      )

    assert status == 0, output

    report = JSON.decode!(output)

    assert_common_framework_smoke!(report, Map.fetch!(spec, :canned_model))
    assert_receipt_caller!(report["receipt_id"], Map.fetch!(spec, :caller))

    report
  end

  def assert_common_framework_smoke!(report, canned_model) do
    assert report["support_tier"] == "recipe_only"
    assert report["fidelity"] == "framework_receipt_correlated"
    assert report["requested_model"] == "unit-model"
    assert report["selected_model"] == canned_model
    assert report["captured_receipts"] == [report["receipt_id"]]

    assert report["fallback"] == %{
             "adapter_receipt_claim" => false,
             "generic_openai_compatible" => true
           }

    assert :wardwright@framework_adapter.smoke_status(true, true, true, true, true) == "passed"
    assert :wardwright@framework_adapter.missing_smoke_requirements(true, true, true, true, true) == []

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"
  end

  def assert_receipt_caller!(receipt_id, expected) do
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["caller", "tenant_id"]) == %{
             "source" => "header",
             "value" => Map.fetch!(expected, :tenant_id)
           }

    assert get_in(receipt, ["caller", "application_id", "value"]) == Map.fetch!(expected, :application_id)
    assert get_in(receipt, ["caller", "consuming_agent_id", "value"]) == Map.fetch!(expected, :consuming_agent_id)
    assert get_in(receipt, ["caller", "consuming_user_id", "value"]) == Map.fetch!(expected, :consuming_user_id)
    assert get_in(receipt, ["caller", "session_id", "value"]) == Map.fetch!(expected, :session_id)
    assert get_in(receipt, ["caller", "run_id", "value"]) == Map.fetch!(expected, :run_id)

    assert get_in(receipt, ["caller", "client_request_id", "value"]) =~
             Map.fetch!(expected, :client_request_id_prefix)
  end

  def assert_framework_receipt_ready!(surface) do
    assert :wardwright@framework_adapter.framework_receipt_correlation_ready(surface, true, true)
  end

  defp framework_smoke_config(spec) do
    unit_policy_config()
    |> Map.put("governance", [])
    |> Map.put("targets", [
      %{
        "canned_outputs" => [Map.fetch!(spec, :canned_output)],
        "context_window" => 256,
        "model" => Map.fetch!(spec, :canned_model),
        "provider_kind" => "canned_sequence"
      }
    ])
  end

  defp framework_smoke_executable!(:node, name) do
    System.find_executable("node") || flunk("node is required for the #{name} smoke")
  end

  defp framework_smoke_executable!(:python, name) do
    System.find_executable("python3") ||
      System.find_executable("python") ||
      flunk("python is required for the #{name} smoke")
  end
end
