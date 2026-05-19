defmodule Wardwright.GleamPolicyCoreTest do
  use ExUnit.Case, async: true

  alias Wardwright.ElixirReference.ActionCore, as: ActionCoreReference
  alias Wardwright.ElixirReference.AlertCore, as: AlertCoreReference
  alias Wardwright.ElixirReference.PlanCore, as: PlanCoreReference
  alias Wardwright.ElixirReference.ProjectionCore, as: ProjectionCoreReference
  alias Wardwright.ElixirReference.RouteCore, as: RouteCoreReference
  alias Wardwright.ElixirReference.StreamCore, as: StreamCoreReference
  alias Wardwright.ElixirReference.StructuredCore, as: StructuredCoreReference
  alias Wardwright.ElixirReference.StructuredValidationCore, as: StructuredValidationCoreReference
  alias Wardwright.ElixirReference.ToolContextCore, as: ToolContextCoreReference
  alias Wardwright.Policy.Action
  alias Wardwright.Policy.AlertCore
  alias Wardwright.Policy.HistoryCore
  alias Wardwright.Policy.PlanCore
  alias Wardwright.Policy.StructuredCore
  alias Wardwright.Policy.StructuredOutput
  alias Wardwright.PolicyCoreReference

  Code.require_file("../src/wardwright/elixir_reference/policy_core_reference.exs", __DIR__)

  test "structured core classifies successful guard-loop outcomes" do
    assert StructuredCore.success_status(0) == "completed"
    assert StructuredCore.success_status(2) == "completed_after_guard"

    assert StructuredCore.guard_rule_id_for_string(
             "semantic_validation",
             "structured-json",
             "minimum-confidence"
           ) == "minimum-confidence"
  end

  test "structured core classifies guard budget exhaustion before another retry" do
    assert StructuredCore.loop_outcome_status(
             "minimum-confidence",
             2,
             2,
             2,
             4
           ) == "exhausted_rule_budget"

    assert StructuredCore.loop_outcome_status(
             "structured-json",
             1,
             2,
             4,
             4
           ) == "exhausted_guard_budget"

    assert StructuredCore.loop_outcome_status(
             "structured-json",
             1,
             2,
             3,
             4
           ) == "continue"
  end

  test "history core classifies threshold decisions over the recent window" do
    decision =
      HistoryCore.count_decision([true, false, true, true],
        threshold: 2,
        recent_limit: 3,
        working_set_size: 4,
        scope: "session_id"
      )

    assert {:triggered, "session_id", 2, 2, 3, 4} = decision

    decision =
      HistoryCore.count_decision([true, true, true, true],
        threshold: 3,
        recent_limit: 2,
        working_set_size: 4,
        scope: "session_id"
      )

    assert {:not_triggered, "session_id", 2, 3, 2, 4} = decision

    assert HistoryCore.triggered_count?(3, 3)
    refute HistoryCore.triggered_count?(2, 3)
  end

  test "plan core classifies policy thresholds, sequence windows, and scope decisions" do
    assert PlanCore.threshold(0) == 1
    assert PlanCore.threshold_triggered?(2, 2)
    refute PlanCore.threshold_triggered?(1, 2)

    assert PlanCore.tool_policy_status("block") == "blocked"
    assert PlanCore.tool_policy_status("switch_model") == "rerouted"
    assert PlanCore.tool_policy_status("alert_async") == "alerted"
    assert PlanCore.tool_policy_status("annotate") == "allowed"

    assert PlanCore.scope_label("") == "session"
    assert PlanCore.scope_label("run_id") == "run"

    assert PlanCore.state_scope_matches?("", "reviewing")
    assert PlanCore.state_scope_matches?("reviewing", "reviewing")
    refute PlanCore.state_scope_matches?("reviewing", "active")

    assert PlanCore.sequence_window_limit(nil, nil) == 21
    assert PlanCore.sequence_window_limit(0, nil) == 2
    assert PlanCore.sequence_window_limit(nil, 4) == 5

    assert PlanCore.within_wall_clock_window?(100, 1_100, 1_001)
    refute PlanCore.within_wall_clock_window?(100, 1_102, 1_001)

    assert PlanCore.event_after?(10, 2, 10, 1)
  end

  test "alert core classifies queue capacity, duplicate, and terminal states" do
    config = %{"capacity" => 1, "on_full" => "dead_letter"}
    alert = %{"idempotency_key" => "key-1", "rule_id" => "alert-rule", "session_id" => "s1"}

    assert %{
             key: "key-1",
             outcome: "queued",
             queue_capacity: 1,
             queue_depth: 1
           } = AlertCore.decide_enqueue(config, 0, false, alert)

    assert %{outcome: "duplicate_suppressed"} =
             AlertCore.decide_enqueue(config, 1, true, alert)

    assert %{outcome: "dead_lettered"} =
             AlertCore.decide_enqueue(config, 1, false, alert)

    refute AlertCore.terminal?(:enqueued)
    assert AlertCore.terminal?(:dead_lettered)
  end

  test "action core normalizes policy actions and conflicts" do
    action =
      Action.normalize(
        %{"action" => "restrict_routes", "rule_id" => "private-local-only"},
        rule: %{"kind" => "route_gate", "priority" => "25"}
      )

    assert %{
             "action" => "restrict_routes",
             "action_schema" => "wardwright.policy_action.v1",
             "conflict_key" => "route_constraints",
             "conflict_policy" => "ordered",
             "effect_type" => "route_constraint",
             "kind" => "route_gate",
             "phase" => "request.routing",
             "priority" => 25,
             "rule_id" => "private-local-only"
           } = action

    assert [
             %{
               "action_count" => 2,
               "class" => "ordered",
               "conflict_schema" => "wardwright.policy_conflict.v1",
               "key" => "route_constraints",
               "required_resolution" => "preserve policy declaration order",
               "rule_ids" => ["local-only", "strong-model"]
             }
           ] =
             Action.conflicts([
               Action.normalize(%{
                 "action" => "restrict_routes",
                 "kind" => "route_gate",
                 "rule_id" => "local-only"
               }),
               Action.normalize(%{
                 "action" => "switch_model",
                 "kind" => "route_gate",
                 "rule_id" => "strong-model"
               })
             ])
  end

  test "action result core keeps policy blocks distinct from successful annotations" do
    assert %{
             "action" => "block",
             "actions" => [%{"effect_type" => "terminal", "rule_id" => "deny"}],
             "result_schema" => "wardwright.policy_result.v1",
             "status" => "ok"
           } =
             Action.normalize_result(%{
               "actions" => [%{"action" => "block", "rule_id" => "deny"}],
               "engine" => "primitive",
               "status" => "ok"
             })

    assert %{
             "action" => "block",
             "actions" => [],
             "status" => "error"
           } =
             Action.normalize_result(%{
               "engine" => "wasm",
               "reason" => "engine unavailable",
               "status" => "error"
             })
  end

  test "route core classifies route strategies and reasons" do
    config = %{
      "dispatchers" => [%{"id" => "fit-dispatcher", "models" => ["small/model", "medium/model", "large/model"]}],
      "model_id" => "unit-model",
      "targets" => [
        %{"context_window" => 16, "model" => "small/model"},
        %{"context_window" => 64, "model" => "medium/model"},
        %{"context_window" => 256, "model" => "large/model"}
      ],
      "version" => "unit-version"
    }

    assert %{
             reason: "estimated prompt exceeded smaller configured context windows",
             route_id: "fit-dispatcher",
             route_type: "dispatcher",
             selected_model: "medium/model",
             selected_provider: "medium",
             skipped: [%{"reason" => "context_window_too_small", "target" => "small/model"}]
           } = Wardwright.RoutePlanner.select(config, 32)

    assert %{
             fallback_used: true,
             reason: "policy forced model was not in the allowed route set; explicit policy fallback allowed",
             route_type: "policy_override_fallback",
             selected_model: "medium/model"
           } =
             Wardwright.RoutePlanner.select(config, 32, %{
               "allow_fallback" => true,
               "forced_model" => "missing/model"
             })
  end

  test "Gleam policy cores produce representative route and policy decisions" do
    assert StructuredCore.success_status(1) == "completed_after_guard"

    assert {:triggered, "session_id", 2, 2, 3, 3} =
             HistoryCore.count_decision([true, false, true],
               threshold: 2,
               recent_limit: 3,
               working_set_size: 3,
               scope: "session_id"
             )

    assert %{outcome: "failed_closed"} =
             AlertCore.decide_enqueue(
               %{"capacity" => 1, "on_full" => "fail_closed"},
               1,
               false,
               %{"idempotency_key" => "key-1", "rule_id" => "alert-rule"}
             )

    assert %{"action" => "block", "effect_type" => "terminal"} =
             Action.normalize(%{
               "action" => "block",
               "kind" => "request_guard",
               "message" => "private data blocked",
               "rule_id" => "block-private"
             })

    assert %{route_type: "dispatcher", selected_model: "medium/model"} =
             Wardwright.RoutePlanner.select(
               %{
                 "dispatchers" => [
                   %{"id" => "fit-dispatcher", "models" => ["small/model", "medium/model", "large/model"]}
                 ],
                 "model_id" => "unit-model",
                 "route_root" => "fit-dispatcher",
                 "targets" => [
                   %{"context_window" => 16, "model" => "small/model"},
                   %{"context_window" => 64, "model" => "medium/model"},
                   %{"context_window" => 256, "model" => "large/model"}
                 ],
                 "version" => "unit-version"
               },
               32
             )
  end

  test "extended Gleam kernels produce public policy-surface decisions" do
    assert %{
             reason: "policy forced model was too small for estimated prompt",
             route_blocked: true,
             selected_model: "unconfigured/no-target"
           } = route_forced_model_context_block()

    assert [
             {:ok, "answer_v1", %{"answer" => "final"}},
             {:error, "semantic_validation", "answer-not-draft"},
             {:error, "schema_validation", "structured-json"}
           ] = structured_output_validation_results()

    assert [
             %{action: "rewrite_chunk", chunks: rewritten_chunks, status: "completed"},
             %{action: "drop_chunk", chunks: dropped_chunks, status: "completed"}
           ] = stream_window_results()

    assert Enum.join(rewritten_chunks) == "abc NewClient( done"
    assert Enum.join(dropped_chunks) == "keep  done"

    assert [context, true, false] = tool_context_results()
    assert context["phase"] == "result_interpretation"
    assert get_in(context, ["primary_tool", "namespace"]) == "openai.function"
    assert get_in(context, ["primary_tool", "name"]) == "create_ticket"

    assert [1, true, "rerouted", "session", false, 2, false, true] = plan_core_results()

    assert [
             ["observing", "guarding", "retrying", "recording"],
             [],
             %{"actions" => ["state_transition"]},
             %{"actions" => ["deny_tool"]},
             route_effects
           ] = projection_results()

    assert Enum.any?(route_effects, &(&1["target"] == "route"))
  end

  test "Gleam cores stay equivalent to executable Elixir reference documentation" do
    assert :wardwright@structured_core.guard_action() ==
             StructuredCoreReference.guard_action()

    assert :wardwright@structured_core.success_status(2) ==
             PolicyCoreReference.success_status(2)

    assert :wardwright@structured_core.loop_outcome_status("semantic", 3, 2, 1, 4) ==
             PolicyCoreReference.loop_outcome_status("semantic", 3, 2, 1, 4)

    assert HistoryCore.count_decision([true, false, true, true],
             threshold: 2,
             recent_limit: 3,
             working_set_size: 4,
             scope: "session_id"
           ) ==
             PolicyCoreReference.count_decision([true, false, true, true],
               threshold: 2,
               recent_limit: 3,
               working_set_size: 4,
               scope: "session_id"
             )

    assert :wardwright@plan_core.threshold(0) == PolicyCoreReference.plan_threshold(0)
    assert :wardwright@plan_core.threshold_triggered(3, 2)
    assert :wardwright@plan_core.tool_policy_status("reroute") == "rerouted"
    assert :wardwright@plan_core.scope_label("session_id") == "session"
    assert :wardwright@plan_core.state_scope_matches("reviewing", "active") == false
    assert :wardwright@plan_core.sequence_window_limit(true, 0) == 2
    assert :wardwright@plan_core.within_wall_clock_window(true, 50, 120, 60) == false
    assert :wardwright@plan_core.event_after(120, 0, 100, 99)

    assert AlertCore.decide_enqueue(
             %{"capacity" => 1, "on_full" => "fail_closed"},
             1,
             false,
             %{"idempotency_key" => "key-1", "rule_id" => "alert-rule", "session_id" => "s1"}
           ).status ==
             AlertCoreReference.decide_enqueue(
               %{capacity: 1, on_full: :fail_closed},
               1,
               false,
               %{idempotency_key: "key-1", rule_id: "alert-rule", session_id: "s1"}
             ).status

    assert AlertCore.terminal?(:dead_lettered) ==
             AlertCoreReference.terminal?(:dead_lettered)

    assert :wardwright@structured_validation_core.object_schema_valid(true, true, false) ==
             StructuredValidationCoreReference.object_schema_valid?(true, true, false)

    assert :wardwright@structured_validation_core.string_property_valid(true, 4, 3, true) ==
             StructuredValidationCoreReference.string_property_valid?(true, 4, 3, true)

    assert :wardwright@structured_validation_core.number_property_valid(true, true, false) ==
             StructuredValidationCoreReference.number_property_valid?(true, true, false)

    assert :wardwright@structured_validation_core.string_array_property_valid(true, false) ==
             StructuredValidationCoreReference.string_array_property_valid?(true, false)

    assert :wardwright@structured_validation_core.semantic_number_rule_valid(true, true) ==
             StructuredValidationCoreReference.semantic_number_rule_valid?(true, true)

    assert :wardwright@structured_validation_core.semantic_string_not_contains_valid(true, true) ==
             StructuredValidationCoreReference.semantic_string_not_contains_valid?(true, true)

    assert :wardwright@projection_core.state_ids("tts-retry", true) ==
             ProjectionCoreReference.state_ids("tts-retry", true)

    assert :wardwright@projection_core.route_action("", true) ==
             ProjectionCoreReference.route_action("", true)

    assert :wardwright@projection_core.tool_action("tool_sequence", "", "deny_tool", "") ==
             ProjectionCoreReference.tool_action("tool_sequence", "", "deny_tool", "")

    assert :wardwright@projection_core.tool_rule_phase(false, true) ==
             ProjectionCoreReference.tool_rule_phase(false, true)

    assert :wardwright@projection_core.tool_context_phase("tool.loop_governing") ==
             ProjectionCoreReference.tool_context_phase("tool.loop_governing")

    assert :wardwright@route_core.normalize_alloy_strategy("all") ==
             RouteCoreReference.normalize_alloy_strategy("all")

    assert :wardwright@route_core.default_root("", "dispatcher.a", "cascade.a", "alloy.a") ==
             RouteCoreReference.default_root("", "dispatcher.a", "cascade.a", "alloy.a")

    assert :wardwright@route_core.validate_strategy("round_robin") ==
             RouteCoreReference.validate_strategy("round_robin")

    assert :wardwright@route_core.forced_fallback_reason("policy forced selected model") ==
             RouteCoreReference.forced_fallback_reason("policy forced selected model")

    assert :wardwright@tool_context_core.inferred_phase(false, true, false) ==
             ToolContextCoreReference.inferred_phase(false, true, false)

    assert :wardwright@tool_context_core.inferred_confidence(false, false, 1, false) ==
             ToolContextCoreReference.inferred_confidence(false, false, 1, false)

    assert :wardwright@tool_context_core.default_namespace(false, "function") ==
             ToolContextCoreReference.default_namespace(false, "function")

    assert :wardwright@tool_context_core.list_matches(["shell.exec"], "shell.exec") ==
             ToolContextCoreReference.list_matches?(["shell.exec"], "shell.exec")

    for {action, scope} <- [
          {"rewrite", "stream_window"},
          {"rewrite_chunk", "chunk"},
          {"drop_chunk", "chunk"},
          {"retry_with_reminder", "chunk"},
          {"pass", "chunk"},
          {"annotate", "chunk"}
        ] do
      assert :wardwright@stream_core.action_tag(action, scope) ==
               StreamCoreReference.action_tag(action, scope)
    end

    assert :wardwright@stream_core.terminal_status("retry_with_reminder") ==
             StreamCoreReference.terminal_status("retry_with_reminder")

    assert :wardwright@stream_core.release_budget(10, 16) ==
             StreamCoreReference.release_budget(10, 16)

    for {kind, action} <- [
          {"route_gate", "restrict_routes"},
          {"request_guard", "block"},
          {"history_threshold", "annotate"},
          {"custom", "unknown"}
        ] do
      assert :wardwright@action_core.phase(kind, action) ==
               ActionCoreReference.phase(kind, action)

      assert :wardwright@action_core.effect_type(action) ==
               ActionCoreReference.effect_type(action)

      assert :wardwright@action_core.conflict_key(action) ==
               ActionCoreReference.conflict_key(action)

      assert :wardwright@action_core.conflict_policy(action) ==
               ActionCoreReference.conflict_policy(action)

      assert :wardwright@action_core.default_priority(action) ==
               ActionCoreReference.default_priority(action)
    end

    assert :wardwright@action_core.result_action("ok", false, 0) ==
             PolicyCoreReference.result_action("ok", false, 0)

    assert :wardwright@action_core.result_action("error", false, 0) ==
             PolicyCoreReference.result_action("error", false, 0)

    assert :wardwright@action_core.conflict_resolution("ordered") ==
             ActionCoreReference.conflict_resolution("ordered")

    assert :wardwright@action_core.conflict_summary("terminal_decision", "ordered") ==
             ActionCoreReference.conflict_summary("terminal_decision", "ordered")

    assert PlanCoreReference.threshold_decision(-1, 0) == {:not_triggered, 0, 1}
  end

  defp route_forced_model_context_block do
    Wardwright.RoutePlanner.select(
      %{
        "dispatchers" => [%{"id" => "fit-dispatcher", "models" => ["small/model", "medium/model"]}],
        "model_id" => "unit-model",
        "targets" => [
          %{"context_window" => 16, "model" => "small/model"},
          %{"context_window" => 128, "model" => "medium/model"}
        ],
        "version" => "unit-version"
      },
      64,
      %{"allow_fallback" => false, "forced_model" => "small/model"}
    )
  end

  defp structured_output_validation_results do
    config = %{
      "schemas" => %{
        "answer_v1" => %{
          "additionalProperties" => false,
          "properties" => %{
            "answer" => %{"minLength" => 1, "type" => "string"},
            "citations" => %{"items" => %{"type" => "string"}, "type" => "array"},
            "confidence" => %{"maximum" => 1, "minimum" => 0, "type" => "number"}
          },
          "required" => ["answer", "confidence"],
          "type" => "object"
        }
      },
      "semantic_rules" => [
        %{
          "gte" => 0.7,
          "id" => "minimum-confidence",
          "kind" => "json_path_number",
          "path" => "/confidence"
        },
        %{
          "id" => "answer-not-draft",
          "kind" => "json_path_string_not_contains",
          "path" => "/answer",
          "pattern" => "draft"
        }
      ]
    }

    [
      StructuredOutput.validate_output(
        ~s({"answer":"final","confidence":0.91,"citations":["one"]}),
        config
      )
      |> strip_structured_payload(),
      StructuredOutput.validate_output(
        ~s({"answer":"draft","confidence":0.91}),
        config
      ),
      StructuredOutput.validate_output(
        ~s({"answer":"final","confidence":1.2}),
        config
      )
    ]
  end

  defp strip_structured_payload({:ok, schema_id, parsed}), do: {:ok, schema_id, Map.take(parsed, ["answer"])}

  defp strip_structured_payload(result), do: result

  defp stream_window_results do
    [
      Wardwright.Policy.Stream.evaluate(
        ["abc ", "OldClient(", " done"],
        [
          %{
            "action" => "rewrite_chunk",
            "contains" => "OldClient(",
            "horizon_bytes" => byte_size("OldClient("),
            "id" => "bounded-rewrite",
            "replacement" => "NewClient("
          }
        ]
      )
      |> deterministic_stream_result(),
      Wardwright.Policy.Stream.evaluate(
        ["keep ", "DROP", " done"],
        [
          %{
            "action" => "drop_chunk",
            "contains" => "DROP",
            "horizon_bytes" => byte_size("DROP"),
            "id" => "bounded-drop"
          }
        ]
      )
      |> deterministic_stream_result()
    ]
  end

  defp deterministic_stream_result(result) do
    Map.take(result, [
      :status,
      :action,
      :events,
      :chunks,
      :rewritten_bytes,
      :released_bytes,
      :held_bytes,
      :blocked_bytes,
      :trigger_count,
      :generated_bytes
    ])
  end

  defp tool_context_results do
    {_request, context} =
      Wardwright.ToolContext.normalize_request(%{
        "messages" => [
          %{"role" => "assistant", "tool_calls" => [%{"id" => "call_1"}]},
          %{"content" => "ok", "role" => "tool", "tool_call_id" => "call_1"}
        ],
        "tool_choice" => %{"function" => %{"name" => "create_ticket"}, "type" => "function"},
        "tools" => [
          %{"function" => %{"name" => "create_ticket", "parameters" => %{"type" => "object"}}, "type" => "function"}
        ]
      })

    [
      context,
      Wardwright.ToolContext.matches?(context, %{
        "names" => ["create_ticket"],
        "namespaces" => ["openai.function"],
        "phases" => ["result_interpretation"]
      }),
      Wardwright.ToolContext.matches?(context, %{"risk_classes" => ["write"]})
    ]
  end

  defp plan_core_results do
    [
      PlanCore.threshold(0),
      PlanCore.threshold_triggered?(3, 2),
      PlanCore.tool_policy_status("reroute"),
      PlanCore.scope_label("session_id"),
      PlanCore.state_scope_matches?("reviewing", "active"),
      PlanCore.sequence_window_limit(0, nil),
      PlanCore.within_wall_clock_window?(50, 120, 60),
      PlanCore.event_after?(120, 0, 100, 99)
    ]
  end

  defp projection_results do
    config = %{
      "governance" => [
        %{"allowed_targets" => ["local/model"], "id" => "private-route", "kind" => "route_gate"},
        %{
          "id" => "transition-first",
          "kind" => "tool_sequence",
          "phase" => "tool.loop_governing",
          "then" => %{"action" => "annotate_receipt"},
          "transition_to" => "review_required"
        },
        %{"id" => "deny-shell", "kind" => "tool_denylist", "phase" => "tool.planning"}
      ],
      "model_id" => "unit-model",
      "stream_rules" => [],
      "version" => "unit-version"
    }

    projection = Wardwright.PolicyProjection.projection("tool-governance", config)
    nodes = projection["phases"] |> Enum.flat_map(& &1["nodes"])
    transition_node = Enum.find(nodes, &(&1["id"] == "tool-policy.transition-first"))
    deny_node = Enum.find(nodes, &(&1["id"] == "tool-policy.deny-shell"))

    assert transition_node["writes"] == ["policy.actions", "policy_cache.session.policy_state"]
    assert transition_node["phase"] == "tool.loop_governing"
    assert deny_node["actions"] == ["deny_tool"]
    assert deny_node["writes"] == ["decision.blocked", "tool.allowed"]

    [
      Wardwright.PolicyProjection.state_ids("tts-retry"),
      Wardwright.PolicyProjection.state_ids("unknown-pattern"),
      Map.take(transition_node, ["actions"]),
      Map.take(deny_node, ["actions"]),
      Wardwright.PolicyProjection.projection("route-privacy", config)["effects"]
    ]
  end
end
