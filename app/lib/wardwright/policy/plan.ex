defmodule Wardwright.Policy.Plan do
  @moduledoc """
  Request-policy evaluator boundary.

  The router should only collect request/caller context and serialize outcomes.
  This module owns the deterministic policy pass that turns configured governance
  rules into a transformed request, policy actions, route constraints, and trace
  events.
  """

  alias Wardwright.Policy.Action
  alias Wardwright.Policy.Engine
  alias Wardwright.Policy.History
  alias Wardwright.Policy.PlanCore
  alias Wardwright.PolicySandbox.DuneSnippetRegistry

  @action_key "action"
  @actions_key "actions"
  @after_key "after"
  @alert_count_key "alert_count"
  @before_key "before"
  @cache_scope_key "cache_scope"
  @created_at_key "created_at_unix_ms"
  @events_key "events"
  @id_key "id"
  @key_key "key"
  @kind_key "kind"
  @matched_key "matched"
  @message_key "message"
  @phase_key "phase"
  @policy_state_kind "policy_state"
  @primary_tool_key "primary_tool"
  @rule_id_key "rule_id"
  @scope_key "scope"
  @sequence_after_event_id_key "sequence_after_event_id"
  @sequence_after_key_key "sequence_after_key"
  @sequence_inspected_count_key "sequence_inspected_count"
  @sequence_key "sequence"
  @severity_key "severity"
  @state_key "state"
  @state_scope_key "state_scope"
  @state_transition_key "state_transition"
  @then_key "then"
  @tool_call_kind "tool_call"
  @tool_context_key "tool_context"
  @tool_key "tool"
  @tool_sequence_kind "tool_sequence"
  @transition_to_key "transition_to"
  @until_key "until"
  @value_key "value"
  @within_key "within"
  @type_key "type"
  @idempotency_key "idempotency_key"
  @route_constraints_key "route_constraints"
  @blocked_key "blocked"
  @active_state "active"
  @alert_async_action "alert_async"
  @annotate_action "annotate"
  @block_action "block"
  @allow_fallback_key "allow_fallback"
  @allowed_targets_key "allowed_targets"
  @default_cache_scope "session_id"
  @default_info_severity "info"
  @default_tool_sequence_id "tool-sequence"
  @dune_engine "dune"
  @engine_key "engine"
  @escalate_action "escalate"
  @events_window_key "events"
  @match_key "match"
  @milliseconds_window_key "milliseconds"
  @ms_window_key "ms"
  @policy_engine_kind "policy_engine"
  @request_policy_message "request policy matched"
  @request_rule_kinds ["request_guard", "request_transform", "receipt_annotation", "route_gate"]
  @request_rule_snippet "primitive.request-rule-action"
  @request_text_key "request_text"
  @restrict_routes_action "restrict_routes"
  @reroute_action "reroute"
  @reminder_key "reminder"
  @rule_key "rule"
  @schema_key "schema"
  @source_key "source"
  @switch_model_action "switch_model"
  @target_model_key "target_model"
  @tool_context_schema "wardwright.tool_context.v1"
  @turns_window_key "turns"

  def evaluate_request(request, caller, config \\ Wardwright.current_config(), opts \\ []) do
    text = request |> Map.get("messages", []) |> request_text() |> String.downcase()
    tool_context = Wardwright.ToolContext.normalize(request, opts)

    config
    |> Map.get("governance", [])
    |> Enum.reduce({request, empty_policy(tool_context)}, fn rule, {request, policy} ->
      apply_rule(rule, text, caller, request, policy, opts)
    end)
    |> then(fn {request, policy} ->
      policy =
        policy
        |> Map.update!("actions", &Enum.reverse/1)
        |> Map.update!("events", &Enum.reverse/1)
        |> Map.update!("tool_policy_selectors", &Enum.reverse/1)
        |> then(fn policy ->
          Map.put(policy, "conflicts", Action.conflicts(policy["actions"]))
        end)

      {request, policy}
    end)
  end

  def empty_policy, do: empty_policy(nil)

  def empty_policy(tool_context),
    do: %{
      "actions" => [],
      "alert_count" => 0,
      "blocked" => false,
      "conflicts" => [],
      "events" => [],
      "route_constraints" => %{},
      "tool_context" => tool_context,
      "tool_policy_selectors" => []
    }

  defp apply_rule(rule, text, caller, request, policy, opts) do
    kind = Map.get(rule, "kind", "")

    cond do
      not state_scope_matches?(rule, caller) ->
        {request, policy}

      Map.has_key?(rule, "engine") ->
        apply_engine_governance_rule(rule, caller, request, policy)

      kind == "history_threshold" ->
        apply_history_threshold_rule(rule, caller, request, policy)

      kind == "history_regex_threshold" ->
        apply_history_regex_threshold_rule(rule, caller, request, policy)

      kind == "tool_selector" ->
        apply_tool_selector_rule(rule, request, policy, opts)

      kind == "tool_loop_threshold" ->
        apply_tool_loop_threshold_rule(rule, caller, request, policy, opts)

      kind == "tool_sequence" ->
        apply_tool_sequence_rule(rule, caller, request, policy, opts)

      kind in @request_rule_kinds ->
        apply_dune_primitive_governance_rule(rule, text, request, policy)

      true ->
        {request, policy}
    end
  end

  defp apply_primitive_governance_rule(rule, kind, request, policy) do
    action = Map.get(rule, "action", "annotate")
    rule_id = Map.get(rule, "id", "policy")

    message =
      rule |> Map.get("message", "request policy matched") |> blank_to_nil() ||
        "request policy matched"

    severity = rule |> Map.get("severity", "info") |> blank_to_nil() || "info"

    action_record =
      %{
        "action" => action,
        "kind" => kind,
        "matched" => true,
        "message" => message,
        "rule_id" => rule_id,
        "severity" => severity
      }
      |> put_route_action_fields(rule)
      |> Action.normalize(rule: rule)

    apply_policy_action_effect(action_record, rule, request, policy)
  end

  defp apply_dune_primitive_governance_rule(rule, text, request, policy) do
    engine_rule =
      rule
      |> Map.merge(%{
        @engine_key => @dune_engine,
        @source_key => DuneSnippetRegistry.source!(@request_rule_snippet)
      })

    context = %{
      @request_text_key => text,
      @rule_key => rule
    }

    result = Engine.evaluate(engine_rule, context)

    action_records =
      result
      |> engine_actions(rule)
      |> Enum.map(&put_route_action_fields/1)

    Enum.reduce(action_records, {request, policy}, fn action_record, {request, policy_acc} ->
      apply_policy_action_effect(action_record, rule, request, policy_acc)
    end)
  end

  defp apply_policy_action_effect(action_record, rule, request, policy) do
    action = Map.get(action_record, @action_key, @annotate_action)
    rule_id = Map.get(action_record, @rule_id_key, Map.get(rule, @id_key, "policy"))

    message =
      action_record
      |> Map.get(@message_key, Map.get(rule, @message_key, @request_policy_message))
      |> blank_to_nil() || @request_policy_message

    severity =
      action_record
      |> Map.get(@severity_key, Map.get(rule, @severity_key, @default_info_severity))
      |> blank_to_nil() || @default_info_severity

    case action do
      action when action in ["escalate", "alert_async"] ->
        event = %{
          "idempotency_key" => Map.get(action_record, @idempotency_key, Map.get(rule, @idempotency_key)),
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "type" => "policy.alert"
        }

        {request,
         policy
         |> Map.update!("actions", &[action_record | &1])
         |> Map.update!("events", &[event | &1])
         |> Map.update!("alert_count", &(&1 + 1))}

      action when action in ["inject_reminder_and_retry", "transform"] ->
        reminder =
          action_record
          |> Map.get(@reminder_key, Map.get(rule, @reminder_key, message))
          |> blank_to_nil() || message

        message_record = %{
          "content" => reminder,
          "name" => "wardwright_policy_reminder",
          "role" => "system"
        }

        request =
          Map.update(request, "messages", [message_record], fn messages ->
            messages ++ [message_record]
          end)

        action_record = Map.put(action_record, "reminder_injected", true)
        {request, Map.update!(policy, "actions", &[action_record | &1])}

      "annotate" ->
        event = %{
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "type" => "policy.annotated"
        }

        {request,
         policy
         |> Map.update!("actions", &[action_record | &1])
         |> Map.update!("events", &[event | &1])}

      action when action in ["restrict_routes", "switch_model", "reroute"] ->
        apply_route_action(request, policy, action_record)

      "block" ->
        apply_block_action(request, policy, action_record)

      _ ->
        {request, Map.update!(policy, "actions", &[action_record | &1])}
    end
  end

  defp apply_engine_governance_rule(rule, caller, request, policy) do
    context = %{
      "caller" => caller,
      "estimated_prompt_tokens" => Wardwright.estimate_prompt_tokens(Map.get(request, "messages", [])),
      "request" => request,
      "request_text" => request |> Map.get("messages", []) |> request_text()
    }

    result = Engine.evaluate(rule, context)

    action_records =
      result
      |> engine_actions(rule)
      |> Enum.map(&put_route_action_fields/1)

    Enum.reduce(action_records, {request, policy}, fn action_record, {request, policy_acc} ->
      apply_policy_action_effect(action_record, rule, request, policy_acc)
    end)
  end

  defp engine_actions(%{"actions" => actions}, rule) when is_list(actions) do
    Enum.map(actions, &engine_action_record(&1, rule))
  end

  defp engine_actions(%{"action" => action} = result, rule) when is_binary(action) do
    [engine_action_record(result, rule)]
  end

  defp engine_actions(_result, _rule), do: []

  defp engine_action_record(action, rule) when is_map(action) do
    value = Map.get(action, "value", %{})
    value = if is_map(value), do: value, else: %{}

    %{
      @action_key => Map.get(action, @action_key, @annotate_action),
      @allow_fallback_key => Map.get(action, @allow_fallback_key, Map.get(value, @allow_fallback_key)),
      @allowed_targets_key => Map.get(action, @allowed_targets_key, Map.get(value, @allowed_targets_key)),
      @idempotency_key => Map.get(action, @idempotency_key, Map.get(value, @idempotency_key)),
      @kind_key => Map.get(rule, @kind_key, @policy_engine_kind),
      @match_key => Map.get(action, @match_key, Map.get(value, @match_key)),
      @matched_key => Map.get(action, @matched_key, true),
      @message_key =>
        Map.get(action, @message_key, Map.get(action, "reason", Map.get(value, "reason", "policy engine matched"))),
      @reminder_key => Map.get(action, @reminder_key, Map.get(value, @reminder_key)),
      @rule_id_key => Map.get(action, @rule_id_key, Map.get(rule, @id_key, "policy-engine")),
      @severity_key => Map.get(action, @severity_key, @default_info_severity),
      @source_key => Map.get(action, @source_key),
      @target_model_key =>
        Map.get(
          action,
          @target_model_key,
          Map.get(action, "model", Map.get(value, "target_model", Map.get(value, "model")))
        )
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
    |> Action.normalize(rule: rule)
  end

  defp engine_action_record(_action, rule) do
    %{
      "action" => "annotate",
      "kind" => Map.get(rule, "kind", "policy_engine"),
      "matched" => true,
      "message" => "policy engine returned a non-map action",
      "rule_id" => Map.get(rule, "id", "policy-engine"),
      "severity" => "warning"
    }
    |> Action.normalize(rule: rule)
  end

  defp apply_route_action(request, policy, action_record) do
    route_constraints =
      policy
      |> Map.get("route_constraints", %{})
      |> merge_route_constraints(action_record)

    policy =
      policy
      |> Map.put("route_constraints", route_constraints)
      |> Map.update!("actions", &[action_record | &1])

    {request, policy}
  end

  defp merge_route_constraints(route_constraints, %{"action" => "restrict_routes"} = action) do
    allowed_targets = normalize_string_list(Map.get(action, "allowed_targets"))

    if allowed_targets == [] do
      route_constraints
    else
      Map.update(route_constraints, "allowed_targets", allowed_targets, fn existing ->
        existing
        |> normalize_string_list()
        |> Enum.filter(&(&1 in allowed_targets))
      end)
    end
  end

  defp merge_route_constraints(route_constraints, %{"action" => action} = record)
       when action in ["switch_model", "reroute"] do
    target_model = record |> Map.get("target_model", Map.get(record, "model")) |> blank_to_nil()

    if target_model do
      route_constraints
      |> Map.put("forced_model", target_model)
      |> maybe_put_allow_fallback(record)
    else
      route_constraints
    end
  end

  defp merge_route_constraints(route_constraints, _action), do: route_constraints

  defp apply_block_action(request, policy, action_record) do
    policy =
      policy
      |> Map.put("blocked", true)
      |> Map.update!("actions", &[action_record | &1])

    {request, policy}
  end

  defp put_route_action_fields(action_record, rule) do
    action_record
    |> maybe_put_string_list("allowed_targets", Map.get(rule, "allowed_targets"))
    |> maybe_put_string("target_model", Map.get(rule, "target_model", Map.get(rule, "model")))
    |> maybe_put_boolean("allow_fallback", Map.get(rule, "allow_fallback"))
  end

  defp put_route_action_fields(action_record), do: put_route_action_fields(action_record, action_record)

  defp maybe_put_string_list(map, key, value) do
    value = normalize_string_list(value)
    if value == [], do: map, else: Map.put(map, key, value)
  end

  defp maybe_put_string(map, key, value) do
    case blank_to_nil(value) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end

  defp maybe_put_boolean(map, key, value) when value in [true, false], do: Map.put(map, key, value)

  defp maybe_put_boolean(map, _key, _value), do: map

  defp maybe_put_allow_fallback(route_constraints, %{"allow_fallback" => true}),
    do: Map.put(route_constraints, "allow_fallback", true)

  defp maybe_put_allow_fallback(route_constraints, _record), do: route_constraints

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_values), do: []

  defp apply_history_threshold_rule(rule, caller, request, policy) do
    threshold = PlanCore.threshold(integer_value(Map.get(rule, "threshold", 1)) || 1)

    filter = %{
      "key" => blank_to_nil(Map.get(rule, "cache_key")),
      "kind" => blank_to_nil(Map.get(rule, "cache_kind")),
      "scope" => cache_scope_from_caller(caller, Map.get(rule, "cache_scope", ""))
    }

    count = Wardwright.PolicyCache.count(filter)

    if PlanCore.threshold_triggered?(count, threshold) do
      action = Map.get(rule, "action", "annotate")
      rule_id = Map.get(rule, "id", "policy")

      message =
        rule |> Map.get("message", "policy cache threshold matched") |> blank_to_nil() ||
          "policy cache threshold matched"

      severity = rule |> Map.get("severity", "info") |> blank_to_nil() || "info"

      action_record =
        %{
          "action" => action,
          "cache_key" => Map.get(rule, "cache_key", ""),
          "cache_kind" => Map.get(rule, "cache_kind", ""),
          "cache_scope" => Map.get(rule, "cache_scope", ""),
          "history_count" => count,
          "kind" => "history_threshold",
          "matched" => true,
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "threshold" => threshold
        }
        |> Action.normalize(rule: rule)

      policy = Map.update!(policy, "actions", &[action_record | &1])

      if action in ["escalate", "alert_async"] do
        event = %{
          "history_count" => count,
          "idempotency_key" => Map.get(rule, "idempotency_key"),
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "threshold" => threshold,
          "type" => "policy.alert"
        }

        {request,
         policy
         |> Map.update!("events", &[event | &1])
         |> Map.update!("alert_count", &(&1 + 1))}
      else
        {request, policy}
      end
    else
      {request, policy}
    end
  end

  defp apply_history_regex_threshold_rule(rule, caller, request, policy) do
    threshold = PlanCore.threshold(integer_value(Map.get(rule, "threshold", 1)) || 1)

    filter = %{
      "key" => blank_to_nil(Map.get(rule, "cache_key")),
      "kind" => blank_to_nil(Map.get(rule, "cache_kind")),
      "scope" => cache_scope_from_caller(caller, Map.get(rule, "cache_scope", ""))
    }

    count =
      filter
      |> History.regex_count(
        Map.get(rule, "pattern", ""),
        Map.get(rule, "limit")
      )

    if PlanCore.threshold_triggered?(count, threshold) do
      action = Map.get(rule, "action", "annotate")
      rule_id = Map.get(rule, "id", "policy")

      message =
        rule |> Map.get("message", "history regex threshold matched") |> blank_to_nil() ||
          "history regex threshold matched"

      severity = rule |> Map.get("severity", "info") |> blank_to_nil() || "info"

      action_record =
        %{
          "action" => action,
          "cache_key" => Map.get(rule, "cache_key", ""),
          "cache_kind" => Map.get(rule, "cache_kind", ""),
          "cache_scope" => Map.get(rule, "cache_scope", ""),
          "history_count" => count,
          "kind" => "history_regex_threshold",
          "matched" => true,
          "message" => message,
          "pattern" => Map.get(rule, "pattern", ""),
          "rule_id" => rule_id,
          "severity" => severity,
          "threshold" => threshold
        }
        |> Action.normalize(rule: rule)

      policy = Map.update!(policy, "actions", &[action_record | &1])

      if action in ["escalate", "alert_async"] do
        event = %{
          "history_count" => count,
          "idempotency_key" => Map.get(rule, "idempotency_key"),
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "threshold" => threshold,
          "type" => "policy.alert"
        }

        {request,
         policy
         |> Map.update!("events", &[event | &1])
         |> Map.update!("alert_count", &(&1 + 1))}
      else
        {request, policy}
      end
    else
      {request, policy}
    end
  end

  defp apply_tool_selector_rule(rule, request, policy, opts) do
    tool_context = request_tool_context(request, policy, opts)

    if Wardwright.ToolContext.matches?(tool_context, Map.get(rule, "tool", %{})) do
      policy = record_tool_selector(policy, rule, true)
      apply_primitive_governance_rule(rule, "tool_selector", request, policy)
    else
      {request, record_tool_selector(policy, rule, false)}
    end
  end

  defp apply_tool_loop_threshold_rule(rule, caller, request, policy, opts) do
    tool_context = request_tool_context(request, policy, opts)
    threshold = PlanCore.threshold(integer_value(Map.get(rule, "threshold", 1)) || 1)
    tool_matcher = Map.get(rule, "tool", %{})

    cache_key =
      Map.get(rule, "cache_key") |> blank_to_nil() ||
        Wardwright.ToolContext.cache_key(tool_context)

    cache_kind = Map.get(rule, "cache_kind") |> blank_to_nil() || "tool_call"
    cache_scope = Map.get(rule, "cache_scope", "session_id")

    filter = %{
      "key" => cache_key,
      "kind" => cache_kind,
      "scope" => cache_scope_from_caller(caller, cache_scope)
    }

    count = if cache_key, do: Wardwright.PolicyCache.count(filter), else: 0

    if cache_key == nil or
         not Wardwright.ToolContext.matches?(tool_context, tool_matcher) or
         not PlanCore.threshold_triggered?(count, threshold) do
      {request, policy}
    else
      action = Map.get(rule, "action", "annotate")
      rule_id = Map.get(rule, "id", "tool-loop-threshold")

      message =
        rule |> Map.get("message", "tool policy threshold matched") |> blank_to_nil() ||
          "tool policy threshold matched"

      severity = rule |> Map.get("severity", "info") |> blank_to_nil() || "info"

      action_record =
        %{
          "action" => action,
          "cache_key" => cache_key,
          "cache_kind" => cache_kind,
          "cache_scope" => cache_scope,
          "history_count" => count,
          "kind" => "tool_loop_threshold",
          "matched" => true,
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "threshold" => threshold,
          "tool_context" => tool_context
        }
        |> put_route_action_fields(rule)
        |> Action.normalize(rule: rule)

      policy =
        policy
        |> Map.update!("actions", &[action_record | &1])
        |> put_tool_policy_status(action, rule_id, count, threshold, cache_key, cache_scope)
        |> apply_tool_loop_action_policy(action, action_record)

      if action in ["escalate", "alert_async"] do
        event = %{
          "history_count" => count,
          "idempotency_key" => Map.get(rule, "idempotency_key"),
          "message" => message,
          "rule_id" => rule_id,
          "severity" => severity,
          "threshold" => threshold,
          "tool_context" => tool_context,
          "type" => "policy.alert"
        }

        {request,
         policy
         |> Map.update!("events", &[event | &1])
         |> Map.update!("alert_count", &(&1 + 1))}
      else
        {request, policy}
      end
    end
  end

  defp apply_tool_loop_action_policy(policy, action, action_record)
       when action in ["restrict_routes", "switch_model", "reroute"] do
    route_constraints = merge_route_constraints(policy["route_constraints"], action_record)
    Map.put(policy, "route_constraints", route_constraints)
  end

  defp apply_tool_loop_action_policy(policy, "block", _action_record), do: Map.put(policy, "blocked", true)

  defp apply_tool_loop_action_policy(policy, _action, _action_record), do: policy

  defp apply_tool_sequence_rule(rule, caller, request, policy, opts) do
    tool_context = request_tool_context(request, policy, opts)

    cond do
      transition_to = blank_to_nil(Map.get(rule, @transition_to_key)) ->
        apply_tool_sequence_transition(rule, caller, request, policy, tool_context, transition_to)

      then_rule = Map.get(rule, @then_key) ->
        apply_tool_sequence_then_rule(rule, caller, request, policy, tool_context, then_rule)

      true ->
        {request, policy}
    end
  end

  defp apply_tool_sequence_transition(rule, caller, request, policy, tool_context, transition_to) do
    after_matcher = rule |> Map.get(@after_key, %{}) |> Map.get(@tool_key, %{})

    if Wardwright.ToolContext.matches?(tool_context, after_matcher) do
      cache_scope = Map.get(rule, @cache_scope_key, @default_cache_scope)
      :ok = record_policy_state(caller, cache_scope, transition_to, rule, tool_context)

      rule_id = Map.get(rule, @id_key, @default_tool_sequence_id)

      action_record =
        %{
          @action_key => @state_transition_key,
          @cache_scope_key => cache_scope,
          @kind_key => @tool_sequence_kind,
          @matched_key => true,
          @message_key =>
            rule |> Map.get(@message_key, "tool sequence state transition matched") |> blank_to_nil() ||
              "tool sequence state transition matched",
          @rule_id_key => rule_id,
          @severity_key =>
            rule |> Map.get(@severity_key, @default_info_severity) |> blank_to_nil() || @default_info_severity,
          @state_transition_key => transition_to,
          @tool_context_key => tool_context
        }
        |> Action.normalize(rule: rule)

      event = %{
        @rule_id_key => rule_id,
        @state_key => transition_to,
        @tool_context_key => tool_context,
        @type_key => "policy.state_transition"
      }

      {request,
       policy
       |> Map.update!(@actions_key, &[action_record | &1])
       |> Map.update!(@events_key, &[event | &1])}
    else
      {request, policy}
    end
  end

  defp apply_tool_sequence_then_rule(rule, caller, request, policy, tool_context, then_rule) when is_map(then_rule) do
    current_matcher =
      Map.get(
        then_rule,
        @tool_key,
        Map.get(rule, @tool_key, get_in(rule, [@before_key, @tool_key]) || %{})
      )

    after_matcher = rule |> Map.get(@after_key, %{}) |> Map.get(@tool_key, %{})

    with true <- Wardwright.ToolContext.matches?(tool_context, current_matcher),
         {:ok, prior_event, inspected_count} <- sequence_prior_event(rule, caller, after_matcher),
         false <- sequence_reset_after?(rule, caller, prior_event) do
      action = Map.get(then_rule, @action_key, Map.get(rule, @action_key, @annotate_action))
      rule_id = Map.get(rule, @id_key, @default_tool_sequence_id)

      action_record =
        %{
          @action_key => action,
          @cache_scope_key => Map.get(rule, @cache_scope_key, @default_cache_scope),
          @kind_key => @tool_sequence_kind,
          @matched_key => true,
          @message_key =>
            then_rule |> Map.get(@message_key, Map.get(rule, @message_key, "tool sequence matched")) |> blank_to_nil() ||
              "tool sequence matched",
          @rule_id_key => rule_id,
          @sequence_after_event_id_key => Map.get(prior_event, @id_key),
          @sequence_after_key_key => Map.get(prior_event, @key_key),
          @sequence_inspected_count_key => inspected_count,
          @severity_key =>
            then_rule |> Map.get(@severity_key, Map.get(rule, @severity_key, @default_info_severity)) |> blank_to_nil() ||
              @default_info_severity,
          @tool_context_key => tool_context
        }
        |> put_route_action_fields(Map.merge(rule, then_rule))
        |> Action.normalize(rule: rule)

      policy =
        policy
        |> Map.update!(@actions_key, &[action_record | &1])
        |> apply_tool_sequence_action_policy(action, action_record)

      if action in [@escalate_action, @alert_async_action] do
        event = %{
          @idempotency_key => Map.get(rule, @idempotency_key),
          @message_key => action_record[@message_key],
          @rule_id_key => rule_id,
          @severity_key => action_record[@severity_key],
          @tool_context_key => tool_context,
          @type_key => "policy.alert"
        }

        {request,
         policy
         |> Map.update!(@events_key, &[event | &1])
         |> Map.update!(@alert_count_key, &(&1 + 1))}
      else
        {request, policy}
      end
    else
      _ -> {request, policy}
    end
  end

  defp apply_tool_sequence_then_rule(_rule, _caller, request, policy, _tool_context, _then_rule), do: {request, policy}

  defp apply_tool_sequence_action_policy(policy, action, action_record)
       when action in [@restrict_routes_action, @switch_model_action, @reroute_action] do
    route_constraints = merge_route_constraints(policy[@route_constraints_key], action_record)
    Map.put(policy, @route_constraints_key, route_constraints)
  end

  defp apply_tool_sequence_action_policy(policy, @block_action, _action_record), do: Map.put(policy, @blocked_key, true)

  defp apply_tool_sequence_action_policy(policy, _action, _action_record), do: policy

  defp sequence_prior_event(rule, caller, after_matcher) do
    cache_scope = Map.get(rule, @cache_scope_key, @default_cache_scope)
    limit = sequence_window_limit(rule)

    events =
      Wardwright.PolicyCache.recent(
        %{
          @kind_key => @tool_call_kind,
          @scope_key => cache_scope_from_caller(caller, cache_scope)
        },
        limit
      )

    current_event = List.first(events)

    events
    |> Enum.drop(1)
    |> Enum.find(&tool_event_matches?(&1, after_matcher))
    |> case do
      nil -> nil
      event -> if within_wall_clock_window?(rule, current_event, event), do: event
    end
    |> case do
      nil -> :error
      event -> {:ok, event, length(events)}
    end
  end

  defp sequence_window_limit(rule) do
    within = Map.get(rule, @within_key, %{})

    PlanCore.sequence_window_limit(
      Map.get(within, @turns_window_key),
      Map.get(within, @events_window_key)
    )
  end

  defp within_wall_clock_window?(rule, current_event, prior_event) do
    within = Map.get(rule, @within_key, %{})

    max_ms =
      integer_value(Map.get(within, @milliseconds_window_key)) ||
        integer_value(Map.get(within, @ms_window_key))

    if max_ms do
      current_ms =
        case current_event do
          %{@created_at_key => created_at} when is_integer(created_at) -> created_at
          _ -> System.system_time(:millisecond)
        end

      PlanCore.within_wall_clock_window?(
        max_ms,
        current_ms,
        Map.get(prior_event, @created_at_key, 0)
      )
    else
      true
    end
  end

  defp sequence_reset_after?(rule, caller, prior_event) do
    until_rule = Map.get(rule, @until_key, %{})

    cond do
      not is_map(until_rule) or map_size(until_rule) == 0 ->
        false

      state = blank_to_nil(Map.get(until_rule, @state_key)) ->
        state_event_after?(rule, caller, state, prior_event)

      tool_matcher = Map.get(until_rule, @tool_key) ->
        tool_event_after?(rule, caller, tool_matcher, prior_event)

      true ->
        false
    end
  end

  defp state_scope_matches?(rule, caller) do
    case blank_to_nil(Map.get(rule, @state_scope_key)) do
      nil ->
        true

      @active_state ->
        PlanCore.state_scope_matches?(
          @active_state,
          current_policy_state(caller, Map.get(rule, @cache_scope_key, @default_cache_scope))
        )

      state ->
        PlanCore.state_scope_matches?(
          state,
          current_policy_state(caller, Map.get(rule, @cache_scope_key, @default_cache_scope))
        )
    end
  end

  defp current_policy_state(caller, cache_scope) do
    Wardwright.PolicyCache.recent(
      %{
        @kind_key => @policy_state_kind,
        @scope_key => cache_scope_from_caller(caller, cache_scope)
      },
      1
    )
    |> case do
      [%{@key_key => state} | _] when is_binary(state) and state != "" -> state
      _ -> @active_state
    end
  end

  defp record_policy_state(caller, cache_scope, state, rule, tool_context) do
    case Wardwright.PolicyCache.add(%{
           @created_at_key => System.system_time(:millisecond),
           @key_key => state,
           @kind_key => @policy_state_kind,
           @scope_key => cache_scope_from_caller(caller, cache_scope),
           @value_key =>
             %{@rule_id_key => Map.get(rule, @id_key, @default_tool_sequence_id), @tool_context_key => tool_context}
             |> reject_blank()
         }) do
      {:ok, _event} -> :ok
      {:error, _message} -> :ok
    end
  end

  defp tool_event_after?(rule, caller, tool_matcher, prior_event) when is_map(tool_matcher) do
    rule
    |> scoped_recent_after(caller, @tool_call_kind, prior_event)
    |> Enum.any?(&tool_event_matches?(&1, tool_matcher))
  end

  defp tool_event_after?(_rule, _caller, _tool_matcher, _prior_event), do: false

  defp state_event_after?(rule, caller, state, prior_event) do
    rule
    |> scoped_recent_after(caller, @policy_state_kind, prior_event)
    |> Enum.any?(&(Map.get(&1, @key_key) == state))
  end

  defp scoped_recent_after(rule, caller, kind, prior_event) do
    Wardwright.PolicyCache.recent(
      %{
        @kind_key => kind,
        @scope_key => cache_scope_from_caller(caller, Map.get(rule, @cache_scope_key, @default_cache_scope))
      },
      sequence_window_limit(rule)
    )
    |> Enum.filter(fn event ->
      PlanCore.event_after?(
        Map.get(event, @created_at_key, 0),
        Map.get(event, @sequence_key, 0),
        Map.get(prior_event, @created_at_key, 0),
        Map.get(prior_event, @sequence_key, 0)
      )
    end)
  end

  defp tool_event_matches?(%{@value_key => %{@phase_key => phase, @primary_tool_key => primary_tool}}, matcher)
       when is_map(primary_tool) and is_map(matcher) do
    tool_context =
      %{
        @phase_key => phase,
        @primary_tool_key => primary_tool,
        @schema_key => @tool_context_schema
      }
      |> reject_blank()

    Wardwright.ToolContext.matches?(tool_context, matcher)
  end

  defp tool_event_matches?(_event, _matcher), do: false

  defp record_tool_selector(policy, rule, matched) do
    selector =
      %{
        "action" => Map.get(rule, "action", "annotate"),
        "allow_fallback" => Map.get(rule, "allow_fallback"),
        "allowed_targets" => normalize_string_list(Map.get(rule, "allowed_targets")),
        "attached_policy_bundle" => Map.get(rule, "attach_policy_bundle"),
        "id" => Map.get(rule, "id", "tool-selector"),
        "matched" => matched,
        "target_model" => blank_to_nil(Map.get(rule, "target_model", Map.get(rule, "model"))),
        "tool" => Map.get(rule, "tool", %{})
      }
      |> reject_blank()

    Map.update!(policy, "tool_policy_selectors", &[selector | &1])
  end

  defp put_tool_policy_status(policy, action, rule_id, count, threshold, cache_key, cache_scope) do
    status = PlanCore.tool_policy_status(action)

    Map.put(policy, "tool_policy", %{
      "counter_key_hash" => content_hash(cache_key),
      "observed_count" => count,
      "rule_id" => rule_id,
      "state_scope" => PlanCore.scope_label(cache_scope),
      "status" => status,
      "threshold" => threshold
    })
  end

  defp request_text(messages) when is_list(messages) do
    Enum.map_join(messages, "\n", fn message ->
      "#{Map.get(message, "role", "")}\n#{metadata_string(Map.get(message, "content"))}"
    end)
  end

  defp request_text(_), do: ""

  defp request_tool_context(_request, %{"tool_context" => tool_context}, _opts) when is_map(tool_context),
    do: tool_context

  defp request_tool_context(request, _policy, opts), do: Wardwright.ToolContext.normalize(request, opts)

  defp cache_scope_from_caller(_caller, scope_name) when scope_name in [nil, ""], do: %{}

  defp cache_scope_from_caller(caller, scope_name) do
    scope_name = metadata_string(scope_name)

    case get_in(caller, [scope_name, "value"]) do
      nil -> %{}
      "" -> %{}
      value -> %{scope_name => value}
    end
  end

  defp metadata_string(value) when is_binary(value), do: String.trim(value)
  defp metadata_string(value) when is_integer(value), do: Integer.to_string(value)
  defp metadata_string(value) when is_float(value), do: Float.to_string(value)
  defp metadata_string(value) when is_boolean(value), do: to_string(value)
  defp metadata_string(_), do: ""

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: if(String.trim(value) != "", do: String.trim(value))

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer_value(_), do: nil

  defp content_hash(nil), do: nil

  defp content_hash(value), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, to_string(value)), case: :lower)

  defp reject_blank(map) when is_map(map) do
    map
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, ""} -> true
      {_key, []} -> true
      {_key, value} when is_map(value) and map_size(value) == 0 -> true
      {_key, _value} -> false
    end)
    |> Map.new()
  end
end
