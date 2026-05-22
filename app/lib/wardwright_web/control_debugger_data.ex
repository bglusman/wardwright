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

  def default_pattern_id_for_example("read-before-edit"), do: "tool-governance"
  def default_pattern_id_for_example("output-contract"), do: "ambiguous-success"
  def default_pattern_id_for_example(_example_id), do: default_pattern_id()

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
        {"Runtime", "deterministic replay/fork and live model continuation available"},
        {"Transcript store", store_location(health)},
        {"Default capture", if(health["default_enabled"] == true, do: "enabled", else: "off; opt in per model")},
        {"Durability", capability_summary(health)},
        {"Read/write health", "#{health["read_health"] || "unknown"} / #{health["write_health"] || "unknown"}"}
      ]
    else
      [{"Runtime", "contract only; replay/fork runtime not loaded"}]
    end
  end

  def counterfactual_example_options do
    [
      {"read-before-edit", "Read before edit", "tool-order failure"},
      {"output-contract", "Output contract", "malformed response repair"}
    ]
  end

  def default_counterfactual_example_id, do: "read-before-edit"

  def default_policy_overlay_json do
    default_policy_overlay_json_for_example(default_counterfactual_example_id())
  end

  def default_policy_overlay_json_for_example(example_id) do
    example_id
    |> counterfactual_example()
    |> Map.get("policy_overlay")
    |> Wardwright.Json.encode_display!()
  end

  def model_options do
    Wardwright.externally_callable_model_configs()
    |> Enum.map(fn config ->
      model_id = config["model_id"] || ""
      target_count = config |> Map.get("targets", []) |> length()
      access = if(Wardwright.model_requires_api_key?(config), do: "keyed", else: "open")

      {
        model_id,
        "#{model_id} - #{access} - #{target_count} target(s)"
      }
    end)
  end

  def default_live_model_id do
    model_options()
    |> List.first()
    |> case do
      nil -> ""
      {model_id, _label} -> model_id
    end
  end

  def harness_adapter_options do
    WardwrightWeb.AgentHarnessAdapters.list()
    |> Enum.map(fn adapter ->
      {
        adapter["id"] || "",
        adapter["label"] || adapter["id"] || "",
        adapter["fidelity"] || "unknown",
        adapter["status"] || "unknown"
      }
    end)
  end

  def default_harness_adapter_id, do: "opencode"

  def export_harness_trace(session_id, adapter_id) do
    session_id = session_id |> to_string() |> String.trim()
    adapter_id = adapter_id |> to_string() |> String.trim() |> blank_fallback(default_harness_adapter_id())

    with {:inputs, false} <- {:inputs, session_id == ""},
         {:ok, export} <- WardwrightWeb.AgentHarnessAdapters.write_export(session_id, adapter_id) do
      adapter = export["adapter"] || %{}
      commands = export["commands"] || []
      warnings = export["warnings"] || []
      saved_files = export["saved_files"] || []
      command = harness_export_command(export, saved_files)

      {true, "Prepared #{adapter["label"] || adapter_id} trace handoff and saved #{length(saved_files)} file(s).",
       [
         {"Adapter", adapter["label"] || adapter_id},
         {"Fidelity", adapter["fidelity"] || "unknown"},
         {"Equivalent agent resume", bool_text(adapter["equivalent_agent_resume"])},
         {"Artifact", export["artifact_format"] || "unknown"},
         {"Saved file", saved_files |> List.first() |> blank_fallback("none")},
         {"Command", command |> blank_fallback(commands |> List.first() |> blank_fallback("none"))},
         {"Warnings", warnings |> Enum.join(" ") |> blank_fallback("none")}
       ]}
    else
      {:inputs, true} ->
        {false, "Load a session trace before exporting to an agent harness.", []}

      {:error, message} ->
        {false, "Could not export trace: #{message}", []}
    end
  end

  def run_counterfactual_demo do
    run_counterfactual_example(default_counterfactual_example_id())
  end

  defp harness_export_command(%{"adapter" => %{"id" => "opencode"}}, [path | _]) when is_binary(path) do
    "opencode import #{shell_quote(path)}"
  end

  defp harness_export_command(_export, _saved_files), do: ""

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end

  def run_counterfactual_example(example_id) do
    scenario = counterfactual_example(example_id)

    with {:ok, original} <- WardwrightWeb.CounterfactualReplay.run_recorded_session(scenario),
         session_id when is_binary(session_id) <- original["session_id"],
         {:ok, transcript} <- WardwrightWeb.CounterfactualReplay.transcript(session_id),
         {:ok, fork_event} <- find_suggested_fork_event(transcript["events"]),
         fork_cursor when is_binary(fork_cursor) <- fork_event["cursor"],
         {:ok, replay} <- WardwrightWeb.CounterfactualReplay.replay_until(session_id, fork_cursor),
         {:ok, fork} <-
           WardwrightWeb.CounterfactualReplay.fork(%{
             "fork_cursor" => fork_cursor,
             "policy_overlay" => scenario["policy_overlay"] || %{},
             "source_session_id" => session_id
           }),
         fork_session_id when is_binary(fork_session_id) <- fork["fork_session_id"],
         {:ok, fixed} <-
           WardwrightWeb.CounterfactualReplay.continue(fork_session_id, %{
             "runner" => "scripted_agent",
             "script_id" => get_in(scenario, ["fork_runner", "script_id"]) || scenario["debugger_example_id"]
           }),
         {:ok, comparison} <- WardwrightWeb.CounterfactualReplay.compare(session_id, fork_session_id),
         {:ok, storage} <- WardwrightWeb.CounterfactualReplay.transcript_store_health() do
      receipt_id =
        case get_in(original, ["gateway", "receipt_ids"]) do
          [id | _] when is_binary(id) -> id
          _ -> "missing"
        end

      {true, "Recorded scripted example session.", receipt_id,
       [
         {"Example", scenario["title"] || scenario["debugger_example_id"] || "unknown"},
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
      {:error, message} -> {false, "Could not record example session: #{message}", "", []}
      nil -> {false, "Could not record example session: missing transcript field.", "", []}
      _other -> {false, "Could not record example session.", "", []}
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

      {true, "Loaded #{length(events)} trace event(s) for #{receipt_id}.", session_id, fork_point,
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
    fork_and_continue_from_point(session_id, fork_point, overlay_json, "scripted_agent", "")
  end

  def fork_and_continue_from_point(session_id, fork_point, overlay_json, continuation_mode, live_model_id) do
    fork_and_continue_from_point(session_id, fork_point, overlay_json, continuation_mode, live_model_id, "")
  end

  def fork_and_continue_from_point(
        session_id,
        fork_point,
        overlay_json,
        continuation_mode,
        live_model_id,
        model_api_key
      ) do
    session_id = session_id |> to_string() |> String.trim()
    fork_point = fork_point |> to_string() |> String.trim()
    continuation_mode = continuation_mode |> to_string() |> String.trim() |> blank_fallback("scripted_agent")
    live_model_id = live_model_id |> to_string() |> String.trim()
    model_api_key = model_api_key |> to_string() |> String.trim()

    with {:inputs, false} <- {:inputs, session_id == "" or fork_point == ""},
         {:mode, true} <- {:mode, continuation_mode in ["scripted_agent", "wardwright_model"]},
         {:live_model, true} <- {:live_model, continuation_mode != "wardwright_model" or live_model_id != ""},
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
             "model_api_key" => model_api_key,
             "model_id" => live_model_id,
             "runner" => continuation_mode,
             "script_id" => "read-settings-then-edit"
           }),
         {:ok, comparison} <- WardwrightWeb.CounterfactualReplay.compare(session_id, fork_session_id) do
      {true, continuation_success_message(continuation_mode),
       [
         {"Original session", session_id},
         {"Fork point", fork_point},
         {"Fork session", fork_session_id},
         {"Continuation", continuation_summary(fixed)},
         {"Fork status", fixed["status"] || "unknown"},
         {"Provider called", bool_text(fixed["provider_called"])},
         {"Live receipt", fixed |> get_in(["gateway", "receipt_ids"]) |> receipt_ids_summary()},
         {"Comparison accepted", bool_text(comparison["accepted"])},
         {"Applied rules", applied_rule_summary(comparison)}
       ]}
    else
      {:inputs, true} ->
        {false, "Load a transcript and choose a fork point first.", []}

      {:mode, false} ->
        {false, "Choose deterministic or live model continuation.", []}

      {:live_model, false} ->
        {false, "Choose a Wardwright model for live continuation.", []}

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

  defp continuation_success_message("wardwright_model"),
    do: "Forked from selected point, applied policy overlay, and continued through a Wardwright model."

  defp continuation_success_message(_mode), do: "Forked from selected point, applied policy overlay, and continued."

  defp continuation_summary(%{"runner" => %{"kind" => "wardwright_model", "model_id" => model_id}}),
    do: "live Wardwright model #{model_id}"

  defp continuation_summary(%{"runner" => %{"kind" => kind}}), do: kind
  defp continuation_summary(_fixed), do: "unknown"

  defp receipt_ids_summary([id | _]) when is_binary(id), do: id
  defp receipt_ids_summary(_ids), do: "none"

  defp read_before_edit_overlay do
    %{
      "allowed_tools_until_read" => ["list_files", "read_file"],
      "id" => "read-before-edit",
      "phase" => "tool.planning",
      "requires_prior_read_for" => ["edit_file"]
    }
  end

  defp output_contract_overlay do
    %{
      "id" => "result-json-contract",
      "output_contract" => %{
        "format" => "json_object",
        "on_violation" => "retry",
        "required_keys" => ["answer", "confidence"]
      },
      "phase" => "response.validation"
    }
  end

  defp decode_policy_overlay(json) do
    json = json |> to_string() |> String.trim()

    case json do
      "" ->
        {:error, "Policy overlay must not be empty."}

      _ ->
        with {:json, {:ok, overlay}} when is_map(overlay) <- {:json, JSON.decode(json)},
             :ok <- validate_policy_overlay(overlay) do
          {:ok, overlay}
        else
          {:json, {:ok, _not_map}} ->
            {:error, "Policy overlay must be a JSON object."}

          {:json, {:error, reason}} ->
            {:error, "Policy overlay JSON is invalid: #{Wardwright.Json.decode_error_message(reason)}"}

          {:error, message} when is_binary(message) ->
            {:error, message}
        end
    end
  end

  defp validate_policy_overlay(overlay) do
    cond do
      not valid_nonempty_string?(overlay["id"]) ->
        {:error, "Policy overlay must include a non-empty string id."}

      Map.has_key?(overlay, "requires_prior_read_for") and
          not valid_nonempty_string_list?(overlay["requires_prior_read_for"]) ->
        {:error, "Policy overlay requires_prior_read_for must be a non-empty string list when present."}

      not valid_optional_string_list?(overlay["allowed_tools_until_read"]) ->
        {:error, "Policy overlay allowed_tools_until_read must be a string list when present."}

      Map.has_key?(overlay, "output_contract") and not is_map(overlay["output_contract"]) ->
        {:error, "Policy overlay output_contract must be an object when present."}

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

  defp find_suggested_fork_event(events) when is_list(events) do
    events
    |> Enum.find(&suggested_fork_event?/1)
    |> case do
      nil -> {:error, "example transcript did not include a suggested fork point"}
      event -> {:ok, event}
    end
  end

  defp find_suggested_fork_event(_events), do: {:error, "example transcript did not include events"}

  defp suggested_fork_event?(%{"fork_point" => true}), do: true

  defp suggested_fork_event?(%{"type" => "tool.call"} = event) do
    get_in(event, ["tool", "name"]) == "edit_file"
  end

  defp suggested_fork_event?(%{"failure_class" => failure_class}) when is_binary(failure_class) and failure_class != "",
    do: true

  defp suggested_fork_event?(_event), do: false

  defp receipt_session_id(receipt) do
    get_in(receipt, ["caller", "session_id", "value"]) ||
      get_in(receipt, ["caller", "run_id", "value"]) ||
      receipt["run_id"] ||
      get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "session_id"]) ||
      get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "run_id"])
  end

  defp suggested_fork_point(events) do
    events
    |> Enum.find(&suggested_fork_event?/1)
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
  defp event_label(%{"type" => "model.response"}), do: "Model response"
  defp event_label(%{"type" => "policy.decision"}), do: "Policy decision"
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

  defp event_detail(%{"type" => "model.response"} = event) do
    "response: #{event["content_preview"] || event["content"] || "recorded"}"
  end

  defp event_detail(%{"type" => "policy.decision"} = event) do
    "decision: #{event["status"] || "unknown"} / #{event["failure_class"] || "no failure class"}"
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

  defp fork_point_recommendation(%{"fork_point" => true, "type" => "model.response"}),
    do: "Suggested fork point: before the response is validated or repaired."

  defp fork_point_recommendation(%{"failure_class" => failure_class, "type" => "policy.decision"})
       when is_binary(failure_class) and failure_class != "",
       do: "Evidence event; usually fork before the response or action that triggered it."

  defp fork_point_recommendation(%{"type" => "tool.result"}),
    do: "Evidence event; usually fork before the matching call."

  defp fork_point_recommendation(_event), do: "Context event."

  defp compact_json(value) do
    value
    |> JSON.encode!()
    |> String.slice(0, 180)
  end

  defp counterfactual_example("output-contract") do
    %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "debugger_example_id" => "output-contract",
      "entrypoint" => %{
        "path" => "/v1/chat/completions",
        "surface" => "openai_compatible_gateway"
      },
      "expected" => %{
        "failure_class" => "output_contract_violation",
        "fork_status" => "passed",
        "original_status" => "failed"
      },
      "fork_runner" => %{"script_id" => "valid-json-response"},
      "model_id" => "counterfactual-output-contract",
      "model_version" => "acceptance-v0",
      "policy_overlay" => output_contract_overlay(),
      "task" => "Answer the search request as JSON with answer and confidence fields.",
      "title" => "Output contract repair",
      "vcr" => %{"mode" => "full_session"},
      "workspace" => %{}
    }
  end

  defp counterfactual_example(_example_id) do
    %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "debugger_example_id" => "read-before-edit",
      "entrypoint" => %{
        "path" => "/v1/chat/completions",
        "surface" => "openai_compatible_gateway"
      },
      "expected" => %{
        "failure_class" => "read_before_edit_violation",
        "fork_status" => "passed",
        "original_status" => "failed"
      },
      "fork_runner" => %{"script_id" => "read-settings-then-edit"},
      "model_id" => "counterfactual-ui-demo",
      "model_version" => "acceptance-v0",
      "policy_overlay" => read_before_edit_overlay(),
      "task" => "Enable the feature flag. Read the relevant file before editing.",
      "title" => "Read before edit",
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
