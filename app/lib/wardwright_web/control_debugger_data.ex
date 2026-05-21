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

  def default_policy_overlay_json do
    read_before_edit_overlay()
    |> Jason.encode!(pretty: true)
  end

  def run_counterfactual_demo do
    scenario = counterfactual_demo_scenario()

    with {:ok, original} <- WardwrightWeb.CounterfactualReplay.run_recorded_session(scenario),
         session_id when is_binary(session_id) <- original["session_id"],
         {:ok, transcript} <- WardwrightWeb.CounterfactualReplay.transcript(session_id),
         {:ok, bad_edit} <- find_bad_edit(transcript["events"]),
         fork_cursor when is_binary(fork_cursor) <- bad_edit["cursor"],
         {:ok, replay} <- WardwrightWeb.CounterfactualReplay.replay_until(session_id, fork_cursor),
         {:ok, fork} <-
           WardwrightWeb.CounterfactualReplay.fork(%{
             "fork_cursor" => fork_cursor,
             "policy_overlay" => read_before_edit_overlay(),
             "source_session_id" => session_id
           }),
         fork_session_id when is_binary(fork_session_id) <- fork["fork_session_id"],
         {:ok, fixed} <-
           WardwrightWeb.CounterfactualReplay.continue(fork_session_id, %{
             "runner" => "scripted_agent",
             "script_id" => "read-settings-then-edit"
           }),
         {:ok, comparison} <- WardwrightWeb.CounterfactualReplay.compare(session_id, fork_session_id),
         {:ok, storage} <- WardwrightWeb.CounterfactualReplay.transcript_store_health() do
      receipt_id =
        case get_in(original, ["gateway", "receipt_ids"]) do
          [id | _] when is_binary(id) -> id
          _ -> "missing"
        end

      {true, "Ran deterministic counterfactual demo.", receipt_id,
       [
         {"Original session", session_id},
         {"Receipt", receipt_id},
         {"Fork cursor", fork_cursor},
         {"Replay provider call", bool_text(replay["provider_called"])},
         {"Fork session", fork_session_id},
         {"Original status", original["status"] || "unknown"},
         {"Fork status", fixed["status"] || "unknown"},
         {"Comparison accepted", bool_text(comparison["accepted"])},
         {"Applied rules", applied_rule_summary(comparison)},
         {"Transcript store", store_location(storage)}
       ]}
    else
      {:error, message} -> {false, "Could not run counterfactual demo: #{message}", "", []}
      nil -> {false, "Could not run counterfactual demo: missing transcript field.", "", []}
      _other -> {false, "Could not run counterfactual demo.", "", []}
    end
  end

  def load_transcript_for_receipt(receipt_id) do
    receipt_id = receipt_id |> to_string() |> String.trim()

    with {:receipt_id, false} <- {:receipt_id, receipt_id == ""},
         {:receipt, receipt} when is_map(receipt) <- {:receipt, Wardwright.ReceiptStore.get(receipt_id)},
         {:session_id, session_id} when is_binary(session_id) and session_id != "" <-
           {:session_id, receipt_session_id(receipt)},
         {:ok, transcript} <- WardwrightWeb.CounterfactualReplay.transcript(session_id),
         events when is_list(events) <- transcript["events"] do
      fork_point = suggested_fork_point(events)

      {true, "Loaded #{length(events)} transcript event(s) for #{receipt_id}.", session_id, fork_point,
       Enum.map(events, &transcript_event_summary/1)}
    else
      {:receipt_id, true} ->
        {false, "Choose a receipt with a full-session transcript.", "", "", []}

      {:receipt, _} ->
        {false, "Could not find receipt #{receipt_id}.", "", "", []}

      {:session_id, _} ->
        {false, "Receipt #{receipt_id} does not point to a transcript session.", "", "", []}

      {:error, message} ->
        {false, "Could not load transcript: #{message}", "", "", []}

      _other ->
        {false, "Could not load transcript for #{receipt_id}.", "", "", []}
    end
  end

  def replay_to_fork_point(session_id, fork_point) do
    session_id = session_id |> to_string() |> String.trim()
    fork_point = fork_point |> to_string() |> String.trim()

    with {:inputs, false} <- {:inputs, session_id == "" or fork_point == ""},
         {:ok, replay} <- WardwrightWeb.CounterfactualReplay.replay_until(session_id, fork_point) do
      {true, "Replayed to selected fork point without calling a provider.",
       [
         {"Session", replay["session_id"] || session_id},
         {"Fork point", replay["next_event_cursor"] || fork_point},
         {"Events replayed", replay |> Map.get("events", []) |> length() |> to_string()},
         {"Provider called", bool_text(replay["provider_called"])}
       ]}
    else
      {:inputs, true} ->
        {false, "Load a transcript and choose a fork point first.", []}

      {:error, message} ->
        {false, "Could not replay to fork point: #{message}", []}
    end
  end

  def fork_and_continue_from_point(session_id, fork_point, overlay_json) do
    session_id = session_id |> to_string() |> String.trim()
    fork_point = fork_point |> to_string() |> String.trim()

    with {:inputs, false} <- {:inputs, session_id == "" or fork_point == ""},
         {:ok, overlay} <- decode_policy_overlay(overlay_json),
         {:ok, fork} <-
           WardwrightWeb.CounterfactualReplay.fork(%{
             "fork_cursor" => fork_point,
             "policy_overlay" => overlay,
             "source_session_id" => session_id
           }),
         fork_session_id when is_binary(fork_session_id) <- fork["fork_session_id"],
         {:ok, fixed} <-
           WardwrightWeb.CounterfactualReplay.continue(fork_session_id, %{
             "runner" => "scripted_agent",
             "script_id" => "read-settings-then-edit"
           }),
         {:ok, comparison} <- WardwrightWeb.CounterfactualReplay.compare(session_id, fork_session_id) do
      {true, "Forked from selected point, applied policy overlay, and continued.",
       [
         {"Original session", session_id},
         {"Fork point", fork_point},
         {"Fork session", fork_session_id},
         {"Fork status", fixed["status"] || "unknown"},
         {"Comparison accepted", bool_text(comparison["accepted"])},
         {"Applied rules", applied_rule_summary(comparison)}
       ]}
    else
      {:inputs, true} ->
        {false, "Load a transcript and choose a fork point first.", []}

      {:error, message} ->
        {false, "Could not fork from selected point: #{message}", []}

      _other ->
        {false, "Could not fork from selected point.", []}
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

  defp applied_rule_summary(comparison) do
    case get_in(comparison, ["policy_delta", "applied_rule_ids"]) do
      ids when is_list(ids) -> ids |> Enum.join(", ") |> blank_fallback("none")
      _ -> "none"
    end
  end

  defp read_before_edit_overlay do
    %{
      "allowed_tools_until_read" => ["list_files", "read_file"],
      "id" => "read-before-edit",
      "phase" => "tool.planning",
      "requires_prior_read_for" => ["edit_file"]
    }
  end

  defp decode_policy_overlay(json) do
    json = json |> to_string() |> String.trim() |> blank_fallback(default_policy_overlay_json())

    with {:ok, overlay} when is_map(overlay) <- Jason.decode(json),
         :ok <- validate_policy_overlay(overlay) do
      {:ok, overlay}
    else
      {:ok, _not_map} -> {:error, "Policy overlay must be a JSON object."}
      {:error, %Jason.DecodeError{} = error} -> {:error, "Policy overlay JSON is invalid: #{Exception.message(error)}"}
      {:error, message} when is_binary(message) -> {:error, message}
    end
  end

  defp validate_policy_overlay(overlay) do
    cond do
      not valid_nonempty_string?(overlay["id"]) ->
        {:error, "Policy overlay must include a non-empty string id."}

      not valid_nonempty_string_list?(overlay["requires_prior_read_for"]) ->
        {:error, "Policy overlay must include requires_prior_read_for as a non-empty string list."}

      not valid_optional_string_list?(overlay["allowed_tools_until_read"]) ->
        {:error, "Policy overlay allowed_tools_until_read must be a string list when present."}

      true ->
        :ok
    end
  end

  defp valid_nonempty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp valid_nonempty_string_list?(value) when is_list(value) and value != [],
    do: Enum.all?(value, &valid_nonempty_string?/1)

  defp valid_nonempty_string_list?(_value), do: false

  defp valid_string_list?(value) when is_list(value), do: Enum.all?(value, &valid_nonempty_string?/1)
  defp valid_string_list?(_value), do: false

  defp valid_optional_string_list?(nil), do: true
  defp valid_optional_string_list?(value), do: valid_string_list?(value)

  defp find_bad_edit(events) when is_list(events) do
    events
    |> Enum.find(fn event ->
      event["type"] == "tool.call" and
        get_in(event, ["tool", "name"]) == "edit_file" and
        get_in(event, ["tool", "args", "path"]) == "app.txt"
    end)
    |> case do
      nil -> {:error, "demo transcript did not include the unsafe edit"}
      event -> {:ok, event}
    end
  end

  defp find_bad_edit(_events), do: {:error, "demo transcript did not include events"}

  defp receipt_session_id(receipt) do
    receipt["run_id"] ||
      get_in(receipt, ["caller", "session_id", "value"]) ||
      get_in(receipt, ["caller", "run_id", "value"]) ||
      get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "session_id"]) ||
      get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "run_id"])
  end

  defp suggested_fork_point(events) do
    events
    |> Enum.find(fn event ->
      event["type"] == "tool.call" and
        get_in(event, ["tool", "name"]) == "edit_file"
    end)
    |> case do
      %{"cursor" => cursor} when is_binary(cursor) -> cursor
      _ -> ""
    end
  end

  defp transcript_event_summary(event) when is_map(event) do
    cursor = event["cursor"] || ""
    sequence = event["sequence"] |> to_string()
    type = event["type"] || "event"
    label = event_label(event)
    detail = event_detail(event)
    recommendation = fork_point_recommendation(event)

    {cursor, sequence, type, label, detail, recommendation}
  end

  defp event_label(%{"type" => "tool.call"} = event) do
    tool_name = get_in(event, ["tool", "name"]) || "tool"
    "Tool call: #{tool_name}"
  end

  defp event_label(%{"type" => "tool.result"} = event) do
    tool_name = get_in(event, ["tool", "name"]) || "tool"
    "Tool result: #{tool_name}"
  end

  defp event_label(%{"type" => "gateway.request"}), do: "Gateway request"
  defp event_label(%{"type" => "receipt.finalized"}), do: "Receipt finalized"
  defp event_label(%{"type" => "session.started"}), do: "Session started"
  defp event_label(%{"type" => "session.forked"}), do: "Session forked"
  defp event_label(%{"type" => type}) when is_binary(type), do: type
  defp event_label(_event), do: "Transcript event"

  defp event_detail(%{"type" => "tool.call"} = event) do
    args = get_in(event, ["tool", "args"]) || %{}
    path = args["path"]

    case path do
      path when is_binary(path) and path != "" -> "args: path=#{path}"
      _ -> "args: #{compact_json(args)}"
    end
  end

  defp event_detail(%{"type" => "tool.result"} = event) do
    result = get_in(event, ["tool", "result"]) || %{}
    status = result["status"] || result["failure_class"]

    case status do
      status when is_binary(status) and status != "" -> "result: #{status}"
      _ -> "result: #{compact_json(result)}"
    end
  end

  defp event_detail(%{"type" => "gateway.request"} = event) do
    "path: #{get_in(event, ["gateway", "path"]) || "unknown"}"
  end

  defp event_detail(%{"type" => "receipt.finalized"} = event) do
    "status: #{event["status"] || "unknown"}"
  end

  defp event_detail(%{"model_id" => model_id, "version" => version}) do
    "model: #{model_id || "unknown"} / #{version || "unknown"}"
  end

  defp event_detail(event), do: compact_json(Map.drop(event, ["schema", "cursor", "sequence", "session_id", "type"]))

  defp fork_point_recommendation(%{"type" => "tool.call"} = event) do
    tool_name = get_in(event, ["tool", "name"]) || ""
    args = get_in(event, ["tool", "args"]) || %{}

    cond do
      tool_name == "edit_file" -> "Suggested fork point: before mutating #{args["path"] || "a file"}."
      tool_name == "run_tests" -> "Possible fork point: before validation."
      true -> "Can fork before this tool call."
    end
  end

  defp fork_point_recommendation(%{"type" => "tool.result"}),
    do: "Evidence event; usually fork before the matching call."

  defp fork_point_recommendation(_event), do: "Context event."

  defp compact_json(value) do
    value
    |> Jason.encode!()
    |> String.slice(0, 180)
  end

  defp counterfactual_demo_scenario do
    %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "entrypoint" => %{
        "path" => "/v1/chat/completions",
        "surface" => "openai_compatible_gateway"
      },
      "model_id" => "counterfactual-ui-demo",
      "model_version" => "acceptance-v0",
      "task" => "Enable the feature flag. Read the relevant file before editing.",
      "vcr" => %{"mode" => "full_session"},
      "workspace" => %{
        "README.md" => "Change the feature flag described in settings.json.",
        "app.txt" => "Tempting wrong file; editing this should not satisfy the task.",
        "settings.json" => ~s({"feature_enabled": false})
      }
    }
  end

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
