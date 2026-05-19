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

  def run_simulation(pattern_id, model_id, user_input, model_response) do
    config = model_config(model_id)
    pattern = Wardwright.PolicyProjection.pattern(pattern_id)
    projection = Wardwright.PolicyProjection.projection(pattern["id"], config)
    simulation = Wardwright.PolicyProjection.simulate_model_turn(user_input, model_response, config)
    receipt = Map.get(simulation, "receipt_preview", %{})
    stream = Map.get(receipt, "stream", %{})
    decision = Map.get(receipt, "decision", %{})
    model_received_input = model_received_input(receipt, user_input)
    user_received_output = user_received_output(stream, model_response)
    policy_actions = policy_actions(decision)
    trace_events = trace_events(simulation["trace"] || [])

    {
      pattern["title"] || pattern["id"] || "",
      pattern["promise"] || "",
      get_in(projection, ["engine", "engine_id"]) || "",
      get_in(projection, ["artifact", "artifact_hash"]) || "",
      decision["selected_model"] || "",
      simulation["verdict"] || "",
      model_received_input,
      user_received_output,
      model_input_changed?(receipt),
      user_received_output != (model_response || ""),
      policy_actions,
      trace_events
    }
  end

  defp model_config(model_id) when is_binary(model_id) do
    case Wardwright.model_config(model_id) do
      {:ok, config} -> config
      {:error, _message} -> Wardwright.current_config()
    end
  end

  defp model_config(_model_id), do: Wardwright.current_config()

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
        event["severity"] || ""
      }
    end)
  end
end
