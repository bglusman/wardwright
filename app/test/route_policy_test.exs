defmodule Wardwright.RoutePolicyTest do
  use Wardwright.RouterCase

  test "route gate policy constrains planner candidates before provider selection" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 32, "model" => "local/qwen"},
        %{"context_window" => 256, "model" => "managed/kimi"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "restrict_routes",
          "allowed_targets" => ["local"],
          "contains" => "private",
          "id" => "private-local-only",
          "kind" => "route_gate",
          "message" => "private context must stay local"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "private notes, summarize briefly", role: "user"}],
          model: "unit-model"
        }
      })

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "decision", "selected_model"]) == "local/qwen"

    assert get_in(body, ["receipt", "decision", "policy_route_constraints"]) == %{
             "allowed_targets" => ["local"]
           }

    assert [
             %{
               "action" => "restrict_routes",
               "allowed_targets" => ["local"],
               "kind" => "route_gate",
               "rule_id" => "private-local-only"
             }
           ] = get_in(body, ["receipt", "decision", "policy_actions"])
  end

  test "route gate policy fails closed when it removes every provider candidate" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "restrict_routes",
          "allowed_targets" => ["nonexistent-provider"],
          "contains" => "private",
          "id" => "impossible-route",
          "kind" => "route_gate"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "private", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 429
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["wardwright", "status"]) == "policy_failed_closed"
    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()

    assert get_in(receipt, ["decision", "route_blocked"]) == true
    assert get_in(receipt, ["decision", "selected_model"]) == "unconfigured/no-target"

    assert get_in(receipt, ["decision", "policy_route_constraints"]) == %{
             "allowed_targets" => ["nonexistent-provider"]
           }
  end

  test "route gate policy can force a specific model through a route override" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "contains" => "hard proof",
          "id" => "deep-reasoning",
          "kind" => "route_gate",
          "message" => "use the strongest configured model",
          "target_model" => "large/model"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "hard proof", role: "user"}],
          model: "unit-model"
        }
      })

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "decision", "route_type"]) == "policy_override"
    assert get_in(body, ["receipt", "decision", "selected_model"]) == "large/model"

    assert get_in(body, ["receipt", "decision", "policy_route_constraints"]) == %{
             "forced_model" => "large/model"
           }
  end

  test "route override fails closed when the forced model is unavailable" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "contains" => "hard proof",
          "id" => "missing-model",
          "kind" => "route_gate",
          "target_model" => "missing/model"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "hard proof " <> String.duplicate("x", 60), role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 429
    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "policy_failed_closed"

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()
    assert get_in(receipt, ["decision", "route_blocked"]) == true
    assert get_in(receipt, ["decision", "fallback_used"]) == false

    assert get_in(receipt, ["decision", "reason"]) ==
             "policy forced model was not in the allowed route set"
  end

  test "route override only falls back when explicitly allowed" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "allow_fallback" => true,
          "contains" => "hard proof",
          "id" => "missing-model",
          "kind" => "route_gate",
          "target_model" => "missing/model"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "hard proof " <> String.duplicate("x", 60), role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "completed"

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()

    assert get_in(receipt, ["decision", "route_type"]) == "policy_override_fallback"
    assert get_in(receipt, ["decision", "fallback_used"]) == true
    assert get_in(receipt, ["decision", "route_blocked"]) == false
    assert get_in(receipt, ["decision", "selected_model"]) == "medium/model"

    assert get_in(receipt, ["decision", "policy_route_constraints"]) == %{
             "allow_fallback" => true,
             "forced_model" => "missing/model"
           }

    refute Enum.any?(
             get_in(receipt, ["decision", "skipped"]),
             &match?(%{"reason" => "policy_route_gate", "target" => "medium/model"}, &1)
           )

    assert Enum.any?(
             get_in(receipt, ["decision", "skipped"]),
             &match?(%{"reason" => "forced_model_unavailable", "target" => "missing/model"}, &1)
           )

    assert Enum.any?(
             get_in(receipt, ["decision", "skipped"]),
             &match?(%{"reason" => "context_window_too_small", "target" => "tiny/model"}, &1)
           )
  end

  test "route override fails closed when the forced model cannot fit the prompt" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "contains" => "long proof",
          "id" => "too-small-model",
          "kind" => "route_gate",
          "target_model" => "tiny/model"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "long proof " <> String.duplicate("x", 200), role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 429
    body = JSON.decode!(conn.resp_body)

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()
    assert get_in(receipt, ["decision", "route_blocked"]) == true

    assert get_in(receipt, ["decision", "reason"]) ==
             "policy forced model was too small for estimated prompt"

    assert [%{"reason" => "context_window_too_small", "target" => "tiny/model"} | _] =
             get_in(receipt, ["decision", "skipped"])
  end

  test "Dune policy engine can return route constraints used by the planner" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 32, "model" => "local/qwen"},
        %{"context_window" => 256, "model" => "managed/kimi"}
      ])
      |> Map.put("governance", [
        %{
          "engine" => "dune",
          "id" => "dune-route-gate",
          "kind" => "route_gate",
          "source" =>
            ~s(%{"action" => "restrict_routes", "allowed_targets" => ["local"], "reason" => "private route gate"})
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "small request", role: "user"}],
          model: "unit-model"
        }
      })

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "decision", "selected_model"]) == "local/qwen"

    assert get_in(body, ["receipt", "decision", "policy_route_constraints"]) == %{
             "allowed_targets" => ["local"]
           }

    assert [%{"action" => "restrict_routes", "rule_id" => "dune-route-gate"}] =
             get_in(body, ["receipt", "decision", "policy_actions"])

    assert [
             %{
               "action_schema" => "wardwright.policy_action.v1",
               "conflict_key" => "route_constraints",
               "conflict_policy" => "ordered",
               "effect_type" => "route_constraint",
               "phase" => "request.routing",
               "source" => %{"engine" => "dune", "status" => "ok", "type" => "engine"}
             }
           ] = get_in(body, ["receipt", "decision", "policy_actions"])
  end

  test "route-affecting policy actions expose ordered conflict metadata" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 32, "model" => "local/qwen"},
        %{"context_window" => 256, "model" => "managed/kimi"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "restrict_routes",
          "allowed_targets" => ["local"],
          "contains" => "private",
          "id" => "private-local-provider",
          "kind" => "route_gate"
        },
        %{
          "action" => "switch_model",
          "contains" => "private",
          "id" => "private-specific-model",
          "kind" => "route_gate",
          "target_model" => "local/qwen"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "private working notes", role: "user"}],
          model: "unit-model"
        }
      })

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "decision", "policy_route_constraints"]) == %{
             "allowed_targets" => ["local"],
             "forced_model" => "local/qwen"
           }

    assert [
             %{
               "class" => "ordered",
               "conflict_schema" => "wardwright.policy_conflict.v1",
               "key" => "route_constraints",
               "required_resolution" => "preserve policy declaration order",
               "rule_ids" => ["private-local-provider", "private-specific-model"]
             }
           ] = get_in(body, ["receipt", "decision", "policy_conflicts"])
  end
end
