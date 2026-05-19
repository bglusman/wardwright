defmodule WardwrightWeb.PolicyAuthoringDrafts do
  @moduledoc false

  alias WardwrightWeb.PolicyArtifactValidator

  @default_version "draft"
  @default_route_id "dispatcher.prompt_length"

  def wardwright_model_draft(body, origin \\ "http://127.0.0.1:8787") when is_map(body) do
    body = string_keys(body)
    artifact = artifact_from_body(body)
    validation = PolicyArtifactValidator.validate(artifact, source: "draft")

    %{
      "access" => access_details(artifact, origin),
      "artifact" => artifact,
      "next_steps" => next_steps(validation),
      "validation" => validation
    }
  end

  def activate_wardwright_model(body, origin \\ "http://127.0.0.1:8787") when is_map(body) do
    body = string_keys(body)
    artifact = artifact_from_body(body)
    validation = PolicyArtifactValidator.validate(artifact, source: "draft")

    if validation["errors"] == [] do
      case Wardwright.put_model_config(artifact) do
        {:ok, config} ->
          {:ok,
           %{
             "access" => access_details(config, origin),
             "artifact" => config,
             "status" => "activated",
             "validation" => PolicyArtifactValidator.validate(config, source: "current_config")
           }}

        {:error, message} ->
          {:error, message, wardwright_model_draft(body, origin)}
      end
    else
      {:error, "artifact has validation errors", wardwright_model_draft(body, origin)}
    end
  end

  def propose_rule_change(body) when is_map(body) do
    body = string_keys(body)
    artifact = artifact_for_change(body)
    operation = body |> Map.get("operation", "append_rule") |> to_string()
    collection = body |> Map.get("collection", default_collection(body)) |> to_string()
    rule = Map.get(body, "rule")
    rule_id = body |> Map.get("rule_id", rule_id(rule)) |> to_string()

    case apply_rule_operation(artifact, operation, collection, rule, rule_id) do
      {:ok, proposed_artifact, change} ->
        %{
          "artifact" => proposed_artifact,
          "proposal" => %{
            "applied" => false,
            "change" => change,
            "collection" => collection,
            "id" => proposal_id(proposed_artifact),
            "operation" => operation,
            "rule_id" => rule_id
          },
          "validation" => PolicyArtifactValidator.validate(proposed_artifact, source: "proposal")
        }

      {:error, message} ->
        %{
          "artifact" => artifact,
          "proposal" => %{
            "applied" => false,
            "collection" => collection,
            "error" => message,
            "operation" => operation,
            "rule_id" => rule_id
          },
          "validation" => PolicyArtifactValidator.validate(artifact, source: "proposal")
        }
    end
  end

  def propose_rule_change(_body), do: propose_rule_change(%{})

  def with_error(result, message) when is_map(result), do: Map.put(result, "error", message)

  defp artifact_from_body(%{"artifact" => artifact}) when is_map(artifact) do
    Wardwright.default_config()
    |> Map.merge(string_keys(artifact))
    |> Wardwright.normalize_config()
  end

  defp artifact_from_body(body) do
    body = string_keys(body)
    route = route_body(body)

    Wardwright.default_config()
    |> Map.merge(%{
      "alert_delivery" => map_field(body, "alert_delivery", %{}),
      "alloys" => if(route["type"] == "alloy", do: [Map.delete(route, "type")], else: []),
      "cascades" => if(route["type"] == "cascade", do: [Map.delete(route, "type")], else: []),
      "dispatchers" => if(route["type"] == "dispatcher", do: [Map.delete(route, "type")], else: []),
      "governance" => governance_rules_field(body),
      "model_id" => draft_model_id(body),
      "policy_cache" => map_field(body, "policy_cache", %{}),
      "prompt_transforms" => map_field(body, "prompt_transforms", %{}, ["behavior_primitives", "prompt_transforms"]),
      "route_root" => route["id"],
      "stream_rules" => stream_rules_field(body),
      "structured_output" =>
        Map.get(body, "structured_output", get_in(body, ["behavior_primitives", "structured_output"])),
      "targets" => draft_targets(body),
      "version" => draft_version(body)
    })
    |> Wardwright.normalize_config()
  end

  defp artifact_for_change(%{"artifact" => artifact}) when is_map(artifact) do
    %{"artifact" => artifact}
    |> artifact_from_body()
  end

  defp artifact_for_change(_body), do: Wardwright.normalize_config(Wardwright.current_config())

  defp draft_model_id(body) do
    body
    |> Map.get("model_id", Map.get(body, "id", "draft-model"))
    |> to_string()
    |> String.trim()
  end

  defp draft_version(body) do
    body
    |> Map.get("version", @default_version)
    |> to_string()
    |> String.trim()
    |> case do
      "" -> @default_version
      version -> version
    end
  end

  defp draft_targets(body) do
    case Map.get(body, "targets") do
      targets when is_list(targets) ->
        targets

      _ ->
        Wardwright.default_config()["targets"]
    end
  end

  defp route_body(body) do
    route = map_field(body, "route", %{})
    type = route |> Map.get("type", "dispatcher") |> to_string()
    id = route |> Map.get("id", default_route_id(type)) |> to_string()
    models = route_models(route, body, type)

    %{
      "id" => if(id == "", do: default_route_id(type), else: id),
      "type" => route_type(type),
      model_key(type) => models
    }
    |> maybe_put("name", Map.get(route, "name"))
    |> maybe_put("strategy", Map.get(route, "strategy"))
    |> maybe_put("partial_context", Map.get(route, "partial_context"))
    |> maybe_put("min_context_window", Map.get(route, "min_context_window"))
    |> maybe_put("fallback_model", Map.get(route, "fallback_model"))
  end

  defp route_models(route, body, type) do
    route
    |> Map.get(model_key(type), Map.get(route, "models", Map.get(route, "targets")))
    |> case do
      models when is_list(models) ->
        models

      _ ->
        body
        |> draft_targets()
        |> Enum.map(&Map.get(&1, "model"))
        |> Enum.reject(&is_nil/1)
    end
  end

  defp route_type(type) when type in ["dispatcher", "cascade", "alloy"], do: type
  defp route_type(_type), do: "dispatcher"

  defp default_route_id("cascade"), do: "cascade.primary"
  defp default_route_id("alloy"), do: "alloy.primary"
  defp default_route_id(_type), do: @default_route_id

  defp model_key("alloy"), do: "constituents"
  defp model_key(_type), do: "models"

  defp apply_rule_operation(artifact, operation, collection, rule, rule_id)
       when collection in ["governance", "stream_rules"] do
    rules = list_field(artifact, collection)

    case operation do
      "append_rule" ->
        if is_map(rule) do
          {:ok, Map.put(artifact, collection, rules ++ [rule]),
           %{"after_count" => length(rules) + 1, "summary" => "appended rule"}}
        else
          {:error, "rule must be an object for append_rule"}
        end

      "replace_rule" ->
        replace_rule(artifact, collection, rules, rule, rule_id)

      "remove_rule" ->
        remove_rule(artifact, collection, rules, rule_id)

      _ ->
        {:error, "unsupported rule change operation #{inspect(operation)}"}
    end
  end

  defp apply_rule_operation(_artifact, _operation, collection, _rule, _rule_id),
    do: {:error, "collection must be governance or stream_rules, got #{inspect(collection)}"}

  defp replace_rule(_artifact, _collection, _rules, rule, _rule_id) when not is_map(rule),
    do: {:error, "rule must be an object for replace_rule"}

  defp replace_rule(artifact, collection, rules, rule, rule_id) do
    {updated, count} =
      Enum.map_reduce(rules, 0, fn existing, count ->
        if Map.get(existing, "id") == rule_id do
          {rule, count + 1}
        else
          {existing, count}
        end
      end)

    if count == 0 do
      {:error, "rule #{inspect(rule_id)} was not found"}
    else
      {:ok, Map.put(artifact, collection, updated), %{"matched_count" => count, "summary" => "replaced rule"}}
    end
  end

  defp remove_rule(artifact, collection, rules, rule_id) do
    updated = Enum.reject(rules, &(Map.get(&1, "id") == rule_id))

    if length(updated) == length(rules) do
      {:error, "rule #{inspect(rule_id)} was not found"}
    else
      {:ok, Map.put(artifact, collection, updated), %{"after_count" => length(updated), "summary" => "removed rule"}}
    end
  end

  defp access_details(artifact, origin) do
    model = Map.get(artifact, "model_id")

    %{
      "chat_completions_url" => "#{origin}/v1/chat/completions",
      "model_ids" => [model, "wardwright/#{model}"],
      "models_url" => "#{origin}/v1/models",
      "openai_base_url" => "#{origin}/v1"
    }
  end

  defp next_steps(%{"errors" => []}) do
    [
      "Review validation warnings and coverage gaps.",
      "POST the same body to /v1/policy-authoring/wardwright-models to register or update it locally.",
      "Point an OpenAI-compatible agent at the returned openai_base_url and use one of the returned model_ids."
    ]
  end

  defp next_steps(_validation), do: ["Fix validation errors before activating this model."]

  defp default_collection(%{"rule" => %{"action" => action}})
       when action in ["pass", "block", "rewrite_chunk", "retry_with_reminder"], do: "stream_rules"

  defp default_collection(_body), do: "governance"

  defp rule_id(%{"id" => id}), do: id
  defp rule_id(_rule), do: ""

  defp governance_rules_field(body) do
    explicit = list_field(body, "governance", ["behavior_primitives", "governance"])

    inferred =
      body
      |> behavior_stream_rules()
      |> Enum.with_index(1)
      |> Enum.filter(fn {rule, _index} -> request_trigger?(Map.get(rule, "trigger")) end)
      |> Enum.map(fn {rule, index} -> request_transform_from_stream_like_rule(rule, index) end)

    explicit ++ inferred
  end

  defp stream_rules_field(body) do
    body
    |> behavior_stream_rules()
    |> Enum.reject(&request_trigger?(Map.get(&1, "trigger")))
    |> Enum.with_index(1)
    |> Enum.map(fn {rule, index} -> normalize_stream_rule(rule, index) end)
  end

  defp behavior_stream_rules(body), do: list_field(body, "stream_rules", ["behavior_primitives", "stream_rules"])

  defp request_transform_from_stream_like_rule(rule, index) do
    rule = string_keys(rule)
    {match_key, match_value} = request_match_from_trigger(Map.get(rule, "trigger"))

    reminder =
      Map.get(rule, "reminder", Map.get(rule, "replacement_text", Map.get(rule, "replacement")))

    %{
      "action" => "transform",
      "id" => Map.get(rule, "id", "request-transform-#{index}"),
      "kind" => "request_transform",
      "message" => Map.get(rule, "message", "request input matched"),
      "reminder" => reminder
    }
    |> maybe_put(match_key, match_value)
  end

  defp normalize_stream_rule(rule, index) when is_map(rule) do
    rule = string_keys(rule)
    action = normalize_stream_action(Map.get(rule, "action"), rule)
    {trigger_match_key, trigger_match_value} = stream_match_from_trigger(Map.get(rule, "trigger"))
    pattern = Map.get(rule, "pattern")
    regex = Map.get(rule, "regex")
    replacement = Map.get(rule, "replacement", Map.get(rule, "replacement_text"))

    rule
    |> Map.put_new("id", "stream-rule-#{index}")
    |> Map.put("action", action)
    |> maybe_put("pattern", pattern)
    |> maybe_put("regex", regex || if(trigger_match_key == "regex", do: trigger_match_value))
    |> maybe_put("replacement", replacement)
    |> Map.drop(["trigger", "replacement_text"])
  end

  defp normalize_stream_rule(rule, _index), do: rule

  defp normalize_stream_action("rewrite_stream", _rule), do: "rewrite_chunk"
  defp normalize_stream_action(action, _rule) when is_binary(action) and action != "", do: action

  defp normalize_stream_action(_action, rule) do
    if Map.has_key?(rule, "replacement") or Map.has_key?(rule, "replacement_text") do
      "rewrite_chunk"
    else
      "pass"
    end
  end

  defp stream_match_from_trigger(trigger) when is_binary(trigger) do
    case trigger_contains_parts(trigger) do
      {token, _source} -> {"regex", token_pattern(token)}
      nil -> {"regex", trigger}
    end
  end

  defp stream_match_from_trigger(_trigger), do: {nil, nil}

  defp request_match_from_trigger(trigger) when is_binary(trigger) do
    case trigger_contains_parts(trigger) do
      {token, _source} -> {"contains", token}
      nil -> {"regex", trigger}
    end
  end

  defp request_match_from_trigger(_trigger), do: {"contains", ""}

  defp request_trigger?(trigger) when is_binary(trigger) do
    trigger =~ ~r/\b(input_text|request_text|user_input|user_text)\b/
  end

  defp request_trigger?(_trigger), do: false

  defp trigger_contains_parts(trigger) do
    case Regex.run(~r/contains\(['"]([^'"]+)['"]\s*,\s*([a-zA-Z_][a-zA-Z0-9_]*)\)/, trigger) do
      [_match, token, source] -> {token, source}
      _ -> nil
    end
  end

  defp token_pattern(token) do
    escaped = Regex.escape(token)

    if token =~ ~r/^\w+$/ do
      "\\b#{escaped}\\b"
    else
      escaped
    end
  end

  defp list_field(map, key, nested_path \\ nil) do
    case Map.get(map, key, nested_value(map, nested_path)) do
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp map_field(map, key, default, nested_path \\ nil) do
    case Map.get(map, key, nested_value(map, nested_path)) do
      value when is_map(value) -> value
      _ -> default
    end
  end

  defp nested_value(_map, nil), do: nil
  defp nested_value(map, path), do: get_in(map, path)

  defp maybe_put(map, _key, value) when value in [nil, "", []], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp proposal_id(artifact) do
    encoded = Jason.encode!(artifact)
    digest = Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
    "proposal_" <> binary_part(digest, 0, 16)
  end

  defp string_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), string_keys(value)}
      {key, value} -> {key, string_keys(value)}
    end)
  end

  defp string_keys(list) when is_list(list), do: Enum.map(list, &string_keys/1)
  defp string_keys(value), do: value
end
