defmodule Wardwright.PolicyProjectionTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint WardwrightWeb.Endpoint

  setup_all do
    original_config = Application.get_env(:wardwright, WardwrightWeb.Endpoint, [])

    endpoint_config =
      Keyword.merge(original_config,
        http: [ip: {127, 0, 0, 1}, port: 0],
        server: false,
        secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))
      )

    Application.put_env(:wardwright, WardwrightWeb.Endpoint, endpoint_config)
    start_supervised!(WardwrightWeb.Endpoint)

    on_exit(fn ->
      Application.put_env(:wardwright, WardwrightWeb.Endpoint, original_config)
    end)

    :ok
  end

  setup do
    Wardwright.reset_config()
    Wardwright.ReceiptStore.clear()
    Wardwright.ModelApiKeyStore.reset!()
    Wardwright.PolicyScenarioStore.clear()
    Wardwright.PolicyCache.reset()
    :ok
  end

  test "policy projection exposes stable review fields and confidence classes" do
    :ok = put_route_gate_config()
    projection = Wardwright.PolicyProjection.projection("route-privacy")

    assert projection["projection_schema"] == "wardwright.policy_projection.v1"
    assert projection["engine"]["language"] == "structured"
    assert projection["artifact"]["artifact_hash"] =~ "sha256:"
    assert projection["compiled_plan"]["planner"] == "Wardwright.Policy.Plan"
    assert projection["state_machine"]["schema"] == "wardwright.policy_state_machine.v1"
    assert projection["state_machine"]["default_projection"] == true
    assert [%{"id" => "active", "node_ids" => node_ids}] = projection["state_machine"]["states"]

    nodes = projection["phases"] |> Enum.flat_map(& &1["nodes"])
    assert Enum.any?(nodes, &(&1["id"] == "request-policy.private-route-gate"))
    assert Enum.any?(nodes, &(&1["confidence"] == "exact"))
    assert Enum.all?(nodes, &is_binary(&1["node_class"]))
    assert Enum.all?(nodes, &is_binary(get_in(&1, ["annotations", "why"])))
    assert Enum.all?(nodes, &is_binary(get_in(&1, ["annotations", "change_when"])))
    assert "request-policy.private-route-gate" in node_ids
    assert [%{"class" => "ordered"}] = projection["conflicts"]
  end

  test "simulation traces link execution evidence back to projection nodes" do
    projection = Wardwright.PolicyProjection.projection("tts-retry")
    node_ids = projection["phases"] |> Enum.flat_map(& &1["nodes"]) |> MapSet.new(& &1["id"])

    [simulation | _] = Wardwright.PolicyProjection.simulations("tts-retry")

    assert simulation["artifact_hash"] == projection["artifact"]["artifact_hash"]
    assert simulation["verdict"] in ["passed", "failed", "inconclusive"]
    assert Enum.any?(simulation["trace"], &MapSet.member?(node_ids, &1["node_id"]))
    assert Enum.all?(simulation["trace"], &is_binary(&1["state_id"]))
    assert is_map(simulation["receipt_preview"])

    assert projection["state_machine"]["default_projection"] == false

    assert Enum.map(projection["state_machine"]["states"], & &1["id"]) == [
             "observing",
             "guarding",
             "retrying",
             "recording"
           ]

    assert Enum.map(projection["state_machine"]["states"], & &1["model_id"]) == [
             Wardwright.local_model(),
             "none",
             Wardwright.managed_model(),
             "none"
           ]

    assert Enum.map(projection["state_machine"]["simulation_steps"], & &1["state"]) == [
             "observing",
             "guarding",
             "retrying",
             "retrying",
             "recording"
           ]
  end

  test "projection simulations prefer persisted reviewed scenarios over fixtures" do
    assert {:ok, _scenario} =
             Wardwright.PolicyScenarioStore.create("tts-retry", %{
               "expected_behavior" => "Retry is requested before any violating bytes are released.",
               "input_summary" => "Reviewed request keeps OldClient split across stream chunks.",
               "pinned" => true,
               "receipt_preview" => %{"final_status" => "simulated"},
               "scenario_id" => "reviewed-split-trigger",
               "source" => "assistant",
               "title" => "Reviewed split trigger",
               "trace" => [
                 %{
                   "detail" => "persisted scenario hit the stream rule",
                   "id" => "r1",
                   "kind" => "match",
                   "label" => "reviewed match",
                   "node_id" => "tts.no-old-client",
                   "phase" => "response.streaming",
                   "severity" => "pass",
                   "state_id" => "guarding"
                 }
               ],
               "verdict" => "passed"
             })

    [simulation] = Wardwright.PolicyProjection.simulations("tts-retry")
    projection = Wardwright.PolicyProjection.projection("tts-retry")

    assert simulation["scenario_id"] == "reviewed-split-trigger"
    assert simulation["scenario_source"] == "persisted"
    assert simulation["source"] == "assistant"
    assert simulation["pinned"] == true
    assert simulation["artifact_hash"] == projection["artifact"]["artifact_hash"]
    assert get_in(simulation, ["trace", Access.at(0), "state_id"]) == "guarding"

    assert Enum.map(projection["state_machine"]["simulation_steps"], & &1["state"]) == [
             "guarding"
           ]
  end

  test "route projection simulation is derived from configured policy plan actions" do
    :ok = put_route_gate_config()
    [simulation] = Wardwright.PolicyProjection.simulations("route-privacy")

    assert simulation["scenario_id"] == "configured-route-policy"
    assert simulation["verdict"] == "passed"

    assert [
             %{
               "action" => "restrict_routes",
               "allowed_targets" => [local_model],
               "rule_id" => "private-route-gate"
             }
           ] = get_in(simulation, ["receipt_preview", "decision", "policy_actions"])

    assert local_model == Wardwright.local_model()

    assert %{"allowed_targets" => [^local_model]} =
             get_in(simulation, ["receipt_preview", "decision", "route_constraints"])
  end

  test "tool governance projection exposes tool phases without enforcing spike semantics" do
    :ok = put_tool_governance_config()

    projection = Wardwright.PolicyProjection.projection("tool-governance")
    [simulation] = Wardwright.PolicyProjection.simulations("tool-governance")

    assert projection["engine"]["engine_id"] == "tool-context-plan"

    assert projection["engine"]["capabilities"]["phases"] == [
             "tool.planning",
             "tool.result_interpreting",
             "tool.loop_governing",
             "receipt.finalized"
           ]

    nodes = projection["phases"] |> Enum.flat_map(& &1["nodes"])

    assert Enum.any?(nodes, fn node ->
             node["id"] == "tool-policy.github-write-tools" and
               node["reads"] == [
                 "request.tools",
                 "request.tool_choice",
                 "message.tool_calls",
                 "decision.tool_context"
               ] and
               node["writes"] == ["tool.allowed", "policy.actions"]
           end)

    assert Enum.any?(nodes, &(&1["id"] == "tool.receipt-context"))
    assert [%{"class" => "ordered", "node_ids" => node_ids}] = projection["conflicts"]
    assert "tool-policy.github-write-tools" in node_ids
    assert "tool-policy.shell-write-tools" in node_ids

    assert simulation["scenario_id"] == "configured-tool-policy"
    assert simulation["verdict"] == "passed"

    assert get_in(simulation, ["receipt_preview", "decision", "tool_context", "primary_tool"]) ==
             %{
               "name" => "create_pull_request",
               "namespace" => "mcp.github",
               "risk_class" => "write",
               "source" => "declared_tool"
             }
  end

  test "legacy policy workbench routes redirect to the Lustre workbench" do
    conn = get(build_conn(), "/policies/tts-retry/diagram")
    assert redirected_to(conn, 302) == "/admin"

    conn = get(build_conn(), "/policies/tts-retry/diagram?model=demo-retry-guard")
    assert redirected_to(conn, 302) == "/admin?model=demo-retry-guard"
  end

  defp put_route_gate_config do
    config =
      Wardwright.default_config()
      |> Map.put("governance", [
        %{
          "action" => "restrict_routes",
          "allowed_targets" => [Wardwright.local_model()],
          "contains" => "private-data-risk",
          "id" => "private-route-gate",
          "kind" => "route_gate",
          "message" => "private context must stay local"
        },
        %{
          "action" => "switch_model",
          "contains" => "force-managed",
          "id" => "fallback-route-gate",
          "kind" => "route_gate",
          "message" => "operator selected managed fallback",
          "target_model" => Wardwright.managed_model()
        }
      ])

    assert {:ok, _config} = Wardwright.put_config(config)
    :ok
  end

  defp put_tool_governance_config do
    config =
      Wardwright.default_config()
      |> Map.put("governance", [
        %{
          "action" => "constrain_tools",
          "id" => "github-write-tools",
          "kind" => "tool_selector",
          "name" => "create_pull_request",
          "namespace" => "mcp.github",
          "risk_class" => "write"
        },
        %{
          "action" => "deny_tool",
          "id" => "shell-write-tools",
          "kind" => "tool_denylist",
          "namespace" => "shell",
          "risk_class" => "irreversible"
        },
        %{
          "action" => "fail_closed",
          "id" => "repeat-github-tool",
          "kind" => "tool_loop_threshold",
          "name" => "create_pull_request",
          "namespace" => "mcp.github",
          "threshold" => 3
        },
        %{
          "allowed_tools" => [
            %{"name" => "approve_tool_result", "namespace" => "review", "risk_class" => "read_only"}
          ],
          "id" => "review-state-tool-surface",
          "kind" => "allowed_tools",
          "phase" => "planning",
          "state_scope" => "reviewing_tool_result"
        }
      ])

    assert {:ok, _config} = Wardwright.put_config(config)
    :ok
  end
end
