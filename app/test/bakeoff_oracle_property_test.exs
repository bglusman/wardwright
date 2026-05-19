defmodule Wardwright.BakeoffOraclePropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "structured output guard oracle" do
    property "accepts valid answers without guard events" do
      check all(answer <- valid_answer()) do
        result = structured_guard_loop_oracle([Jason.encode!(answer)])

        assert result.final_status == "completed"
        assert result.guard_events == []
        assert result.selected_schema == "answer_v1"
        assert result.parsed_output == answer
      end
    end

    property "records one guard event before a repaired valid answer" do
      check all({invalid_output, valid_output} <- invalid_then_valid_outputs()) do
        result = structured_guard_loop_oracle([invalid_output, Jason.encode!(valid_output)])

        assert result.final_status == "completed_after_guard"

        assert [%{action: "retry_with_validation_feedback", attempt_index: 0}] =
                 result.guard_events

        assert result.parsed_output == valid_output
      end
    end

    property "exhausts attempt budget after repeated syntax failures" do
      check all(outputs <- list_of(constant("{not json"), length: 3)) do
        result = structured_guard_loop_oracle(outputs, max_attempts: 3)

        assert result.final_status == "exhausted_guard_budget"
        assert length(result.guard_events) == 3
        assert Enum.map(result.guard_events, & &1.guard_type) == List.duplicate("json_syntax", 3)
      end
    end

    test "matches representative regeneration paths" do
      scenarios = [
        %{
          expected_rules: ["minimum-confidence"],
          expected_status: "completed_after_guard",
          expected_types: ["semantic_validation"],
          outputs: [
            ~s({"answer":"too uncertain","confidence":0.2}),
            ~s({"answer":"Use the current API.","confidence":0.93})
          ]
        },
        %{
          expected_rules: ["answer-json", "answer-json", "minimum-confidence"],
          expected_status: "completed_after_guard",
          expected_types: ["json_syntax", "schema_validation", "semantic_validation"],
          outputs: [
            "{not json",
            ~s({"answer":"missing confidence"}),
            ~s({"answer":"valid shape but still uncertain","confidence":0.4}),
            ~s({"answer":"Use the deterministic cache receipt.","confidence":0.91,"citations":["receipt-42"]})
          ]
        },
        %{
          expected_rules: ["answer-json", "answer-json", "answer-json"],
          expected_status: "exhausted_guard_budget",
          expected_types: ["json_syntax", "json_syntax", "json_syntax"],
          outputs: ["{not json", "{still not json", "{nope"]
        }
      ]

      for scenario <- scenarios do
        result =
          structured_guard_loop_oracle(scenario.outputs,
            max_attempts: length(scenario.outputs)
          )

        assert result.final_status == scenario.expected_status
        assert Enum.map(result.guard_events, & &1.guard_type) == scenario.expected_types
        assert Enum.map(result.guard_events, & &1.rule_id) == scenario.expected_rules
      end
    end
  end

  describe "history cache oracle" do
    property "counts only retained events inside the requested session scope" do
      check all(events <- history_events(), max_entries <- integer(1..20)) do
        count_a =
          history_count(events,
            max_entries: max_entries,
            session_id: "session-a",
            kind: "tool_call",
            key: "shell:ls"
          )

        manual_a =
          events
          |> retained_events(max_entries)
          |> Enum.count(&match_event?(&1, "session-a", "tool_call", "shell:ls"))

        count_b =
          history_count(events,
            max_entries: max_entries,
            session_id: "session-b",
            kind: "tool_call",
            key: "shell:ls"
          )

        manual_b =
          events
          |> retained_events(max_entries)
          |> Enum.count(&match_event?(&1, "session-b", "tool_call", "shell:ls"))

        assert count_a == manual_a
        assert count_b == manual_b
      end
    end

    property "retention keeps the youngest timestamp then sequence entries" do
      check all(events <- history_events(), max_entries <- integer(1..20)) do
        retained = retained_events(events, max_entries)

        assert length(retained) <= max_entries

        if length(events) > max_entries do
          retained_keys = MapSet.new(retained, &{&1.created_at_unix_ms, &1.sequence})

          evicted =
            events
            |> Enum.sort_by(&{&1.created_at_unix_ms, &1.sequence})
            |> Enum.drop(-max_entries)

          refute Enum.any?(
                   evicted,
                   &MapSet.member?(retained_keys, {&1.created_at_unix_ms, &1.sequence})
                 )
        end
      end
    end
  end

  describe "alert queue oracle" do
    property "never queues more alert deliveries than capacity" do
      check all(
              decisions <- alert_decisions(),
              capacity <- integer(0..10),
              on_full <- member_of(["drop", "dead_letter", "fail_closed"])
            ) do
        results = alert_queue_oracle(decisions, capacity: capacity, on_full: on_full)

        assert Enum.count(results, &(&1.outcome == "queued")) <= capacity
        assert length(results) == length(decisions)

        for {decision, result} <- Enum.zip(decisions, results), not decision.triggers_alert do
          assert result.outcome == "not_alerting"
        end
      end
    end

    property "does not enqueue the same idempotency key twice" do
      check all(decisions <- alert_decisions(), capacity <- integer(0..10)) do
        results = alert_queue_oracle(decisions, capacity: capacity, on_full: "dead_letter")

        queued_keys =
          for result <- results, result.outcome == "queued", do: result.idempotency_key

        assert length(queued_keys) == length(Enum.uniq(queued_keys))

        Enum.zip(decisions, results)
        |> Enum.reduce(MapSet.new(), fn {decision, result}, seen_trigger_keys ->
          if result.outcome == "duplicate_suppressed" do
            assert MapSet.member?(seen_trigger_keys, decision.idempotency_key)
          end

          if decision.triggers_alert do
            MapSet.put(seen_trigger_keys, decision.idempotency_key)
          else
            seen_trigger_keys
          end
        end)
      end
    end

    test "matches representative backpressure scenarios" do
      scenarios = [
        {[%{decision_id: "a1", idempotency_key: "alert-a", triggers_alert: true}], 4, "dead_letter", ["queued"]},
        {[
           %{decision_id: "a1", idempotency_key: "same-alert", triggers_alert: true},
           %{decision_id: "a2", idempotency_key: "same-alert", triggers_alert: true}
         ], 4, "dead_letter", ["queued", "duplicate_suppressed"]},
        {[
           %{decision_id: "a1", idempotency_key: "alert-a", triggers_alert: true},
           %{decision_id: "a2", idempotency_key: "alert-b", triggers_alert: true}
         ], 1, "dead_letter", ["queued", "dead_lettered"]},
        {[
           %{decision_id: "a1", idempotency_key: "alert-a", triggers_alert: true},
           %{decision_id: "a2", idempotency_key: "alert-b", triggers_alert: true}
         ], 1, "drop", ["queued", "dropped"]},
        {[%{decision_id: "a1", idempotency_key: "alert-a", triggers_alert: true}], 0, "fail_closed", ["failed_closed"]}
      ]

      for {decisions, capacity, on_full, expected} <- scenarios do
        results = alert_queue_oracle(decisions, capacity: capacity, on_full: on_full)
        assert Enum.map(results, & &1.outcome) == expected
      end
    end
  end

  defp valid_answer do
    fixed_map(%{
      "answer" => string(:alphanumeric, min_length: 1, max_length: 80),
      "citations" => list_of(string(:alphanumeric, min_length: 1, max_length: 40), max_length: 3),
      "confidence" => float(min: 0.7, max: 1.0)
    })
  end

  defp invalid_then_valid_outputs do
    invalid =
      member_of([
        "{not json",
        Jason.encode!(%{"answer" => "too uncertain", "confidence" => 0.1}),
        Jason.encode!(%{"answer" => "missing confidence"})
      ])

    tuple({invalid, valid_answer()})
  end

  defp structured_guard_loop_oracle(outputs, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)

    outputs
    |> Enum.take(max_attempts)
    |> Enum.with_index()
    |> Enum.reduce_while(%{guard_events: []}, fn {output, attempt_index}, acc ->
      case classify_structured_output(output) do
        {:ok, parsed} ->
          status = if acc.guard_events == [], do: "completed", else: "completed_after_guard"

          {:halt,
           %{
             final_status: status,
             guard_events: acc.guard_events,
             parsed_output: parsed,
             selected_schema: "answer_v1"
           }}

        {:error, guard_type, rule_id} ->
          event = %{
            action: "retry_with_validation_feedback",
            attempt_index: attempt_index,
            guard_type: guard_type,
            rule_id: rule_id,
            type: "structured_output.guard"
          }

          {:cont, %{acc | guard_events: acc.guard_events ++ [event]}}
      end
    end)
    |> case do
      %{final_status: _} = result ->
        result

      %{guard_events: guard_events} ->
        %{
          final_status: "exhausted_guard_budget",
          guard_events: guard_events,
          parsed_output: nil,
          selected_schema: nil
        }
    end
  end

  defp classify_structured_output(output) do
    with {:ok, parsed} <- Jason.decode(output),
         :ok <- validate_answer_schema(parsed),
         :ok <- validate_confidence(parsed) do
      {:ok, parsed}
    else
      {:error, %Jason.DecodeError{}} -> {:error, "json_syntax", "answer-json"}
      {:error, :schema} -> {:error, "schema_validation", "answer-json"}
      {:error, :confidence} -> {:error, "semantic_validation", "minimum-confidence"}
    end
  end

  defp validate_answer_schema(%{"answer" => answer, "confidence" => confidence} = parsed)
       when is_binary(answer) and answer != "" and is_number(confidence) do
    allowed = MapSet.new(["answer", "confidence", "citations"])

    cond do
      not MapSet.subset?(MapSet.new(Map.keys(parsed)), allowed) ->
        {:error, :schema}

      Map.has_key?(parsed, "citations") and not valid_citations?(parsed["citations"]) ->
        {:error, :schema}

      confidence < 0 or confidence > 1 ->
        {:error, :schema}

      true ->
        :ok
    end
  end

  defp validate_answer_schema(_), do: {:error, :schema}

  defp valid_citations?(citations) when is_list(citations), do: Enum.all?(citations, &is_binary/1)
  defp valid_citations?(_), do: false

  defp validate_confidence(%{"confidence" => confidence}) when confidence >= 0.7, do: :ok
  defp validate_confidence(_), do: {:error, :confidence}

  defp history_events do
    attrs =
      fixed_map(%{
        created_at_unix_ms: integer(0..1_000),
        key: member_of(["shell:ls", "shell:rm", "regex:secret", "note"]),
        kind: member_of(["tool_call", "response_text", "receipt_event"]),
        session_id: member_of(["session-a", "session-b", "session-c"])
      })

    attrs
    |> list_of(max_length: 80)
    |> map(fn events ->
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {event, sequence} -> Map.put(event, :sequence, sequence) end)
    end)
  end

  defp retained_events(events, max_entries) do
    events
    |> Enum.sort_by(&{&1.created_at_unix_ms, &1.sequence})
    |> Enum.take(-max_entries)
  end

  defp history_count(events, opts) do
    events
    |> retained_events(Keyword.fetch!(opts, :max_entries))
    |> Enum.count(
      &match_event?(
        &1,
        Keyword.fetch!(opts, :session_id),
        Keyword.fetch!(opts, :kind),
        Keyword.fetch!(opts, :key)
      )
    )
  end

  defp match_event?(event, session_id, kind, key) do
    event.session_id == session_id and event.kind == kind and event.key == key
  end

  defp alert_decisions do
    fixed_map(%{
      decision_id: string(:alphanumeric, min_length: 1, max_length: 12),
      idempotency_key: member_of(["same-alert", "alert-a", "alert-b", "alert-c", "alert-d"]),
      triggers_alert: boolean()
    })
    |> list_of(max_length: 40)
  end

  defp alert_queue_oracle(decisions, opts) do
    capacity = Keyword.fetch!(opts, :capacity)
    on_full = Keyword.fetch!(opts, :on_full)

    decisions
    |> Enum.reduce(%{queue: [], results: [], seen_keys: MapSet.new()}, fn decision, acc ->
      cond do
        not decision.triggers_alert ->
          append_alert_result(acc, decision, "not_alerting")

        MapSet.member?(acc.seen_keys, decision.idempotency_key) ->
          append_alert_result(acc, decision, "duplicate_suppressed")

        length(acc.queue) < capacity ->
          acc
          |> Map.update!(:seen_keys, &MapSet.put(&1, decision.idempotency_key))
          |> Map.update!(:queue, &(&1 ++ [decision.idempotency_key]))
          |> append_alert_result(decision, "queued")

        on_full == "drop" ->
          acc
          |> Map.update!(:seen_keys, &MapSet.put(&1, decision.idempotency_key))
          |> append_alert_result(decision, "dropped")

        on_full == "dead_letter" ->
          acc
          |> Map.update!(:seen_keys, &MapSet.put(&1, decision.idempotency_key))
          |> append_alert_result(decision, "dead_lettered")

        true ->
          acc
          |> Map.update!(:seen_keys, &MapSet.put(&1, decision.idempotency_key))
          |> append_alert_result(decision, "failed_closed")
      end
    end)
    |> Map.fetch!(:results)
  end

  defp append_alert_result(acc, decision, outcome) do
    result = %{
      decision_id: decision.decision_id,
      idempotency_key: decision.idempotency_key,
      outcome: outcome
    }

    Map.update!(acc, :results, &(&1 ++ [result]))
  end
end
