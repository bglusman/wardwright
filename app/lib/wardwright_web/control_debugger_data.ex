defmodule WardwrightWeb.ControlDebuggerData do
  @moduledoc false

  def pattern_options do
    Wardwright.PolicyProjection.patterns()
    |> Enum.map(fn pattern ->
      {
        pattern["id"] || "",
        pattern["title"] || pattern["id"] || "",
        pattern["category"] || "",
        pattern["promise"] || ""
      }
    end)
  end

  def default_pattern_id do
    pattern_options()
    |> List.first()
    |> case do
      nil -> "tts-retry"
      {pattern_id, _title, _category, _promise} -> pattern_id
    end
  end

  def receipt_options do
    %{}
    |> Wardwright.ReceiptStore.list(25)
    |> Enum.map(fn receipt ->
      receipt_id = receipt["receipt_id"] || ""
      status = receipt["status"] || "unknown"
      model_id = receipt["model_id"] || "unknown model"
      redaction = get_in(receipt, ["vcr", "redaction"]) || "legacy"

      {
        receipt_id,
        "#{receipt_id} - #{status} - #{redaction}",
        model_id,
        status
      }
    end)
  end

  def default_receipt_id do
    receipt_options()
    |> List.first()
    |> case do
      nil -> ""
      {receipt_id, _label, _model_id, _status} -> receipt_id
    end
  end

  def storage_note do
    "Receipts: #{store_location(Wardwright.ReceiptStore.health())}. Simulator cases: #{store_location(Wardwright.PolicyScenarioStore.health())}."
  end

  def counterfactual_facts do
    if Code.ensure_loaded?(WardwrightWeb.CounterfactualReplay) and
         function_exported?(WardwrightWeb.CounterfactualReplay, :transcript_store_health, 0) do
      {:ok, health} = WardwrightWeb.CounterfactualReplay.transcript_store_health()

      [
        {"Runtime", "deterministic replay/fork contract available"},
        {"Transcript store", store_location(health)},
        {"Default capture", if(health["default_enabled"] == true, do: "enabled", else: "off; opt in per model")},
        {"Durability", capability_summary(health)},
        {"Read/write health", "#{health["read_health"] || "unknown"} / #{health["write_health"] || "unknown"}"}
      ]
    else
      [{"Runtime", "contract only; replay/fork runtime not loaded"}]
    end
  end

  def import_receipt_scenario(pattern_id, receipt_id, title) do
    pattern_id = blank_fallback(pattern_id, default_pattern_id())
    receipt_id = receipt_id |> to_string() |> String.trim()
    title = title |> to_string() |> String.trim()

    if receipt_id == "" do
      {false, "Choose a receipt to import.", ""}
    else
      case Wardwright.ReceiptStore.get(receipt_id) do
        nil ->
          {false, "Could not find receipt #{receipt_id}.", ""}

        receipt ->
          attrs =
            %{"pinned" => true, "title" => title}
            |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
            |> Map.new()

          case Wardwright.PolicyScenarioStore.create_from_receipt(pattern_id, receipt, attrs) do
            {:ok, scenario} ->
              fixture_id = "saved:#{scenario.id}"
              scenario_store = store_location(Wardwright.PolicyScenarioStore.health())

              {true,
               "Saved #{scenario.title} as #{fixture_id}. Stored in simulator case store: #{scenario_store}. Open Workbench, choose #{pattern_id}, then choose the saved scenario.",
               fixture_id}

            {:error, message} ->
              {false, "Could not import receipt: #{message}", ""}
          end
      end
    end
  end

  def replay_receipt(receipt_id) do
    receipt_id = receipt_id |> to_string() |> String.trim()

    if receipt_id == "" do
      {false, "Choose a receipt to replay.", []}
    else
      receipt = Wardwright.ReceiptStore.get(receipt_id)

      case receipt do
        nil ->
          {false, "Could not find receipt #{receipt_id}.", []}

        receipt ->
          replay_receipt(receipt_id, receipt)
      end
    end
  end

  defp replay_receipt(receipt_id, receipt) do
    case Wardwright.PolicyReplay.replay(receipt) do
      {:ok, replay} ->
        {
          true,
          "Explained #{receipt_id} from recorded VCR data. Replay did not call a provider.",
          replay_facts(replay, receipt)
        }

      {:error, message} ->
        {false, "Could not replay receipt: #{message}", []}
    end
  end

  defp replay_facts(replay, receipt) do
    [
      {"Replay mode", replay["mode"] || "unknown"},
      {"Recording", recording_summary(replay, receipt)},
      {"Receipt storage", store_location(Wardwright.ReceiptStore.health())},
      {"Original status", get_in(replay, ["final", "original_status"]) || "unknown"},
      {"Replay provider call", replay_provider_summary(replay)},
      {"Original provider", original_provider_summary(receipt)},
      {"Selected model", selected_model(replay)},
      {"Route", route_summary(replay)},
      {"Policy actions", policy_summary(replay)},
      {"Request shape", request_summary(replay)},
      {"Warnings", warnings_summary(replay)}
    ]
  end

  defp recording_summary(replay, receipt) do
    redaction = replay["redaction"] || get_in(receipt, ["vcr", "redaction"]) || "metadata_only"

    case redaction do
      "full_session" -> "full request/response payloads recorded"
      "metadata_only" -> "metadata only; prompt and completion text omitted"
      other -> other
    end
  end

  defp replay_provider_summary(replay) do
    provider_called = get_in(replay, ["final", "provider_called"])
    would_call_provider = get_in(replay, ["final", "would_call_provider"])

    "called=#{bool_text(provider_called)}; would_call=#{bool_text(would_call_provider)}"
  end

  defp original_provider_summary(receipt) do
    provider = get_in(receipt, ["vcr", "provider"]) || first_attempt(receipt)

    [
      "called=#{bool_text(provider["called_provider"])}",
      "mock=#{bool_text(provider["mock"])}",
      "status=#{provider["status"] || get_in(receipt, ["final", "status"]) || "unknown"}"
    ]
    |> Enum.join("; ")
  end

  defp first_attempt(receipt) do
    receipt
    |> Map.get("attempts", [])
    |> List.first()
    |> case do
      attempt when is_map(attempt) -> attempt
      _ -> %{}
    end
  end

  defp selected_model(replay) do
    get_in(replay, ["decision", "selected_model"]) ||
      get_in(replay, ["route", "selected_model"]) ||
      "unknown"
  end

  defp route_summary(replay) do
    route = replay["route"] || %{}
    route_id = route["route_id"] || "unknown route"
    route_type = route["route_type"] || "unknown type"

    "#{route_id} / #{route_type}"
  end

  defp policy_summary(replay) do
    policy = replay["policy"] || %{}
    actions = Map.get(policy, "actions", [])
    alert_count = Map.get(policy, "alert_count", 0) || 0

    "#{length(actions)} action(s); #{alert_count} alert(s)"
  end

  defp request_summary(replay) do
    request = replay["request"] || %{}
    count = Map.get(request, "message_count", 0) || 0
    roles = request |> Map.get("message_roles", []) |> Enum.join(",")
    lengths = request |> Map.get("message_content_lengths", []) |> Enum.map_join(",", &to_string/1)

    "#{count} message(s); roles=#{blank_fallback(roles, "unknown")}; lengths=#{blank_fallback(lengths, "unknown")}"
  end

  defp warnings_summary(replay) do
    replay
    |> Map.get("warnings", [])
    |> Enum.join("; ")
    |> blank_fallback("none")
  end

  defp bool_text(true), do: "yes"
  defp bool_text(false), do: "no"
  defp bool_text(_), do: "unknown"

  defp store_location(%{"kind" => "file", "path" => path}) when is_binary(path), do: "file #{path}"

  defp store_location(%{"kind" => "append_only_files", "path" => path}) when is_binary(path),
    do: "append-only files #{path}"

  defp store_location(%{"kind" => "memory"}), do: "memory only; not durable across restart"
  defp store_location(%{"kind" => kind}), do: kind
  defp store_location(_health), do: "unknown"

  defp capability_summary(%{"capabilities" => capabilities}) when is_map(capabilities) do
    [
      "durable=#{bool_text(capabilities["durable"])}",
      "parallel=#{bool_text(capabilities["concurrent_writers"])}",
      "global_writer=#{bool_text(capabilities["serialized_global_writer"])}"
    ]
    |> Enum.join("; ")
  end

  defp capability_summary(_health), do: "unknown"

  defp blank_fallback(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      value -> value
    end
  end

  defp blank_fallback(_value, fallback), do: fallback
end
