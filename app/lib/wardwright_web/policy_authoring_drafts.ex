defmodule WardwrightWeb.PolicyAuthoringDrafts do
  @moduledoc false

  alias WardwrightWeb.PolicyArtifactValidator

  @default_version "draft"
  @default_route_id "dispatcher.prompt_length"

  def synthetic_model_draft(body, origin \\ "http://127.0.0.1:8787") when is_map(body) do
    body = string_keys(body)
    artifact = artifact_from_body(body)
    validation = PolicyArtifactValidator.validate(artifact, source: "draft")

    %{
      "artifact" => artifact,
      "validation" => validation,
      "access" => access_details(artifact, origin),
      "next_steps" => next_steps(validation)
    }
  end

  def activate_synthetic_model(body, origin \\ "http://127.0.0.1:8787") when is_map(body) do
    body = string_keys(body)
    artifact = artifact_from_body(body)
    validation = PolicyArtifactValidator.validate(artifact, source: "draft")

    if validation["errors"] == [] do
      case Wardwright.put_config(artifact) do
        {:ok, config} ->
          {:ok,
           %{
             "status" => "activated",
             "artifact" => config,
             "validation" => PolicyArtifactValidator.validate(config, source: "current_config"),
             "access" => access_details(config, origin)
           }}

        {:error, message} ->
          {:error, message, synthetic_model_draft(body, origin)}
      end
    else
      {:error, "artifact has validation errors", synthetic_model_draft(body, origin)}
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
          "proposal" => %{
            "id" => proposal_id(proposed_artifact),
            "applied" => false,
            "operation" => operation,
            "collection" => collection,
            "rule_id" => rule_id,
            "change" => change
          },
          "artifact" => proposed_artifact,
          "validation" => PolicyArtifactValidator.validate(proposed_artifact, source: "proposal")
        }

      {:error, message} ->
        %{
          "proposal" => %{
            "applied" => false,
            "operation" => operation,
            "collection" => collection,
            "rule_id" => rule_id,
            "error" => message
          },
          "artifact" => artifact,
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
      "synthetic_model" => draft_model_id(body),
      "version" => draft_version(body),
      "targets" => draft_targets(body),
      "route_root" => route["id"],
      "dispatchers" =>
        if(route["type"] == "dispatcher", do: [Map.delete(route, "type")], else: []),
      "cascades" => if(route["type"] == "cascade", do: [Map.delete(route, "type")], else: []),
      "alloys" => if(route["type"] == "alloy", do: [Map.delete(route, "type")], else: []),
      "governance" => list_field(body, "governance"),
      "stream_rules" => list_field(body, "stream_rules"),
      "prompt_transforms" => map_field(body, "prompt_transforms", %{}),
      "structured_output" => Map.get(body, "structured_output"),
      "alert_delivery" => map_field(body, "alert_delivery", %{}),
      "policy_cache" => map_field(body, "policy_cache", %{})
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
    |> Map.get("synthetic_model", Map.get(body, "id", "draft-model"))
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
      "type" => route_type(type),
      "id" => if(id == "", do: default_route_id(type), else: id),
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
           %{"summary" => "appended rule", "after_count" => length(rules) + 1}}
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
      {:ok, Map.put(artifact, collection, updated),
       %{"summary" => "replaced rule", "matched_count" => count}}
    end
  end

  defp remove_rule(artifact, collection, rules, rule_id) do
    updated = Enum.reject(rules, &(Map.get(&1, "id") == rule_id))

    if length(updated) == length(rules) do
      {:error, "rule #{inspect(rule_id)} was not found"}
    else
      {:ok, Map.put(artifact, collection, updated),
       %{"summary" => "removed rule", "after_count" => length(updated)}}
    end
  end

  defp access_details(artifact, origin) do
    model = Map.get(artifact, "synthetic_model")

    %{
      "model_ids" => [model, "wardwright/#{model}"],
      "openai_base_url" => "#{origin}/v1",
      "chat_completions_url" => "#{origin}/v1/chat/completions",
      "models_url" => "#{origin}/v1/models"
    }
  end

  defp next_steps(%{"errors" => []}) do
    [
      "Review validation warnings and coverage gaps.",
      "POST the same body to /v1/policy-authoring/synthetic-models to activate it locally.",
      "Point an OpenAI-compatible agent at the returned openai_base_url and use one of the returned model_ids."
    ]
  end

  defp next_steps(_validation), do: ["Fix validation errors before activating this model."]

  defp default_collection(%{"rule" => %{"action" => action}})
       when action in ["pass", "block", "rewrite_chunk", "retry_with_reminder"],
       do: "stream_rules"

  defp default_collection(_body), do: "governance"

  defp rule_id(%{"id" => id}), do: id
  defp rule_id(_rule), do: ""

  defp list_field(map, key) do
    case Map.get(map, key) do
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp map_field(map, key, default) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _ -> default
    end
  end

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
