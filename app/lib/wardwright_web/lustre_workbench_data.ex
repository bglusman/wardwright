defmodule WardwrightWeb.LustreWorkbenchData do
  @moduledoc false

  def pattern_options do
    Enum.map(Wardwright.PolicyProjection.patterns(), fn pattern ->
      {
        pattern["id"] || "",
        pattern["title"] || pattern["id"] || "",
        pattern["category"] || "",
        pattern["promise"] || ""
      }
    end)
  end

  def model_options do
    Wardwright.model_summaries()
    |> Enum.map(fn model ->
      {
        model["id"] || "",
        model["description"] || "",
        model["route_type"] || "",
        if(model["requires_api_key"], do: "keyed", else: "unkeyed")
      }
    end)
  end

  def default_pattern_id do
    Wardwright.PolicyProjection.patterns()
    |> List.first()
    |> then(&((&1 && &1["id"]) || "tts-retry"))
  end

  def default_model_id do
    Wardwright.current_config()
    |> Wardwright.model_id()
  end

  def default_user_input(model_id) do
    model_id
    |> model_config()
    |> default_model_simulation_user_input()
  end

  def default_model_response(model_id) do
    model_id
    |> model_config()
    |> default_model_simulation_response()
  end

  def retry_response_slots(model_id) do
    model_id
    |> model_config()
    |> retry_response_slots_for_config()
  end

  def run_simulation(pattern_id, model_id, user_input, model_response) do
    run_simulation(pattern_id, model_id, user_input, model_response, [])
  end

  def run_simulation(pattern_id, model_id, user_input, model_response, response_attempts) do
    config = model_config(model_id)

    simulation =
      Wardwright.PolicyProjection.simulate_model_turn_with_attempts(
        user_input,
        model_response,
        normalize_response_attempts(response_attempts),
        config
      )

    receipt = Map.get(simulation, "receipt_preview", %{})
    stream = Map.get(receipt, "stream", %{})
    decision = Map.get(receipt, "decision", %{})
    model_received_input = model_received_input(receipt, user_input)
    user_received_output = user_received_output(stream, model_response)
    policy_actions = policy_actions(decision)
    trace_events = trace_events(simulation["trace"] || [])
    state_events = state_replay_events(pattern_id, simulation)

    {
      decision["selected_model"] || "",
      simulation["verdict"] || "",
      model_received_input,
      user_received_output,
      model_input_changed?(receipt),
      user_received_output != (model_response || ""),
      policy_actions,
      trace_events,
      state_events,
      config["model_id"] || model_id || "",
      config["version"] || ""
    }
  end

  defp model_config(model_id) when is_binary(model_id) do
    case Wardwright.model_config(model_id) do
      {:ok, config} -> config
      {:error, _message} -> Wardwright.current_config()
    end
  end

  defp model_config(_model_id), do: Wardwright.current_config()

  defp normalize_response_attempts(attempts) when is_list(attempts) do
    Enum.flat_map(attempts, fn
      {index, model_output} when is_integer(index) and is_binary(model_output) ->
        [%{"index" => index, "model_output" => model_output}]

      %{"index" => index} = attempt when is_integer(index) ->
        [attempt]

      _attempt ->
        []
    end)
  end

  defp normalize_response_attempts(_attempts), do: []

  defp retry_response_slots_for_config(config) do
    config
    |> retry_slot_candidates()
    |> Enum.max(fn -> 0 end)
  end

  defp retry_slot_candidates(config) do
    stream_retry_slots(config) ++ structured_output_retry_slots(config)
  end

  defp stream_retry_slots(config) do
    config
    |> Map.get("stream_rules", [])
    |> Enum.flat_map(fn
      %{"action" => action} = rule when action in ["retry", "retry_with_reminder"] ->
        [non_negative_integer(Map.get(rule, "max_retries"), 1)]

      _rule ->
        []
    end)
  end

  defp structured_output_retry_slots(config) do
    guard_loop = get_in(config, ["structured_output", "guard_loop"]) || %{}

    case Map.get(guard_loop, "on_violation", "retry_with_validation_feedback") do
      "retry_with_validation_feedback" ->
        max_attempts = non_negative_integer(Map.get(guard_loop, "max_attempts"), 0)
        [max(max_attempts - 1, 0)]

      _other ->
        []
    end
  end

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _parse_error -> default
    end
  end

  defp non_negative_integer(_value, default), do: default

  defp default_model_simulation_response(config) do
    config
    |> Map.get("stream_rules", [])
    |> Enum.find(&(Map.get(&1, "action") in ["rewrite_chunk", "rewrite_span", "replace"]))
    |> case do
      %{"regex" => regex} when is_binary(regex) ->
        default_model_response_for_match(regex)

      %{"contains" => contains} when is_binary(contains) ->
        default_model_response_for_match(contains)

      %{"pattern" => pattern} when is_binary(pattern) ->
        default_model_response_for_match(pattern)

      _rule ->
        "The model output contains text to test."
    end
  end

  defp default_model_response_for_match(match) do
    cond do
      String.contains?(String.downcase(match), "moo") ->
        "The model says moo in a draft answer."

      String.contains?(match, "acct_") ->
        "The model mentions acct_4938 in a draft answer."

      true ->
        "The model output contains text to test against #{match}."
    end
  end

  defp default_model_simulation_user_input(config) do
    config
    |> Map.get("governance", [])
    |> Enum.find(&request_transform_rule?/1)
    |> case do
      %{"contains" => contains} when is_binary(contains) and contains != "" ->
        "The user says #{contains} while asking for help."

      %{"match" => match} when is_binary(match) and match != "" ->
        "The user says #{match} while asking for help."

      _rule ->
        ""
    end
  end

  defp request_transform_rule?(%{"kind" => "request_transform"}), do: true
  defp request_transform_rule?(_rule), do: false

  defp model_received_input(%{"input" => %{"model_received_input" => value}}, _user_input) when is_binary(value),
    do: value

  defp model_received_input(_receipt, user_input), do: user_input || ""

  defp user_received_output(%{"released_to_consumer" => false}, _model_response), do: ""

  defp user_received_output(%{"final_output" => final_output}, _model_response) when is_binary(final_output),
    do: final_output

  defp user_received_output(%{"rewrites" => rewrites}, model_response) when is_list(rewrites) do
    Enum.reduce(rewrites, model_response || "", fn rewrite, output ->
      case rewrite do
        %{"match" => match, "replacement" => replacement}
        when is_binary(match) and is_binary(replacement) ->
          String.replace(output, match, replacement)

        %{"replacement" => replacement, "rule_id" => "account-redactor"}
        when is_binary(replacement) ->
          Regex.replace(~r/\bacct_[A-Za-z0-9_]+\b/, output, replacement)

        _ ->
          output
      end
    end)
  end

  defp user_received_output(_stream, model_response), do: model_response || ""

  defp model_input_changed?(%{"input" => %{"request_rewrites" => rewrites}}) when is_list(rewrites), do: rewrites != []

  defp model_input_changed?(%{"decision" => %{"policy_actions" => actions}}) when is_list(actions), do: actions != []

  defp model_input_changed?(_receipt), do: false

  defp policy_actions(%{"policy_actions" => actions}) when is_list(actions) do
    Enum.map(actions, fn action ->
      {
        action["rule_id"] || action["id"] || "",
        action["action"] || "",
        action["message"] || action["reminder"] || ""
      }
    end)
  end

  defp policy_actions(_decision), do: []

  defp trace_events(events) do
    Enum.map(events, fn event ->
      {
        event["phase"] || "",
        event["label"] || "",
        event["detail"] || "",
        event["severity"] || "",
        event["state_id"] || ""
      }
    end)
  end

  defp state_replay_events("tts-retry", simulation) do
    stream = get_in(simulation, ["receipt_preview", "stream"]) || %{}
    attempts = Map.get(stream, "attempts", [])

    cond do
      retry_attempts?(attempts) ->
        tts_retry_attempt_events(attempts)

      stream["released_to_consumer"] == true ->
        ["stream.release"]

      stream["retry_attempted"] == true ->
        ["stream.match", "attempt.retry"]

      stream["rule_matched"] ->
        ["stream.match"]

      true ->
        []
    end
  end

  defp state_replay_events("stream-rewrite-state", simulation) do
    receipt = Map.get(simulation, "receipt_preview", %{})
    stream = Map.get(receipt, "stream", %{})
    rewrites = Map.get(stream, "rewrites", [])
    transition = Map.get(stream, "state_transition")

    []
    |> maybe_append_event(model_input_changed?(receipt), "request.rewrite")
    |> maybe_append_event(rewrites != [], "regex.rewrite")
    |> maybe_append_event(rewrites != [] and transition == "review_required", "regex.related-secret")
    |> maybe_append_event(rewrites == [] and transition == "review_required", "history.related-secret")
    |> maybe_append_event(transition == "review_required", "receipt.write")
    |> maybe_append_event(rewrites != [] and transition != "review_required", "rewrite.release")
    |> maybe_append_event(rewrites == [] and transition != "review_required", "stream.release")
  end

  defp state_replay_events(_pattern_id, _simulation), do: []

  defp retry_attempts?(attempts) when is_list(attempts) do
    Enum.any?(attempts, &(Map.get(&1, "status") == "stream_policy_retry_required"))
  end

  defp retry_attempts?(_attempts), do: false

  defp tts_retry_attempt_events(attempts) when is_list(attempts) do
    attempts
    |> Enum.with_index()
    |> Enum.flat_map(fn {attempt, index} ->
      last_attempt? = index == length(attempts) - 1

      case Map.get(attempt, "status") do
        "stream_policy_retry_required" ->
          if last_attempt?, do: ["stream.match"], else: ["stream.match", "attempt.retry"]

        _status ->
          if index == 0, do: ["stream.release"], else: ["retry.release", "receipt.write"]
      end
    end)
  end

  defp maybe_append_event(events, true, event), do: events ++ [event]
  defp maybe_append_event(events, _condition, _event), do: events
end
