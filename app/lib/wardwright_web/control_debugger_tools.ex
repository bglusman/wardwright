defmodule WardwrightWeb.ControlDebuggerTools do
  @moduledoc false

  alias Wardwright.PolicyScenario
  alias Wardwright.PolicyScenarioStore
  alias WardwrightWeb.ControlDebuggerData
  alias WardwrightWeb.CounterfactualReplay

  def error_response(message, code, data) do
    %{
      "error" => %{
        "code" => code,
        "data" => data,
        "message" => message,
        "type" => "invalid_request"
      }
    }
  end

  def list_examples do
    examples =
      ControlDebuggerData.counterfactual_example_options()
      |> Enum.map(fn {id, title, summary} ->
        %{
          "default_pattern_id" => ControlDebuggerData.default_pattern_id_for_example(id),
          "default_policy_overlay" => overlay_for_example(id),
          "id" => id,
          "summary" => summary,
          "title" => title
        }
      end)

    {:ok,
     %{
       "data" => examples,
       "default_example_id" => ControlDebuggerData.default_counterfactual_example_id(),
       "schema" => "wardwright.control_debugger_examples.v1"
     }}
  end

  def record_example(example_id) do
    example_id = blank_fallback(example_id, ControlDebuggerData.default_counterfactual_example_id())

    case ControlDebuggerData.run_counterfactual_example(example_id) do
      {true, message, receipt_id, facts} ->
        {:ok,
         %{
           "example_id" => example_id,
           "facts" => facts_map(facts),
           "message" => message,
           "receipt_id" => receipt_id,
           "schema" => "wardwright.control_debugger_recording.v1"
         }}

      {false, message, _receipt_id, facts} ->
        {:error, message, %{"example_id" => example_id, "facts" => facts_map(facts)}}
    end
  end

  def load_trace(params) when is_map(params) do
    receipt_id = trim_string(Map.get(params, "receipt_id") || Map.get(params, :receipt_id))
    session_id = trim_string(Map.get(params, "session_id") || Map.get(params, :session_id))

    cond do
      receipt_id != "" ->
        load_trace_for_receipt(receipt_id)

      session_id != "" ->
        load_trace_for_session(session_id)

      true ->
        {:error, "receipt_id or session_id is required", %{}}
    end
  end

  def replay_cursor(params) when is_map(params) do
    session_id = trim_string(Map.get(params, "session_id") || Map.get(params, :session_id))
    cursor = trace_cursor(params)

    case ControlDebuggerData.replay_to_fork_point(session_id, cursor) do
      {true, message, facts} ->
        {:ok,
         %{
           "facts" => facts_map(facts),
           "message" => message,
           "provider_called" => false,
           "schema" => "wardwright.control_debugger_cursor_replay.v1",
           "session_id" => session_id,
           "trace_cursor" => cursor
         }}

      {false, message, facts} ->
        {:error, message, %{"facts" => facts_map(facts), "session_id" => session_id, "trace_cursor" => cursor}}
    end
  end

  def fork_cursor(params) when is_map(params) do
    session_id = trim_string(Map.get(params, "session_id") || Map.get(params, :session_id))
    cursor = trace_cursor(params)
    overlay = policy_overlay_json(params)

    case ControlDebuggerData.fork_and_continue_from_point(session_id, cursor, overlay, "scripted_agent", "") do
      {true, message, facts} ->
        {:ok,
         %{
           "continuation_mode" => "scripted_agent",
           "facts" => facts_map(facts),
           "message" => message,
           "provider_called" => false,
           "schema" => "wardwright.control_debugger_cursor_fork.v1",
           "session_id" => session_id,
           "trace_cursor" => cursor
         }}

      {false, message, facts} ->
        {:error, message, %{"facts" => facts_map(facts), "session_id" => session_id, "trace_cursor" => cursor}}
    end
  end

  def save_evidence(params) when is_map(params) do
    pattern_id =
      params
      |> Map.get("pattern_id", Map.get(params, :pattern_id))
      |> blank_fallback(ControlDebuggerData.default_pattern_id())

    session_id = trim_string(Map.get(params, "session_id") || Map.get(params, :session_id))
    cursor = trace_cursor(params)

    with :ok <- known_pattern(pattern_id),
         {:ok, transcript} <- CounterfactualReplay.transcript(session_id),
         {:ok, selected, events} <- selected_trace_events(transcript["events"], cursor),
         scenario_body = scenario_from_trace(pattern_id, session_id, cursor, selected, events, params),
         {:ok, scenario} <- PolicyScenarioStore.create(pattern_id, scenario_body) do
      {:ok,
       %{
         "message" => "Saved selected Control Debugger trace evidence as saved:#{scenario.id} for #{pattern_id}.",
         "pattern_id" => pattern_id,
         "scenario" => PolicyScenario.to_map(scenario),
         "schema" => "wardwright.control_debugger_saved_evidence.v1",
         "session_id" => session_id,
         "trace_cursor" => cursor
       }}
    else
      {:error, message} when is_binary(message) ->
        {:error, message, %{"pattern_id" => pattern_id, "session_id" => session_id, "trace_cursor" => cursor}}
    end
  end

  defp load_trace_for_receipt(receipt_id) do
    case ControlDebuggerData.load_transcript_for_receipt(receipt_id) do
      {true, message, session_id, suggested_cursor, events} ->
        {:ok,
         %{
           "events" => event_summary_maps(events),
           "message" => message,
           "receipt_id" => receipt_id,
           "schema" => "wardwright.control_debugger_trace.v1",
           "session_id" => session_id,
           "suggested_fork_cursor" => suggested_cursor
         }}

      {false, message, session_id, suggested_cursor, events} ->
        {:error, message,
         %{
           "events" => event_summary_maps(events),
           "receipt_id" => receipt_id,
           "session_id" => session_id,
           "suggested_fork_cursor" => suggested_cursor
         }}
    end
  end

  defp load_trace_for_session(session_id) do
    case CounterfactualReplay.transcript(session_id) do
      {:ok, transcript} ->
        events = Map.get(transcript, "events", [])

        {:ok,
         %{
           "events" => raw_event_summary_maps(events),
           "message" => "Loaded #{length(events)} trace event(s) for #{session_id}.",
           "schema" => "wardwright.control_debugger_trace.v1",
           "session_id" => session_id,
           "suggested_fork_cursor" => suggested_cursor(events)
         }}

      {:error, message} ->
        {:error, message, %{"session_id" => session_id}}
    end
  end

  defp selected_trace_events(events, cursor) when is_list(events) and is_binary(cursor) and cursor != "" do
    case Enum.split_while(events, &(&1["cursor"] != cursor)) do
      {_before, []} -> {:error, "unknown transcript cursor #{inspect(cursor)}"}
      {before, [selected | _after]} -> {:ok, selected, before ++ [selected]}
    end
  end

  defp selected_trace_events(_events, _cursor), do: {:error, "session_id and trace_cursor are required"}

  defp scenario_from_trace(pattern_id, session_id, cursor, selected, events, params) do
    scenario_id =
      params
      |> Map.get("scenario_id", Map.get(params, :scenario_id))
      |> blank_fallback(
        "trace-#{Base.url_encode64(:crypto.hash(:sha256, cursor), padding: false) |> binary_part(0, 16)}"
      )

    %{
      "expected_behavior" => "Preserve selected Control Debugger evidence and replay/fork cursor #{cursor}.",
      "input_summary" => "Control Debugger trace #{session_id} selected #{event_label(selected)}.",
      "pinned" => true,
      "receipt_preview" => %{
        "selected_event_type" => selected["type"],
        "selected_sequence" => selected["sequence"],
        "session_id" => session_id,
        "trace_cursor" => cursor
      },
      "scenario_id" => scenario_id,
      "source" => "live_replay",
      "title" => blank_fallback(Map.get(params, "title", Map.get(params, :title)), "Control Debugger trace evidence"),
      "trace" => Enum.map(events, &scenario_trace_event(pattern_id, cursor, &1)),
      "verdict" => "inconclusive"
    }
  end

  defp scenario_trace_event(_pattern_id, selected_cursor, event) do
    cursor = event["cursor"] || "event"

    %{
      "detail" => event_detail(event),
      "id" => cursor,
      "kind" => "control_debugger_trace_event",
      "label" => event_label(event),
      "node_id" => "control_debugger.#{event["type"] || "event"}",
      "phase" => event["type"] || "trace.event",
      "severity" => if(cursor == selected_cursor, do: "warn", else: "info"),
      "state_id" => "active"
    }
  end

  defp facts_map(facts) when is_list(facts) do
    facts
    |> Map.new(fn
      {key, value} -> {key, value}
      other -> {"Fact", inspect(other)}
    end)
  end

  defp event_summary_maps(events) when is_list(events) do
    Enum.map(events, fn
      {cursor, sequence, type, label, detail, recommendation} ->
        %{
          "cursor" => cursor,
          "detail" => detail,
          "label" => label,
          "recommendation" => recommendation,
          "sequence" => sequence,
          "type" => type
        }

      event when is_map(event) ->
        event
    end)
  end

  defp raw_event_summary_maps(events) when is_list(events) do
    Enum.map(events, fn event ->
      %{
        "cursor" => event["cursor"] || "",
        "detail" => event_detail(event),
        "label" => event_label(event),
        "recommendation" => if(event["fork_point"] == true, do: "Suggested fork point.", else: "Recorded event."),
        "sequence" => to_string(event["sequence"] || ""),
        "type" => event["type"] || "event"
      }
    end)
  end

  defp suggested_cursor(events) do
    events
    |> Enum.find(fn event -> event["fork_point"] == true end)
    |> case do
      %{"cursor" => cursor} when is_binary(cursor) -> cursor
      _ -> ""
    end
  end

  defp event_label(%{"type" => "tool.call"} = event), do: "Tool call: #{get_in(event, ["tool", "name"]) || "tool"}"
  defp event_label(%{"type" => "tool.result"} = event), do: "Tool result: #{get_in(event, ["tool", "name"]) || "tool"}"
  defp event_label(%{"type" => type}) when is_binary(type), do: type
  defp event_label(_event), do: "Transcript event"

  defp event_detail(%{"type" => "tool.call"} = event) do
    args = get_in(event, ["tool", "args"]) || %{}
    path = args["path"]

    if is_binary(path) and path != "" do
      "args: path=#{path}"
    else
      "args: #{compact_json(args)}"
    end
  end

  defp event_detail(%{"type" => "tool.result"} = event),
    do: "result: #{compact_json(get_in(event, ["tool", "result"]) || %{})}"

  defp event_detail(%{"type" => "gateway.request"} = event),
    do: "path: #{get_in(event, ["gateway", "path"]) || "unknown"}"

  defp event_detail(%{"type" => "receipt.finalized"} = event), do: "status: #{event["status"] || "unknown"}"

  defp event_detail(event) when is_map(event),
    do: compact_json(Map.drop(event, ["schema", "cursor", "sequence", "session_id", "type"]))

  defp event_detail(_event), do: "recorded event"

  defp compact_json(value), do: value |> JSON.encode!() |> String.slice(0, 180)

  defp overlay_for_example(example_id) do
    example_id
    |> ControlDebuggerData.default_policy_overlay_json_for_example()
    |> JSON.decode!()
  end

  defp policy_overlay_json(params) do
    case Map.get(params, "policy_overlay", Map.get(params, :policy_overlay)) do
      overlay when is_map(overlay) -> JSON.encode!(overlay)
      overlay when is_binary(overlay) -> overlay
      _ -> ControlDebuggerData.default_policy_overlay_json()
    end
  end

  defp trace_cursor(params),
    do:
      trim_string(
        Map.get(params, "trace_cursor") || Map.get(params, :trace_cursor) || Map.get(params, "cursor") ||
          Map.get(params, :cursor)
      )

  defp known_pattern(pattern_id) do
    if pattern_id in Wardwright.PolicyProjection.pattern_ids() do
      :ok
    else
      {:error, "unknown policy pattern #{pattern_id}"}
    end
  end

  defp blank_fallback(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      trimmed -> trimmed
    end
  end

  defp blank_fallback(_value, fallback), do: fallback

  defp trim_string(value) when is_binary(value), do: String.trim(value)
  defp trim_string(_value), do: ""
end
