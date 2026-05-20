defmodule Wardwright.PolicyReplay do
  @moduledoc """
  Replays recorded policy and route decisions from receipt metadata.

  Replay v0 is intentionally metadata-only. It does not reconstruct provider
  requests, call providers, or expose prompt/completion content. It gives the
  control layer a deterministic foundation for reviewing what a stored receipt
  says Wardwright decided.
  """

  @schema "wardwright.policy_replay.v0"
  @vcr_schema "wardwright.policy_vcr.v0"
  @legacy_schema "wardwright.receipt_legacy.v1"
  @metadata_redaction "metadata_only"
  @legacy_replay_warning "receipt has no policy_vcr metadata; replay used legacy receipt fields"

  @actions_key "actions"
  @alert_count_key "alert_count"
  @conflicts_key "conflicts"
  @decision_key "decision"
  @estimated_prompt_tokens_key "estimated_prompt_tokens"
  @events_key "events"
  @fallback_models_key "fallback_models"
  @fallback_used_key "fallback_used"
  @final_key "final"
  @final_status_key "final_status"
  @content_key "content"
  @message_content_lengths_key "message_content_lengths"
  @message_count_key "message_count"
  @message_roles_key "message_roles"
  @messages_key "messages"
  @model_key "model"
  @model_id_key "model_id"
  @model_version_key "model_version"
  @mode_key "mode"
  @normalized_model_key "normalized_model"
  @original_status_key "original_status"
  @policy_key "policy"
  @policy_actions_key "policy_actions"
  @policy_conflicts_key "policy_conflicts"
  @policy_route_constraints_key "policy_route_constraints"
  @provider_called_key "provider_called"
  @reason_key "reason"
  @receipt_id_key "receipt_id"
  @redaction_key "redaction"
  @replayed_at_key "replayed_at"
  @request_key "request"
  @route_key "route"
  @route_blocked_key "route_blocked"
  @route_id_key "route_id"
  @route_lineage_key "route_lineage"
  @route_type_key "route_type"
  @rule_key "rule"
  @role_key "role"
  @schema_key "schema"
  @selected_context_window_key "selected_context_window"
  @selected_model_key "selected_model"
  @selected_models_key "selected_models"
  @selected_provider_key "selected_provider"
  @skipped_key "skipped"
  @source_receipt_id_key "source_receipt_id"
  @source_vcr_schema_key "source_vcr_schema"
  @status_key "status"
  @strategy_key "strategy"
  @stream_key "stream"
  @structured_output_configured_key "structured_output_configured"
  @text_key "text"
  @tool_context_key "tool_context"
  @vcr_key "vcr"
  @warnings_key "warnings"
  @would_call_provider_key "would_call_provider"

  def replay_receipt_id(receipt_id) when is_binary(receipt_id) do
    case Wardwright.ReceiptStore.get(receipt_id) do
      nil -> {:error, :receipt_not_found}
      receipt -> replay(receipt)
    end
  end

  def replay_receipt_id(_receipt_id), do: {:error, "receipt_id is required"}

  def replay(receipt) when is_map(receipt) do
    with receipt_id when is_binary(receipt_id) and receipt_id != "" <- Map.get(receipt, @receipt_id_key),
         {:ok, recording} <- recording(receipt),
         {:ok, decision} <- decision_recording(receipt, recording) do
      {:ok, replay_result(receipt, receipt_id, recording, decision)}
    else
      nil -> {:error, "receipt_id is required"}
      "" -> {:error, "receipt_id is required"}
      {:error, message} -> {:error, message}
    end
  end

  def replay(_receipt), do: {:error, "receipt must be a JSON object"}

  defp recording(receipt) do
    case Map.get(receipt, @vcr_key) do
      recording when is_map(recording) -> {:ok, recording}
      _missing -> {:ok, legacy_recording(receipt)}
    end
  end

  defp decision_recording(receipt, recording) do
    decision = first_map(Map.get(recording, @decision_key), Map.get(receipt, @decision_key))

    if decision == %{} do
      {:error, "receipt does not include replayable decision metadata"}
    else
      {:ok, decision}
    end
  end

  defp replay_result(receipt, receipt_id, recording, decision) do
    policy = first_map(Map.get(recording, @policy_key), policy_from_decision(decision))
    route = first_map(Map.get(recording, @route_key), route_from_decision(decision))
    final_status = final_status(receipt, recording)

    [
      {@schema_key, @schema},
      {@source_receipt_id_key, receipt_id},
      {@source_vcr_schema_key, Map.get(recording, @schema_key, @legacy_schema)},
      {@mode_key, "receipt_metadata"},
      {@redaction_key, Map.get(recording, @redaction_key, @metadata_redaction)},
      {@replayed_at_key, DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
      {@model_id_key, Map.get(receipt, @model_id_key)},
      {@model_version_key, Map.get(receipt, @model_version_key)},
      {@request_key, first_map(Map.get(recording, @request_key), Map.get(receipt, @request_key))},
      {@policy_key, policy},
      {@route_key, route},
      {@decision_key, decision},
      {@final_key,
       Map.new([
         {@status_key, "replayed"},
         {@original_status_key, final_status},
         {@final_status_key, final_status},
         {@provider_called_key, false},
         {@would_call_provider_key, false}
       ])},
      {@warnings_key, replay_warnings(recording)}
    ]
    |> reject_nil_fields()
  end

  defp legacy_recording(receipt) do
    [
      {@schema_key, @legacy_schema},
      {@redaction_key, @metadata_redaction},
      {@request_key, legacy_request_summary(Map.get(receipt, @request_key, %{}))},
      {@decision_key, Map.get(receipt, @decision_key, %{})},
      {@policy_key, policy_from_decision(Map.get(receipt, @decision_key, %{}))},
      {@route_key, route_from_decision(Map.get(receipt, @decision_key, %{}))}
    ]
    |> reject_nil_fields()
  end

  defp policy_from_decision(decision) when is_map(decision) do
    [
      {@actions_key, Map.get(decision, @policy_actions_key, [])},
      {@conflicts_key, Map.get(decision, @policy_conflicts_key, [])},
      {@events_key, nested_get(decision, @final_key, @events_key)},
      {@alert_count_key, nested_get(decision, @final_key, @alert_count_key)}
    ]
    |> reject_nil_fields()
  end

  defp policy_from_decision(_decision), do: %{}

  defp route_from_decision(decision) when is_map(decision) do
    [
      {@estimated_prompt_tokens_key, Map.get(decision, @estimated_prompt_tokens_key)},
      {@fallback_models_key, Map.get(decision, @fallback_models_key)},
      {@fallback_used_key, Map.get(decision, @fallback_used_key)},
      {@policy_route_constraints_key, Map.get(decision, @policy_route_constraints_key)},
      {@reason_key, Map.get(decision, @reason_key)},
      {@route_blocked_key, Map.get(decision, @route_blocked_key)},
      {@route_id_key, Map.get(decision, @route_id_key)},
      {@route_lineage_key, Map.get(decision, @route_lineage_key)},
      {@route_type_key, Map.get(decision, @route_type_key)},
      {@rule_key, Map.get(decision, @rule_key)},
      {@selected_context_window_key, Map.get(decision, @selected_context_window_key)},
      {@selected_model_key, Map.get(decision, @selected_model_key)},
      {@selected_models_key, Map.get(decision, @selected_models_key)},
      {@selected_provider_key, Map.get(decision, @selected_provider_key)},
      {@skipped_key, Map.get(decision, @skipped_key)},
      {@strategy_key, Map.get(decision, @strategy_key)}
    ]
    |> reject_nil_fields()
  end

  defp route_from_decision(_decision), do: %{}

  defp final_status(receipt, recording) do
    nested_get(recording, @final_key, @status_key) ||
      nested_get(receipt, @final_key, @status_key)
  end

  defp legacy_request_summary(request) when is_map(request) do
    messages = Map.get(request, @messages_key, [])

    [
      {@estimated_prompt_tokens_key, Map.get(request, @estimated_prompt_tokens_key)},
      {@message_content_lengths_key, legacy_message_lengths(messages)},
      {@message_count_key, legacy_message_count(request, messages)},
      {@message_roles_key, legacy_message_roles(messages)},
      {@model_key, Map.get(request, @model_key)},
      {@normalized_model_key, Map.get(request, @normalized_model_key)},
      {@stream_key, Map.get(request, @stream_key)},
      {@structured_output_configured_key, Map.get(request, @structured_output_configured_key)},
      {@tool_context_key, Map.get(request, @tool_context_key)}
    ]
    |> reject_empty_request_fields()
  end

  defp legacy_request_summary(_request), do: %{}

  defp legacy_message_count(_request, messages) when is_list(messages) and messages != [], do: length(messages)
  defp legacy_message_count(request, _messages), do: Map.get(request, @message_count_key)

  defp legacy_message_roles(messages) when is_list(messages) and messages != [],
    do: Enum.map(messages, &Map.get(&1, @role_key, ""))

  defp legacy_message_roles(_messages), do: nil

  defp legacy_message_lengths(messages) when is_list(messages) and messages != [] do
    Enum.map(messages, &legacy_message_content_length/1)
  end

  defp legacy_message_lengths(_messages), do: nil

  defp legacy_message_content_length(%{@content_key => content}), do: legacy_content_length(content)
  defp legacy_message_content_length(_message), do: 0

  defp legacy_content_length(nil), do: 0
  defp legacy_content_length(value) when is_binary(value), do: String.length(value)

  defp legacy_content_length(value) when is_list(value) do
    Enum.reduce(value, 0, fn
      %{@text_key => text}, acc when is_binary(text) -> acc + String.length(text)
      %{@content_key => text}, acc when is_binary(text) -> acc + String.length(text)
      part, acc -> acc + byte_size(Jason.encode!(part))
    end)
  end

  defp legacy_content_length(value), do: byte_size(Jason.encode!(value))

  defp replay_warnings(recording) do
    if Map.get(recording, @schema_key) == @vcr_schema do
      []
    else
      [@legacy_replay_warning]
    end
  end

  defp first_map(value, _fallback) when is_map(value), do: value
  defp first_map(_value, fallback) when is_map(fallback), do: fallback
  defp first_map(_value, _fallback), do: %{}

  defp nested_get(map, parent_key, child_key) when is_map(map) do
    case Map.get(map, parent_key) do
      child when is_map(child) -> Map.get(child, child_key)
      _child -> nil
    end
  end

  defp nested_get(_map, _parent_key, _child_key), do: nil

  defp reject_nil_fields(fields) do
    fields
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp reject_empty_request_fields(fields) do
    fields
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end
end
