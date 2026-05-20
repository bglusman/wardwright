defmodule Wardwright.PolicyScenarioFixtureTest do
  use ExUnit.Case, async: false

  @fixture_path Path.expand("fixtures/policy_scenarios/control_layer_scenarios.json", __DIR__)

  @scenario_ids [
    "no-result-is-not-tool-failure",
    "read-before-edit",
    "oversized-diff-rejection",
    "malformed-tool-call-retry",
    "context-compaction-breakpoint",
    "leading-canary-sentinel"
  ]

  setup do
    Wardwright.PolicyScenarioStore.configure_storage(nil)
    Wardwright.PolicyScenarioStore.clear()

    on_exit(fn ->
      Wardwright.PolicyScenarioStore.configure_storage(nil)
      Wardwright.PolicyScenarioStore.clear()
    end)

    :ok
  end

  test "public control-layer scenario fixtures load, project, and export as pinned evidence" do
    assert {:ok, _state} = Wardwright.PolicyScenarioStore.configure_storage(@fixture_path)

    scenarios = Wardwright.PolicyScenarioStore.list("tool-governance")
    assert Enum.map(scenarios, & &1.id) == @scenario_ids
    assert Enum.all?(scenarios, &(&1.source == "fixture"))
    assert Enum.all?(scenarios, & &1.pinned)

    fixture_text = Jason.encode!(Enum.map(scenarios, &Wardwright.PolicyScenario.to_map/1))
    refute fixture_text =~ "Bearer "
    refute fixture_text =~ "sk-"
    refute fixture_text =~ "192.168."

    simulations = Wardwright.PolicyProjection.simulations("tool-governance")
    assert Enum.map(simulations, & &1["scenario_id"]) == @scenario_ids
    assert Enum.all?(simulations, &(&1["scenario_source"] == "persisted"))
    assert Enum.all?(simulations, &(&1["source"] == "fixture"))
    assert Enum.all?(simulations, &String.starts_with?(&1["artifact_hash"], "sha256:"))

    assert {:ok, pack} = Wardwright.PolicyScenarioStore.regression_export("tool-governance")
    assert pack["scenario_count"] == 6
    assert Enum.map(pack["scenarios"], & &1["scenario_id"]) == @scenario_ids
    assert Enum.all?(pack["scenarios"], &(&1["pinned"] == true))

    assert {:ok, source} = WardwrightWeb.PolicyScenarioRegression.exunit_source(pack)
    assert [{module, _bytecode}] = Code.compile_string(source)
    assert module.regression_pack()["scenario_count"] == 6
    assert :ok = module.validate_pack!()
  end
end
