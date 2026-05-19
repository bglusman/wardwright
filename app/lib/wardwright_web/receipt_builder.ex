defmodule WardwrightWeb.ReceiptBuilder do
  @moduledoc false

  @tool_context_key "tool_context"

  def build(status, model, caller, request, decision, called_provider, policy, config) do
    receipt_id = "rcpt_" <> random_hex(8)
    created_at = System.system_time(:second)

    %{
      "attempts" => [
        %{
          "called_provider" => called_provider,
          "mock" => true,
          "model" => decision.selected_model,
          "provider_id" => decision.selected_model |> String.split("/") |> List.first(),
          "status" => status
        }
      ],
      "caller" => caller,
      "created_at" => created_at,
      "decision" => %{
        "estimated_prompt_tokens" => decision.estimated_prompt_tokens,
        "fallback_models" => decision.fallback_models,
        "fallback_used" => decision.fallback_used,
        "governance" => config["governance"],
        "policy_actions" => policy["actions"],
        "policy_conflicts" => policy["conflicts"],
        "policy_route_constraints" => decision.policy_route_constraints,
        "reason" => decision.reason,
        "route_blocked" => decision.route_blocked,
        "route_id" => decision.route_id,
        "route_lineage" => Map.get(decision, :route_lineage, []),
        "route_type" => decision.route_type,
        "rule" => decision.rule,
        "selected_context_window" => decision.selected_context_window,
        "selected_model" => decision.selected_model,
        "selected_models" => decision.selected_models,
        "selected_provider" => decision.selected_provider,
        "skipped" => decision.skipped,
        "strategy" => decision.combine_strategy,
        "tool_policy_selectors" => policy["tool_policy_selectors"],
        @tool_context_key => policy["tool_context"] || Wardwright.ToolContext.normalize(request)
      },
      "events" => receipt_events(receipt_id, created_at, status, decision, called_provider),
      "final" => %{
        "alert_count" => policy["alert_count"],
        "alert_delivery" => Map.get(policy, "alert_delivery", []),
        "events" => policy["events"],
        "receipt_recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "selected_model" => decision.selected_model,
        "status" => status,
        "stream_trigger_count" => 0,
        "tool_policy" => policy["tool_policy"]
      },
      "model_id" => model,
      "model_version" => config["version"],
      "receipt_id" => receipt_id,
      "receipt_schema" => "v1",
      "request" => %{
        "estimated_prompt_tokens" => decision.estimated_prompt_tokens,
        "message_count" => length(Map.get(request, "messages", [])),
        "model" => Map.get(request, "model"),
        "normalized_model" => model,
        "prompt_transforms" => config["prompt_transforms"],
        "stream" => Map.get(request, "stream", false),
        "structured_output" => config["structured_output"],
        @tool_context_key => policy["tool_context"]
      },
      "run_id" => get_in(caller, ["run_id", "value"]),
      "simulation" => status == "simulated"
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def apply_provider_outcome(receipt, provider) do
    receipt
    |> update_in(["attempts", Access.at(0)], fn attempt ->
      attempt
      |> Map.put("status", provider.status)
      |> Map.put("mock", provider.mock)
      |> Map.put("called_provider", provider.called_provider)
      |> Map.put("latency_ms", provider.latency_ms)
      |> put_if_present("provider_id", provider_id_from_model(Map.get(provider, :selected_model)))
      |> put_if_present("model", Map.get(provider, :selected_model))
      |> put_if_present("provider_metadata", Map.get(provider, :provider_metadata))
      |> put_if_present("provider_error", provider.error)
    end)
    |> update_in(["final"], fn final ->
      final
      |> Map.put("status", provider.status)
      |> put_if_present("selected_model", Map.get(provider, :selected_model))
      |> put_if_present("structured_output", Map.get(provider, :structured_output))
      |> put_if_present("stream_policy", stream_policy_receipt(Map.get(provider, :stream_policy)))
      |> put_stream_policy_summary(Map.get(provider, :stream_policy))
      |> put_if_present("provider_metadata", Map.get(provider, :provider_metadata))
      |> put_if_present("provider_error", provider.error)
    end)
  end

  def chat_response(request, receipt, decision, provider_content) do
    completion_tokens = 18

    content =
      provider_content ||
        "Mock Wardwright response routed to #{decision.selected_model}. Estimated prompt tokens: #{decision.estimated_prompt_tokens}."

    %{
      "choices" => [
        %{"finish_reason" => "stop", "index" => 0, "message" => %{"content" => content, "role" => "assistant"}}
      ],
      "created" => System.system_time(:second),
      "id" => "chatcmpl_" <> receipt["receipt_id"],
      "model" => Map.get(request, "model"),
      "object" => "chat.completion",
      "usage" => %{
        "completion_tokens" => completion_tokens,
        "prompt_tokens" => decision.estimated_prompt_tokens,
        "total_tokens" => decision.estimated_prompt_tokens + completion_tokens
      },
      "wardwright" => %{
        "alert_delivery" => get_in(receipt, ["final", "alert_delivery"]),
        "provider_error" => get_in(receipt, ["final", "provider_error"]),
        "receipt_id" => receipt["receipt_id"],
        "selected_model" => decision.selected_model,
        "status" => get_in(receipt, ["final", "status"]),
        "stream_policy" => get_in(receipt, ["final", "stream_policy"]),
        "structured_output" => get_in(receipt, ["final", "structured_output"])
      }
    }
  end

  def response_status(receipt) do
    case get_in(receipt, ["final", "status"]) do
      status when status in ["completed", "completed_after_guard"] -> 200
      "policy_failed_closed" -> 429
      "provider_error" -> 502
      "exhausted_rule_budget" -> 422
      "exhausted_guard_budget" -> 422
      "stream_policy_blocked" -> 422
      "stream_policy_latency_exceeded" -> 422
      "stream_policy_retry_context_exceeded" -> 422
      "stream_policy_retry_skipped_after_release" -> 409
      "stream_policy_retry_required" -> 409
      _ -> 200
    end
  end

  def reject_blank(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  def integer_value(value) when is_integer(value), do: value

  def integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  def integer_value(_value), do: nil

  def put_if_present(map, _key, nil), do: map
  def put_if_present(map, key, value), do: Map.put(map, key, value)

  defp provider_id_from_model(model) when is_binary(model) do
    model |> String.split("/", parts: 2) |> List.first()
  end

  defp provider_id_from_model(_model), do: nil

  defp put_stream_policy_summary(final, nil), do: final

  defp put_stream_policy_summary(final, stream_policy) do
    final
    |> Map.put("stream_trigger_count", stream_policy.trigger_count)
    |> put_if_present("stream_policy_action", stream_policy.action)
    |> put_stream_route_transitions(stream_policy)
  end

  defp put_stream_route_transitions(final, stream_policy) do
    transitions =
      stream_policy
      |> Map.get(:events, [])
      |> Enum.filter(&(Map.get(&1, "type") == "attempt.retry_rerouted"))
      |> Enum.map(fn event ->
        %{
          "estimated_prompt_tokens" => Map.get(event, "estimated_prompt_tokens"),
          "fallback_used" => Map.get(event, "fallback_used"),
          "from_context_window" => Map.get(event, "from_context_window"),
          "from_model" => Map.get(event, "from_selected_model"),
          "phase" => "stream_retry",
          "reason" => Map.get(event, "reason"),
          "route_type" => Map.get(event, "route_type"),
          "to_context_window" => Map.get(event, "context_window"),
          "to_model" => Map.get(event, "selected_model")
        }
        |> reject_blank()
      end)

    case transitions do
      [] -> final
      _ -> Map.put(final, "route_transitions", transitions)
    end
  end

  defp stream_policy_receipt(nil), do: nil

  defp stream_policy_receipt(stream_policy) do
    %{
      "action" => stream_policy.action,
      "attempts" => Map.get(stream_policy, :attempts, []),
      "blocked_bytes" => Map.get(stream_policy, :blocked_bytes, 0),
      "events" => stream_policy.events,
      "generated_bytes" => Map.get(stream_policy, :generated_bytes, 0),
      "held_bytes" => Map.get(stream_policy, :held_bytes, 0),
      "max_held_bytes" => Map.get(stream_policy, :max_held_bytes, 0),
      "max_hold_ms" => Map.get(stream_policy, :max_hold_ms),
      "max_observed_hold_ms" => Map.get(stream_policy, :max_observed_hold_ms, 0),
      "max_retries" => Map.get(stream_policy, :max_retries, 0),
      "released_bytes" => Map.get(stream_policy, :released_bytes, 0),
      "released_to_consumer" => stream_policy.released_to_consumer,
      "retry_count" => Map.get(stream_policy, :retry_count, 0),
      "rewritten_bytes" => Map.get(stream_policy, :rewritten_bytes, 0),
      "status" => stream_policy.status,
      "trigger_count" => stream_policy.trigger_count
    }
  end

  def sink_usage(receipt) do
    %{
      "completion_tokens" => get_in(receipt, ["final", "provider_metadata", "usage", "completion_tokens"]) || 0,
      "estimated_prompt_tokens" => get_in(receipt, ["decision", "estimated_prompt_tokens"]) || 0,
      "prompt_tokens" => get_in(receipt, ["final", "provider_metadata", "usage", "prompt_tokens"]) || 0,
      "total_tokens" => get_in(receipt, ["final", "provider_metadata", "usage", "total_tokens"]) || 0
    }
  end

  defp receipt_events(receipt_id, created_at, status, decision, called_provider) do
    [
      %{
        "created_at" => created_at,
        "event_id" => receipt_id <> ":1",
        "receipt_id" => receipt_id,
        "selected_model" => decision.selected_model,
        "selected_provider" => decision.selected_provider,
        "sequence" => 1,
        "type" => "route.selected"
      },
      %{
        "called_provider" => called_provider,
        "created_at" => created_at,
        "event_id" => receipt_id <> ":2",
        "receipt_id" => receipt_id,
        "sequence" => 2,
        "type" => "provider.attempted"
      },
      %{
        "created_at" => created_at,
        "event_id" => receipt_id <> ":3",
        "receipt_id" => receipt_id,
        "sequence" => 3,
        "status" => status,
        "type" => "receipt.finalized"
      }
    ]
  end

  defp random_hex(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
