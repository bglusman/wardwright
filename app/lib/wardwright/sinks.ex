defmodule Wardwright.Sinks do
  @moduledoc false

  use Agent

  alias Wardwright.Policy.AlertCore
  alias Wardwright.Runtime.Events

  @default_history_limit 100
  @default_timeout_ms 1_000
  @supported_sink_kinds ["memory_alert", "jsonl_file", "webhook"]

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state(Wardwright.default_config()["sinks"]) end,
      name: __MODULE__
    )
  end

  def configure(config), do: Agent.update(__MODULE__, fn _state -> initial_state(config || []) end)

  def reset, do: configure(Wardwright.default_config()["sinks"])

  def emit(events, opts \\ []) when is_list(events) do
    Agent.get_and_update(__MODULE__, fn state ->
      receipt_hint = Keyword.get(opts, :receipt_id)

      Enum.reduce(events, {state, []}, fn raw_event, {state, results} ->
        event = event_envelope(raw_event, receipt_hint)
        publish_receipt_usage_telemetry(event)
        {state, event_results} = deliver_event(state, event)
        {state, results ++ event_results}
      end)
      |> then(fn {state, results} -> {results, state} end)
    end)
  end

  def alert_results(results) when is_list(results) do
    Enum.filter(results, fn result ->
      result["event_type"] == "policy.alert" and
        (result["kind"] == "memory_alert" or result["outcome"] == "failed_closed")
    end)
  end

  def fail_closed?(results), do: Enum.any?(results, &(&1["outcome"] == "failed_closed"))

  def status do
    Agent.get(__MODULE__, fn state ->
      %{
        "data" =>
          state.sinks
          |> Enum.map(fn {sink_id, sink_state} -> sink_status(sink_id, sink_state) end)
          |> Enum.sort_by(& &1["id"])
      }
    end)
  end

  def status(sink_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.sinks, sink_id) do
        {:ok, sink_state} -> sink_status(sink_id, sink_state)
        :error -> nil
      end
    end)
  end

  def legacy_alert_status do
    Agent.get(__MODULE__, fn state ->
      state.sinks
      |> Enum.find_value(fn {sink_id, sink_state} ->
        if sink_state.config["kind"] == "memory_alert" do
          sink_status(sink_id, sink_state)
        end
      end)
      |> Kernel.||(%{
        "capacity" => 0,
        "dead_letter_count" => 0,
        "dropped_count" => 0,
        "duplicate_suppressed_count" => 0,
        "failed_closed_count" => 0,
        "id" => "policy-alerts",
        "kind" => "in_memory_alert_sink",
        "last_result" => nil,
        "on_full" => "dead_letter",
        "queue_depth" => 0,
        "queued_count" => 0,
        "seen_count" => 0
      })
    end)
  end

  def normalize_config(config, alert_delivery_config \\ %{})

  def normalize_config(sinks, alert_delivery_config) when is_list(sinks) do
    sinks
    |> Enum.map(&normalize_sink/1)
    |> Enum.reject(&is_nil/1)
    |> apply_legacy_alert_delivery(alert_delivery_config)
  end

  def normalize_config(_sinks, alert_delivery_config) do
    [legacy_alert_sink(alert_delivery_config)]
  end

  def legacy_alert_sink(config) do
    config = normalize_alert_delivery(config)

    %{
      "delivery" => config,
      "id" => "policy-alerts",
      "kind" => "memory_alert",
      "redaction" => "metadata",
      "select" => %{"types" => ["policy.alert"]}
    }
  end

  defp initial_state(config) do
    sinks =
      config
      |> Map.new(fn sink_config ->
        {sink_config["id"], new_sink_state(sink_config)}
      end)

    %{sinks: sinks}
  end

  defp new_sink_state(config) do
    %{
      config: config,
      history: [],
      last_result: nil,
      outcomes: %{},
      queue: [],
      seen: MapSet.new()
    }
  end

  defp deliver_event(state, event) do
    Enum.reduce(state.sinks, {state, []}, fn {sink_id, sink_state}, {state, results} ->
      if selected?(sink_state.config, event) do
        {sink_state, result} = deliver_to_sink(sink_id, sink_state, event)
        state = put_in(state, [:sinks, sink_id], sink_state)
        {state, results ++ [result]}
      else
        {state, results}
      end
    end)
  end

  defp deliver_to_sink(sink_id, sink_state, event) do
    start_time = System.monotonic_time()

    result =
      case sink_state.config["kind"] do
        "memory_alert" -> deliver_memory_alert(sink_id, sink_state, event)
        "jsonl_file" -> deliver_jsonl_file(sink_id, sink_state, event)
        "webhook" -> deliver_webhook(sink_id, sink_state, event)
        kind -> base_result(sink_id, kind, event, idempotency_key(event), "dead_lettered")
      end

    duration = System.monotonic_time() - start_time

    sink_state = record_result(sink_state, event, result)
    publish_delivery_telemetry(sink_state.config, result, duration)
    publish_queue_depth(sink_state.config, length(sink_state.queue))
    publish_policy_alert_delivery(sink_state, result)
    {sink_state, result}
  end

  defp deliver_memory_alert(sink_id, sink_state, event) do
    key = alert_idempotency_key(event)
    delivery = sink_state.config["delivery"] || %{}

    decision =
      AlertCore.decide_enqueue(
        delivery,
        length(sink_state.queue),
        MapSet.member?(sink_state.seen, key),
        Map.put(event["payload"], "idempotency_key", key)
      )

    result = base_result(sink_id, "memory_alert", event, key, decision.outcome)

    case decision.outcome do
      "queued" ->
        result
        |> Map.put("_queue_key", key)
        |> Map.put("_seen_key", key)

      "duplicate_suppressed" ->
        result

      _ ->
        Map.put(result, "_seen_key", key)
    end
  end

  defp deliver_jsonl_file(sink_id, sink_state, event) do
    path = get_in(sink_state.config, ["delivery", "path"])
    key = idempotency_key(event)

    try do
      cond do
        not is_binary(path) or String.trim(path) == "" ->
          base_result(sink_id, "jsonl_file", event, key, "dead_lettered")

        MapSet.member?(sink_state.seen, key) ->
          base_result(sink_id, "jsonl_file", event, key, "duplicate_suppressed")

        true ->
          File.mkdir_p!(Path.dirname(path))

          File.write!(path, Jason.encode!(redacted_event(event, sink_state.config)) <> "\n", [
            :append
          ])

          base_result(sink_id, "jsonl_file", event, key, "delivered")
          |> Map.put("_seen_key", key)
      end
    rescue
      _error ->
        base_result(sink_id, "jsonl_file", event, key, on_error_outcome(sink_state.config))
    end
  end

  defp deliver_webhook(sink_id, sink_state, event) do
    url = get_in(sink_state.config, ["delivery", "url"])
    key = idempotency_key(event)

    try do
      cond do
        not is_binary(url) or String.trim(url) == "" ->
          base_result(sink_id, "webhook", event, key, "dead_lettered")

        MapSet.member?(sink_state.seen, key) ->
          base_result(sink_id, "webhook", event, key, "duplicate_suppressed")

        true ->
          payload = Jason.encode!(redacted_event(event, sink_state.config))
          headers = [{~c"content-type", ~c"application/json"}]
          request = {String.to_charlist(url), headers, ~c"application/json", payload}
          timeout = get_in(sink_state.config, ["delivery", "timeout_ms"]) || @default_timeout_ms

          case :httpc.request(:post, request, [{:timeout, timeout}], body_format: :binary) do
            {:ok, {{_, status, _}, _headers, _body}} when status in 200..299 ->
              base_result(sink_id, "webhook", event, key, "delivered")
              |> Map.put("_seen_key", key)

            _ ->
              base_result(sink_id, "webhook", event, key, on_error_outcome(sink_state.config))
          end
      end
    rescue
      _error ->
        base_result(sink_id, "webhook", event, key, on_error_outcome(sink_state.config))
    end
  end

  defp record_result(sink_state, event, result) do
    seen_key = Map.get(result, "_seen_key")
    queue_key = Map.get(result, "_queue_key")
    result = Map.drop(result, ["_queue_key", "_seen_key"])

    sink_state
    |> maybe_mark_seen(seen_key)
    |> maybe_enqueue(queue_key, result["outcome"])
    |> Map.update!(:outcomes, fn outcomes ->
      Map.update(outcomes, result["outcome"], 1, &(&1 + 1))
    end)
    |> Map.update!(:history, fn history ->
      ([Map.put(result, "created_at", event["created_at"])] ++ history)
      |> Enum.take(history_limit(sink_state.config))
    end)
    |> Map.put(:last_result, result)
  end

  defp maybe_mark_seen(sink_state, nil), do: sink_state
  defp maybe_mark_seen(sink_state, key), do: Map.update!(sink_state, :seen, &MapSet.put(&1, key))

  defp maybe_enqueue(sink_state, key, "queued") when is_binary(key), do: Map.update!(sink_state, :queue, &(&1 ++ [key]))

  defp maybe_enqueue(sink_state, _key, _outcome), do: sink_state

  defp event_envelope(event, receipt_hint) do
    type = string_value(event["type"])
    receipt_id = event["receipt_id"] || receipt_hint
    payload = Map.delete(event, "receipt_id")
    created_at = event["created_at"] || DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "created_at" => created_at,
      "event_schema" => "wardwright.sink_event.v1",
      "id" => event["id"] || event_id(type, receipt_id, payload, created_at),
      "payload" => payload,
      "policy_id" => event["policy_id"] || event["rule_id"],
      "receipt_id" => receipt_id,
      "session_id" => event["session_id"],
      "severity" => event["severity"],
      "type" => type
    }
  end

  defp event_id(type, receipt_id, payload, created_at) do
    :crypto.hash(:sha256, :erlang.term_to_binary({type, receipt_id, payload, created_at}))
    |> Base.url_encode64(padding: false)
  end

  defp idempotency_key(event) do
    payload_value(event, "idempotency_key") ||
      Enum.join(
        [
          event["receipt_id"],
          event["type"],
          payload_value(event, "rule_id"),
          payload_value(event, "message"),
          payload_value(event, "severity"),
          event["id"]
        ],
        ":"
      )
  end

  defp alert_idempotency_key(event) do
    payload_value(event, "idempotency_key") ||
      Enum.join(
        [
          event["receipt_id"],
          payload_value(event, "rule_id"),
          payload_value(event, "message"),
          payload_value(event, "severity")
        ],
        ":"
      )
  end

  defp base_result(sink_id, kind, event, key, outcome) do
    %{
      "event_id" => event["id"],
      "event_type" => event["type"],
      "idempotency_key" => key,
      "kind" => kind,
      "outcome" => outcome,
      "rule_id" => payload_value(event, "rule_id"),
      "sink_id" => sink_id
    }
  end

  defp payload_value(%{"payload" => payload}, key) when is_map(payload), do: Map.get(payload, key)
  defp payload_value(_event, _key), do: nil

  defp sink_status(sink_id, sink_state) do
    outcomes = sink_state.outcomes
    kind = sink_state.config["kind"]

    %{
      "capacity" => get_in(sink_state.config, ["delivery", "capacity"]),
      "dead_letter_count" => Map.get(outcomes, "dead_lettered", 0),
      "delivered_count" => Map.get(outcomes, "delivered", 0),
      "dropped_count" => Map.get(outcomes, "dropped", 0),
      "duplicate_suppressed_count" => Map.get(outcomes, "duplicate_suppressed", 0),
      "failed_closed_count" => Map.get(outcomes, "failed_closed", 0),
      "id" => sink_id,
      "kind" => status_kind(kind),
      "last_result" => sink_state.last_result,
      "on_full" => get_in(sink_state.config, ["delivery", "on_full"]),
      "queue_depth" => length(sink_state.queue),
      "queued_count" => Map.get(outcomes, "queued", 0),
      "recent" => Enum.reverse(sink_state.history),
      "redaction" => sink_state.config["redaction"],
      "seen_count" => MapSet.size(sink_state.seen),
      "select" => sink_state.config["select"]
    }
  end

  defp status_kind("memory_alert"), do: "in_memory_alert_sink"
  defp status_kind(kind), do: kind

  defp selected?(config, event) do
    types = get_in(config, ["select", "types"]) || []
    Enum.any?(types, &type_match?(&1, event["type"]))
  end

  defp type_match?("*", _type), do: true

  defp type_match?(pattern, type) when is_binary(pattern) and is_binary(type) do
    if String.ends_with?(pattern, ".*") do
      prefix = String.trim_trailing(pattern, "*")
      String.starts_with?(type, prefix)
    else
      pattern == type
    end
  end

  defp type_match?(_pattern, _type), do: false

  defp redacted_event(event, config) do
    event
    |> Map.put("redaction", config["redaction"] || "metadata")
    |> Map.update!("payload", fn payload ->
      if config["redaction"] == "full" do
        payload
      else
        Map.take(payload, [
          "type",
          "rule_id",
          "message",
          "severity",
          "status",
          "simulation",
          "alert_count",
          "selected_model",
          "selected_provider",
          "estimated_prompt_tokens",
          "prompt_tokens",
          "completion_tokens",
          "total_tokens"
        ])
      end
    end)
  end

  defp on_error_outcome(config) do
    case get_in(config, ["delivery", "on_error"]) || get_in(config, ["delivery", "on_full"]) do
      "fail_closed" -> "failed_closed"
      "drop" -> "dropped"
      _ -> "dead_lettered"
    end
  end

  defp publish_delivery_telemetry(config, result, duration) do
    :telemetry.execute(
      [:wardwright, :sinks, :delivery],
      %{count: 1, duration: duration},
      %{
        kind: config["kind"],
        outcome: result["outcome"],
        sink_id: result["sink_id"]
      }
    )
  end

  defp publish_queue_depth(config, depth) do
    capacity = get_in(config, ["delivery", "capacity"])

    :telemetry.execute(
      [:wardwright, :sinks, :queue_depth],
      %{
        capacity: capacity || 0,
        depth: depth,
        utilization: queue_utilization(depth, capacity)
      },
      %{kind: config["kind"], sink_id: config["id"]}
    )
  end

  defp queue_utilization(depth, capacity) when is_integer(capacity) and capacity > 0, do: depth / capacity

  defp queue_utilization(_depth, _capacity), do: 0.0

  defp publish_receipt_usage_telemetry(%{"type" => "receipt.finalized"} = event) do
    :telemetry.execute(
      [:wardwright, :model, :usage],
      %{
        completion_tokens: integer_payload_value(event, "completion_tokens"),
        count: 1,
        estimated_prompt_tokens: integer_payload_value(event, "estimated_prompt_tokens"),
        prompt_tokens: integer_payload_value(event, "prompt_tokens"),
        total_tokens: integer_payload_value(event, "total_tokens")
      },
      %{
        selected_model: payload_value(event, "selected_model"),
        selected_provider: payload_value(event, "selected_provider"),
        simulation: payload_value(event, "simulation"),
        status: payload_value(event, "status")
      }
    )
  end

  defp publish_receipt_usage_telemetry(_event), do: :ok

  defp integer_payload_value(event, key) do
    case payload_value(event, key) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end

  defp publish_policy_alert_delivery(%{config: %{"kind" => "memory_alert"}} = sink_state, result) do
    if Process.whereis(Wardwright.PubSub) do
      Events.publish(Events.topic(:policies), %{
        "capacity" => get_in(sink_state.config, ["delivery", "capacity"]),
        "created_at" => System.system_time(:second),
        "idempotency_key" => result["idempotency_key"],
        "outcome" => result["outcome"],
        "queue_depth" => length(sink_state.queue),
        "rule_id" => result["rule_id"],
        "sink_id" => result["sink_id"],
        "type" => "policy_alert.delivery"
      })
    end
  end

  defp publish_policy_alert_delivery(_sink_state, _result), do: :ok

  defp normalize_sink(config) when is_map(config) do
    kind = config |> Map.get("kind", "") |> to_string() |> String.trim()
    id = config |> Map.get("id", default_sink_id(kind)) |> to_string() |> String.trim()

    if !(id == "" or kind not in @supported_sink_kinds) do
      %{
        "delivery" => normalize_delivery(Map.get(config, "delivery", %{}), kind),
        "id" => id,
        "kind" => kind,
        "redaction" => normalize_redaction(Map.get(config, "redaction", "metadata")),
        "select" => normalize_select(Map.get(config, "select", %{}), kind)
      }
    end
  end

  defp normalize_sink(_), do: nil

  defp apply_legacy_alert_delivery(sinks, alert_delivery_config) do
    legacy_sink = legacy_alert_sink(alert_delivery_config)
    default_delivery = normalize_alert_delivery(%{})

    if legacy_sink["delivery"] == default_delivery do
      sinks
    else
      apply_legacy_alert_delivery_override(sinks, legacy_sink)
    end
  end

  defp apply_legacy_alert_delivery_override(sinks, legacy_sink) do
    Enum.map(sinks, fn
      %{"id" => "policy-alerts", "kind" => "memory_alert"} = sink ->
        Map.put(sink, "delivery", legacy_sink["delivery"])

      sink ->
        sink
    end)
  end

  defp normalize_select(select, kind) when is_map(select) do
    types =
      select
      |> Map.get("types", default_types(kind))
      |> List.wrap()
      |> Enum.map(&(to_string(&1) |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    %{"types" => if(types == [], do: default_types(kind), else: types)}
  end

  defp normalize_select(_select, kind), do: %{"types" => default_types(kind)}

  defp normalize_delivery(config, "memory_alert"), do: normalize_alert_delivery(config)

  defp normalize_delivery(config, kind) when is_map(config) do
    config
    |> Map.take(["path", "url", "timeout_ms", "on_error"])
    |> Map.update("timeout_ms", @default_timeout_ms, &positive_integer(&1, @default_timeout_ms))
    |> Map.update("on_error", "dead_letter", &normalize_on_error/1)
    |> then(fn delivery ->
      case kind do
        "jsonl_file" -> Map.update(delivery, "path", "", &string_value/1)
        "webhook" -> Map.update(delivery, "url", "", &string_value/1)
        _ -> delivery
      end
    end)
  end

  defp normalize_delivery(_config, kind), do: normalize_delivery(%{}, kind)

  defp normalize_alert_delivery(config) when is_map(config) do
    %{
      "capacity" => non_negative_integer(Map.get(config, "capacity"), 16),
      "on_full" =>
        case Map.get(config, "on_full") do
          value when value in ["drop", "dead_letter", "fail_closed"] -> value
          _ -> "dead_letter"
        end
    }
  end

  defp normalize_alert_delivery(_), do: %{"capacity" => 16, "on_full" => "dead_letter"}

  defp normalize_redaction("full"), do: "full"
  defp normalize_redaction(_), do: "metadata"

  defp normalize_on_error("fail_closed"), do: "fail_closed"
  defp normalize_on_error("drop"), do: "drop"
  defp normalize_on_error(_), do: "dead_letter"

  defp default_types("memory_alert"), do: ["policy.alert"]
  defp default_types("jsonl_file"), do: ["policy.*", "receipt.finalized"]
  defp default_types("webhook"), do: ["policy.alert"]
  defp default_types(_), do: []

  defp default_sink_id("memory_alert"), do: "policy-alerts"
  defp default_sink_id(kind), do: kind

  defp history_limit(config),
    do: positive_integer(get_in(config, ["delivery", "history_limit"]), @default_history_limit)

  defp non_negative_integer(value, default) do
    case integer_value(value) do
      value when is_integer(value) and value >= 0 -> value
      _ -> default
    end
  end

  defp positive_integer(value, default) do
    case integer_value(value) do
      value when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer_value(_), do: nil

  defp string_value(nil), do: ""
  defp string_value(value) when is_binary(value), do: String.trim(value)
  defp string_value(value), do: value |> to_string() |> String.trim()
end
