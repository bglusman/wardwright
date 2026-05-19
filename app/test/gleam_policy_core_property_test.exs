defmodule Wardwright.GleamPolicyCorePropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Wardwright.ElixirReference.ActionCore, as: ActionCoreReference
  alias Wardwright.ElixirReference.AlertCore, as: AlertCoreReference
  alias Wardwright.ElixirReference.HistoryCore, as: HistoryCoreReference
  alias Wardwright.ElixirReference.PlanCore, as: PlanCoreReference
  alias Wardwright.ElixirReference.ProjectionCore, as: ProjectionCoreReference
  alias Wardwright.ElixirReference.RouteCore, as: RouteCoreReference
  alias Wardwright.ElixirReference.StreamCore, as: StreamCoreReference
  alias Wardwright.ElixirReference.StructuredCore, as: StructuredCoreReference
  alias Wardwright.ElixirReference.StructuredValidationCore, as: StructuredValidationCoreReference
  alias Wardwright.ElixirReference.ToolContextCore, as: ToolContextCoreReference

  Code.require_file("../src/wardwright/elixir_reference/policy_core_reference.exs", __DIR__)

  property "action core matches the Elixir reference for valid action and result inputs" do
    check all(
            kind <- policy_kind(),
            action <- policy_action(),
            status <- member_of(["ok", "error", "unknown"]),
            has_blocking_action <- boolean(),
            action_count <- integer(0..8),
            conflict_key <- member_of(["route_constraints", "terminal_decision", "custom_key"]),
            conflict_policy <- member_of(["ordered", "parallel_safe", "last_write_wins"])
          ) do
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

      assert :wardwright@action_core.result_action(status, has_blocking_action, action_count) ==
               ActionCoreReference.result_action(status, has_blocking_action, action_count)

      assert :wardwright@action_core.conflict_summary(conflict_key, conflict_policy) ==
               ActionCoreReference.conflict_summary(conflict_key, conflict_policy)

      assert :wardwright@action_core.conflict_resolution(conflict_policy) ==
               ActionCoreReference.conflict_resolution(conflict_policy)
    end
  end

  property "alert core matches the Elixir reference for valid queue decisions" do
    check all(
            capacity <- integer(0..8),
            queue_depth <- integer(0..10),
            on_full <- member_of([:dead_letter, :drop, :fail_closed]),
            already_seen <- boolean(),
            existing_status <- alert_status(),
            alert <- alert_event()
          ) do
      config = %{capacity: capacity, on_full: on_full}
      gleam_config = {:config, capacity, on_full, :fast, 0}
      gleam_alert = {:alert, alert.idempotency_key, alert.rule_id, alert.session_id}

      assert normalize_alert_decision(
               :wardwright@alert_core.decide_enqueue(
                 gleam_config,
                 queue_depth,
                 already_seen,
                 gleam_alert,
                 existing_status
               )
             ) ==
               AlertCoreReference.decide_enqueue(
                 config,
                 queue_depth,
                 already_seen,
                 alert,
                 existing_status
               )

      assert :wardwright@alert_core.terminal(existing_status) ==
               AlertCoreReference.terminal?(existing_status)
    end
  end

  property "history core matches the Elixir reference for valid match windows" do
    check all(
            matches <- list_of(boolean(), max_length: 40),
            threshold <- integer(-4..16),
            recent_limit <- integer(-4..40),
            working_set_size <- integer(0..60),
            scope <- scope()
          ) do
      assert :wardwright@history_core.count_matches(
               matches,
               threshold,
               recent_limit,
               working_set_size,
               scope
             ) ==
               HistoryCoreReference.count_matches(matches,
                 threshold: threshold,
                 recent_limit: recent_limit,
                 working_set_size: working_set_size,
                 scope: scope
               )
    end
  end

  property "plan core matches the Elixir reference for valid threshold and window inputs" do
    check all(
            count <- integer(-10..40),
            threshold <- integer(-10..40),
            action <- policy_action(),
            scope <- scope(),
            required_state <- state(),
            current_state <- state(),
            has_requested <- boolean(),
            requested <- integer(-4..20),
            has_max_ms <- boolean(),
            max_ms <- integer(-50..500),
            current_ms <- integer(0..1_000),
            prior_ms <- integer(0..1_000),
            left_sequence <- integer(0..100),
            right_sequence <- integer(0..100)
          ) do
      assert :wardwright@plan_core.threshold(threshold) ==
               PlanCoreReference.threshold(threshold)

      assert :wardwright@plan_core.threshold_decision(count, threshold) ==
               PlanCoreReference.threshold_decision(count, threshold)

      assert :wardwright@plan_core.threshold_triggered(count, threshold) ==
               PlanCoreReference.threshold_triggered?(count, threshold)

      assert :wardwright@plan_core.tool_policy_status(action) ==
               PlanCoreReference.tool_policy_status(action)

      assert :wardwright@plan_core.scope_label(scope) ==
               PlanCoreReference.scope_label(scope)

      assert :wardwright@plan_core.state_scope_matches(required_state, current_state) ==
               PlanCoreReference.state_scope_matches?(required_state, current_state)

      assert :wardwright@plan_core.sequence_window_limit(has_requested, requested) ==
               PlanCoreReference.sequence_window_limit(has_requested, requested)

      assert :wardwright@plan_core.within_wall_clock_window(
               has_max_ms,
               max_ms,
               current_ms,
               prior_ms
             ) ==
               PlanCoreReference.within_wall_clock_window?(
                 has_max_ms,
                 max_ms,
                 current_ms,
                 prior_ms
               )

      assert :wardwright@plan_core.event_after(
               current_ms,
               left_sequence,
               prior_ms,
               right_sequence
             ) ==
               PlanCoreReference.event_after?(current_ms, left_sequence, prior_ms, right_sequence)
    end
  end

  property "projection core matches the Elixir reference for valid projection inputs" do
    check all(
            pattern_id <- member_of(["tts-retry", "stream-rewrite-state", "custom-model"]),
            known_pattern <- boolean(),
            route_action <-
              member_of(["", "restrict_routes", "switch_model", "block", "annotate"]),
            has_engine <- boolean(),
            tool_kind <-
              member_of([
                "tool_loop_threshold",
                "tool_sequence",
                "tool_result_guard",
                "tool_denylist",
                "custom"
              ]),
            top_action <- member_of(["", "block", "deny_tool", "constrain_tools"]),
            then_action <- member_of(["", "annotate_receipt", "deny_tool"]),
            transition_to <- member_of(["", "review_required"]),
            is_loop_rule <- boolean(),
            is_result_rule <- boolean(),
            source_type <- member_of(["primitive", "dune", "wasm"]),
            tool_phase <-
              member_of([
                "tool.result_interpreting",
                "tool.loop_governing",
                "tool.planning",
                "custom.phase"
              ])
          ) do
      assert :wardwright@projection_core.state_ids(pattern_id, known_pattern) ==
               ProjectionCoreReference.state_ids(pattern_id, known_pattern)

      assert :wardwright@projection_core.route_action(route_action, has_engine) ==
               ProjectionCoreReference.route_action(route_action, has_engine)

      assert :wardwright@projection_core.route_confidence(has_engine) ==
               ProjectionCoreReference.route_confidence(has_engine)

      assert :wardwright@projection_core.route_effect_target(route_action) ==
               ProjectionCoreReference.route_effect_target(route_action)

      assert :wardwright@projection_core.tool_action(
               tool_kind,
               top_action,
               then_action,
               transition_to
             ) ==
               ProjectionCoreReference.tool_action(
                 tool_kind,
                 top_action,
                 then_action,
                 transition_to
               )

      tool_action =
        ProjectionCoreReference.tool_action(tool_kind, top_action, then_action, transition_to)

      assert :wardwright@projection_core.tool_effect_target(tool_action) ==
               ProjectionCoreReference.tool_effect_target(tool_action)

      assert :wardwright@projection_core.tool_rule_phase(is_loop_rule, is_result_rule) ==
               ProjectionCoreReference.tool_rule_phase(is_loop_rule, is_result_rule)

      assert :wardwright@projection_core.effect_confidence(source_type) ==
               ProjectionCoreReference.effect_confidence(source_type)

      assert :wardwright@projection_core.tool_context_phase(tool_phase) ==
               ProjectionCoreReference.tool_context_phase(tool_phase)
    end
  end

  property "route core matches the Elixir reference for valid selector inputs" do
    check all(
            targets <- list_of(route_target(), max_length: 6),
            estimated_prompt_tokens <- integer(1..128),
            strategy <-
              member_of(["deterministic_all", "weighted", "round_robin", "all", "unknown"]),
            configured_root <- selector_id(),
            first_dispatcher <- selector_id(),
            first_cascade <- selector_id(),
            first_alloy <- selector_id(),
            partial_context <- boolean()
          ) do
      gleam_targets = Enum.map(targets, &gleam_target/1)

      assert :wardwright@route_core.normalize_alloy_strategy(strategy) ==
               RouteCoreReference.normalize_alloy_strategy(strategy)

      assert :wardwright@route_core.validate_strategy(strategy) ==
               RouteCoreReference.validate_strategy(strategy)

      assert :wardwright@route_core.default_root(
               configured_root,
               first_dispatcher,
               first_cascade,
               first_alloy
             ) ==
               RouteCoreReference.default_root(
                 configured_root,
                 first_dispatcher,
                 first_cascade,
                 first_alloy
               )

      assert :wardwright@route_core.alloy_reason(partial_context, length(targets)) ==
               RouteCoreReference.alloy_reason(partial_context, length(targets))

      assert normalize_route_selection(
               :wardwright@route_core.select_dispatcher(
                 gleam_targets,
                 gleam_targets,
                 estimated_prompt_tokens
               )
             ) ==
               RouteCoreReference.select_dispatcher(
                 targets,
                 targets,
                 estimated_prompt_tokens
               )

      assert normalize_route_selection(
               :wardwright@route_core.select_cascade(
                 gleam_targets,
                 gleam_targets,
                 estimated_prompt_tokens
               )
             ) ==
               RouteCoreReference.select_cascade(targets, targets, estimated_prompt_tokens)
    end
  end

  property "stream core matches the Elixir reference for valid stream action inputs" do
    check all(
            action <- stream_action(),
            match_scope <- member_of(["chunk", "stream_window", "response"]),
            observed_ms <- integer(0..1_000),
            max_hold_ms <- integer(0..1_000),
            stream_window_bytes <- integer(0..4_096),
            horizon_bytes <- integer(0..4_096),
            generated_bytes <- integer(0..4_096),
            unchanged <- boolean()
          ) do
      assert :wardwright@stream_core.action_tag(action, match_scope) ==
               StreamCoreReference.action_tag(action, match_scope)

      assert :wardwright@stream_core.terminal_status(action) ==
               StreamCoreReference.terminal_status(action)

      assert :wardwright@stream_core.latency_exceeded(observed_ms, max_hold_ms) ==
               StreamCoreReference.latency_exceeded?(observed_ms, max_hold_ms)

      assert :wardwright@stream_core.release_budget(stream_window_bytes, horizon_bytes) ==
               StreamCoreReference.release_budget(stream_window_bytes, horizon_bytes)

      assert :wardwright@stream_core.rewritten_bytes(generated_bytes, unchanged) ==
               StreamCoreReference.rewritten_bytes(generated_bytes, unchanged)
    end
  end

  property "structured core matches the Elixir reference for valid guard-loop inputs" do
    check all(
            guard_count <- integer(-4..12),
            guard_type <-
              member_of(["json_syntax", "schema_validation", "semantic_validation", "unknown"]),
            schema_rule_id <- rule_id(),
            semantic_rule_id <- rule_id(),
            rule_failures <- integer(0..8),
            max_failures_per_rule <- integer(0..8),
            attempt_count <- integer(0..8),
            max_attempts <- integer(0..8)
          ) do
      assert :wardwright@structured_core.guard_action() ==
               StructuredCoreReference.guard_action()

      assert :wardwright@structured_core.success_status(guard_count) ==
               StructuredCoreReference.success_status(guard_count)

      assert :wardwright@structured_core.guard_rule_id_for_string(
               guard_type,
               schema_rule_id,
               semantic_rule_id
             ) ==
               StructuredCoreReference.guard_rule_id_for_string(
                 guard_type,
                 schema_rule_id,
                 semantic_rule_id
               )

      assert :wardwright@structured_core.loop_outcome_status(
               schema_rule_id,
               rule_failures,
               max_failures_per_rule,
               attempt_count,
               max_attempts
             ) ==
               StructuredCoreReference.loop_outcome_status(
                 schema_rule_id,
                 rule_failures,
                 max_failures_per_rule,
                 attempt_count,
                 max_attempts
               )
    end
  end

  property "structured validation core matches the Elixir reference for valid validation facts" do
    check all(
            required_ok <- boolean(),
            additional_properties_ok <- boolean(),
            properties_ok <- boolean(),
            is_string <- boolean(),
            string_length <- integer(0..80),
            min_length <- integer(0..80),
            enum_ok <- boolean(),
            is_number <- boolean(),
            gte_ok <- boolean(),
            lte_ok <- boolean(),
            is_list <- boolean(),
            all_strings <- boolean(),
            bounds_ok <- boolean(),
            contains_pattern <- boolean()
          ) do
      assert :wardwright@structured_validation_core.object_schema_valid(
               required_ok,
               additional_properties_ok,
               properties_ok
             ) ==
               StructuredValidationCoreReference.object_schema_valid?(
                 required_ok,
                 additional_properties_ok,
                 properties_ok
               )

      assert :wardwright@structured_validation_core.string_property_valid(
               is_string,
               string_length,
               min_length,
               enum_ok
             ) ==
               StructuredValidationCoreReference.string_property_valid?(
                 is_string,
                 string_length,
                 min_length,
                 enum_ok
               )

      assert :wardwright@structured_validation_core.number_property_valid(
               is_number,
               gte_ok,
               lte_ok
             ) ==
               StructuredValidationCoreReference.number_property_valid?(is_number, gte_ok, lte_ok)

      assert :wardwright@structured_validation_core.string_array_property_valid(
               is_list,
               all_strings
             ) ==
               StructuredValidationCoreReference.string_array_property_valid?(
                 is_list,
                 all_strings
               )

      assert :wardwright@structured_validation_core.semantic_number_rule_valid(
               is_number,
               bounds_ok
             ) ==
               StructuredValidationCoreReference.semantic_number_rule_valid?(is_number, bounds_ok)

      assert :wardwright@structured_validation_core.semantic_string_not_contains_valid(
               is_string,
               contains_pattern
             ) ==
               StructuredValidationCoreReference.semantic_string_not_contains_valid?(
                 is_string,
                 contains_pattern
               )
    end
  end

  property "tool context core matches the Elixir reference for valid tool facts" do
    check all(
            has_primary_tool <- boolean(),
            has_available_tools <- boolean(),
            has_tool_result <- boolean(),
            has_chosen_tool <- boolean(),
            has_assistant_tool <- boolean(),
            available_tool_count <- integer(0..8),
            has_explicit_namespace <- boolean(),
            tool_type <- member_of(["function", "web_search", "custom"]),
            expected <- list_of(tool_name(), max_length: 6),
            actual <- tool_name()
          ) do
      assert :wardwright@tool_context_core.inferred_phase(
               has_primary_tool,
               has_available_tools,
               has_tool_result
             ) ==
               ToolContextCoreReference.inferred_phase(
                 has_primary_tool,
                 has_available_tools,
                 has_tool_result
               )

      assert :wardwright@tool_context_core.inferred_confidence(
               has_chosen_tool,
               has_assistant_tool,
               available_tool_count,
               has_tool_result
             ) ==
               ToolContextCoreReference.inferred_confidence(
                 has_chosen_tool,
                 has_assistant_tool,
                 available_tool_count,
                 has_tool_result
               )

      assert :wardwright@tool_context_core.result_status(has_tool_result) ==
               ToolContextCoreReference.result_status(has_tool_result)

      assert :wardwright@tool_context_core.default_namespace(
               has_explicit_namespace,
               tool_type
             ) ==
               ToolContextCoreReference.default_namespace(has_explicit_namespace, tool_type)

      assert :wardwright@tool_context_core.list_matches(expected, actual) ==
               ToolContextCoreReference.list_matches?(expected, actual)
    end
  end

  defp policy_action do
    member_of([
      "restrict_routes",
      "switch_model",
      "reroute",
      "inject_reminder_and_retry",
      "transform",
      "escalate",
      "alert_async",
      "block",
      "annotate",
      "custom_action"
    ])
  end

  defp policy_kind do
    member_of([
      "history_threshold",
      "history_regex_threshold",
      "route_gate",
      "request_guard",
      "custom"
    ])
  end

  defp stream_action do
    member_of([
      "rewrite",
      "rewrite_chunk",
      "drop_chunk",
      "block",
      "block_final",
      "retry",
      "retry_with_reminder",
      "pass",
      "annotate"
    ])
  end

  defp scope, do: member_of(["", "session_id", "run_id", "workspace", "model"])

  defp state, do: member_of(["", "active", "observing", "review_required", "recording"])

  defp rule_id do
    member_of(["answer-json", "minimum-confidence", "tool-loop", "route-local"])
  end

  defp selector_id do
    member_of(["", "dispatcher.default", "cascade.safe", "alloy.consensus"])
  end

  defp tool_name do
    member_of(["", "shell.exec", "create_ticket", "web.search", "openai.function"])
  end

  defp alert_status do
    member_of([:enqueued, :retrying, :dead_lettered, :dropped, :blocked, :delivered, :failed])
  end

  defp alert_event do
    fixed_map(%{
      idempotency_key: member_of(["alert-a", "alert-b", "same-alert"]),
      rule_id: member_of(["rule-a", "rule-b"]),
      session_id: member_of(["session-a", "session-b"])
    })
  end

  defp route_target do
    fixed_map(%{
      context_window: integer(1..128),
      model: member_of(["tiny/model", "small/model", "medium/model", "large/model"]),
      weight: integer(1..8)
    })
  end

  defp gleam_target(%{context_window: context_window, model: model, weight: weight}) do
    {:target, model, context_window, weight}
  end

  defp normalize_alert_decision({:enqueue_decision, key, status, queue_depth, queue_capacity}) do
    %{key: key, queue_capacity: queue_capacity, queue_depth: queue_depth, status: status}
  end

  defp normalize_route_selection(
         {:route_selection, selected_model, selected_context_window, selected_models, fallback_models, skipped,
          route_blocked, reason}
       ) do
    %{
      fallback_models: fallback_models,
      reason: reason,
      route_blocked: route_blocked,
      selected_context_window: selected_context_window,
      selected_model: selected_model,
      selected_models: selected_models,
      skipped: skipped
    }
  end
end
