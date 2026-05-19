defmodule WardwrightWeb.LustreWorkbenchData do
  @moduledoc false

  def pattern_options, do: pattern_options(nil)

  def pattern_options(model_id) when model_id in [nil, ""] do
    all_pattern_options()
  end

  def pattern_options(model_id) do
    supported_pattern_ids = supported_pattern_ids(model_config(model_id))

    all_pattern_options()
    |> Enum.filter(fn {pattern_id, _title, _category, _promise} ->
      pattern_id in supported_pattern_ids
    end)
  end

  defp all_pattern_options do
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
    (Wardwright.model_summaries() ++ demo_model_summaries())
    |> Enum.uniq_by(&(&1["id"] || ""))
    |> Enum.map(fn model ->
      {
        model["id"] || "",
        model["description"] || "",
        model["route_type"] || "",
        if(model["requires_api_key"], do: "keyed", else: "unkeyed")
      }
    end)
  end

  def fixture_options(pattern_id, model_id) do
    config = model_config(model_id)

    [
      model_default_fixture(model_id, config)
      | policy_fixture_options(pattern_id, model_id)
    ]
    |> Enum.uniq_by(&elem(&1, 0))
  end

  def default_pattern_id, do: default_pattern_id(default_model_id())

  def default_pattern_id(model_id) do
    model_id
    |> model_config()
    |> supported_pattern_ids()
    |> List.first()
    |> case do
      nil -> fallback_pattern_id()
      pattern_id -> pattern_id
    end
  end

  defp fallback_pattern_id do
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

  defp model_default_fixture(model_id, config) do
    {
      "model-default",
      "Model default",
      "Current model policy sample",
      default_model_simulation_user_input(config),
      default_model_simulation_response(config),
      fixture_retry_responses(model_id, [])
    }
  end

  defp policy_fixture_options(pattern_id, model_id) do
    pattern_id
    |> Wardwright.PolicyProjection.simulation_inputs()
    |> Enum.filter(&fixture_for_selected_policy?/1)
    |> Enum.map(fn input ->
      {
        input["id"] || "",
        fixture_title(input),
        input["description"] || "",
        input["user_input"] || "",
        input["model_response"] || "",
        fixture_retry_responses(model_id, input["response_attempts"] || [])
      }
    end)
  end

  defp fixture_for_selected_policy?(%{"relationship" => relationship}), do: relationship in ["direct", "saved_scenario"]

  defp fixture_for_selected_policy?(_input), do: false

  defp fixture_title(%{"relationship" => "saved_scenario"} = input), do: "Saved: #{input["title"] || input["id"] || ""}"
  defp fixture_title(input), do: input["title"] || input["id"] || ""

  defp fixture_retry_responses(model_id, attempts) do
    slot_count = retry_response_slots(model_id)

    case slot_count do
      count when count <= 0 ->
        []

      count ->
        attempt_outputs =
          attempts
          |> normalize_fixture_response_attempts()
          |> Map.new(fn %{"index" => index, "model_output" => output} -> {index, output} end)

        Enum.map(2..(count + 1), fn index ->
          {index, Map.get(attempt_outputs, index, "")}
        end)
    end
  end

  defp normalize_fixture_response_attempts(attempts) when is_list(attempts) do
    attempts
    |> Enum.flat_map(&normalize_fixture_response_attempt/1)
    |> Enum.sort_by(&Map.get(&1, "index", 0))
  end

  defp normalize_fixture_response_attempts(_attempts), do: []

  defp normalize_fixture_response_attempt({index, output}) when is_integer(index) and is_binary(output),
    do: [%{"index" => index, "model_output" => output}]

  defp normalize_fixture_response_attempt(%{"index" => index} = attempt) do
    with index when is_integer(index) <- parse_attempt_index(index),
         output when is_binary(output) and output != "" <-
           Map.get(attempt, "model_output") || Map.get(attempt, "model_response") do
      [%{"index" => index, "model_output" => output}]
    else
      _invalid -> []
    end
  end

  defp normalize_fixture_response_attempt(_attempt), do: []

  defp parse_attempt_index(index) when is_integer(index), do: index

  defp parse_attempt_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {integer, ""} -> integer
      _parse_error -> nil
    end
  end

  defp parse_attempt_index(_index), do: nil

  def projection_summary(pattern_id, model_id) do
    config = model_config(model_id)
    config_model_id = config["model_id"] || model_id || ""
    config_version = config["version"] || ""

    {engine_id, artifact_label, initial_state, default_projection, transitions} =
      :wardwright@projection_core.derive_summary(pattern_id, config_model_id, config_version)

    {
      engine_id,
      artifact_label,
      initial_state,
      default_projection,
      filter_projection_transitions(pattern_id, transitions, config) ++
        composed_projection_transitions(pattern_id, config, initial_state, terminal_state(pattern_id, transitions))
    }
  end

  def run_simulation(pattern_id, model_id, user_input, model_response) do
    run_simulation(pattern_id, model_id, user_input, model_response, [])
  end

  def run_simulation(pattern_id, model_id, user_input, model_response, response_attempts) do
    config = model_config(model_id)
    response_attempts = normalize_response_attempts(response_attempts)

    simulation =
      Wardwright.PolicyProjection.simulate_model_turn_with_attempts(
        user_input,
        model_response,
        response_attempts,
        config
      )

    receipt = Map.get(simulation, "receipt_preview", %{})
    stream = Map.get(receipt, "stream", %{})
    decision = Map.get(receipt, "decision", %{})
    model_received_input = model_received_input(receipt, user_input)
    user_received_output = user_received_output(stream, model_response)
    policy_actions = policy_actions(decision)
    trace_events = trace_events(simulation["trace"] || [])
    state_events = state_replay_events(pattern_id, simulation, config, user_input, model_response, response_attempts)

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
      {:error, _message} -> demo_model_config(model_id) || Wardwright.current_config()
    end
  end

  defp model_config(_model_id), do: Wardwright.current_config()

  defp demo_model_summaries do
    Enum.map(demo_model_configs(), &Wardwright.model_summary/1)
  end

  defp demo_model_config(model_id) when is_binary(model_id) do
    model_id = String.replace_prefix(model_id, "wardwright/", "")

    Enum.find(demo_model_configs(), &(Map.get(&1, "model_id") == model_id))
  end

  defp demo_model_configs do
    retry = demo_retry_guard_config()
    rewrite = demo_rewrite_review_config()

    [
      retry,
      rewrite,
      demo_route_cascade_config(),
      demo_composed_retry_router_config(retry),
      demo_composed_rewrite_router_config(rewrite),
      demo_nested_composition_config(retry, rewrite)
    ]
  end

  defp demo_retry_guard_config do
    demo_base_config(
      "demo-retry-guard",
      "Example model: retries streamed output that still uses OldClient.",
      [
        %{
          "canned_outputs" => [
            "Use OldClient(arg) in the migration.",
            "Still uses OldClient(arg).",
            "Use NewClient(arg) in the migration."
          ],
          "context_window" => 8192,
          "model" => "canned/demo-retry-writer",
          "provider_kind" => "canned_sequence"
        }
      ],
      "dispatcher.demo-retry",
      [%{"id" => "dispatcher.demo-retry", "models" => ["canned/demo-retry-writer"]}]
    )
    |> Map.put("stream_rules", [
      %{
        "action" => "retry_with_reminder",
        "id" => "retry-old-client",
        "max_retries" => 3,
        "regex" => "OldClient\\(",
        "reminder" => "Use NewClient instead of OldClient."
      }
    ])
    |> Wardwright.normalize_config()
  end

  defp demo_rewrite_review_config do
    demo_base_config(
      "demo-rewrite-review",
      "Example model: rewrites account spans and can transition secret-adjacent output to review.",
      [
        %{
          "canned_outputs" => ["The answer references acct_4938 and token_alpha."],
          "context_window" => 8192,
          "model" => "canned/demo-rewrite-writer",
          "provider_kind" => "canned_sequence"
        }
      ],
      "dispatcher.demo-rewrite",
      [%{"id" => "dispatcher.demo-rewrite", "models" => ["canned/demo-rewrite-writer"]}]
    )
    |> Map.put("governance", [
      %{
        "action" => "transform",
        "contains" => "account",
        "id" => "account-context-reminder",
        "kind" => "request_transform",
        "message" => "account context matched",
        "reminder" => "Do not expose raw account identifiers."
      }
    ])
    |> Map.put("stream_rules", [
      %{
        "action" => "rewrite_chunk",
        "id" => "redact-account",
        "regex" => "\\bacct_[A-Za-z0-9_]+\\b",
        "replacement" => "[account]"
      },
      %{
        "action" => "state_transition",
        "id" => "secret-needs-review",
        "regex" => "\\btoken_[A-Za-z0-9_]+\\b",
        "transition_to" => "review_required"
      }
    ])
    |> Wardwright.normalize_config()
  end

  defp demo_route_cascade_config do
    demo_base_config(
      "demo-context-cascade",
      "Example model: route-only cascade across small and large canned providers.",
      [
        %{"context_window" => 1024, "model" => "canned/small-context", "provider_kind" => "canned_sequence"},
        %{"context_window" => 32_768, "model" => "canned/large-context", "provider_kind" => "canned_sequence"}
      ],
      "cascade.demo-context",
      [],
      [%{"id" => "cascade.demo-context", "models" => ["canned/small-context", "canned/large-context"]}]
    )
  end

  defp demo_composed_retry_router_config(retry_config) do
    demo_composed_config(
      "demo-composed-retry-router",
      "Example composed model: delegates route selection to the retry guard model.",
      retry_config,
      "dispatcher.demo-composed-retry"
    )
  end

  defp demo_composed_rewrite_router_config(rewrite_config) do
    demo_composed_config(
      "demo-composed-rewrite-router",
      "Example composed model: delegates route selection to the rewrite/review model.",
      rewrite_config,
      "dispatcher.demo-composed-rewrite"
    )
  end

  defp demo_nested_composition_config(retry_config, rewrite_config) do
    child =
      demo_composed_config(
        "demo-nested-retry-child",
        "Nested child model that delegates to the retry guard.",
        retry_config,
        "dispatcher.demo-nested-child"
      )

    demo_base_config(
      "demo-nested-router",
      "Example composed model: a parent delegates to another Wardwright model and keeps a rewrite reviewer as fallback.",
      [
        model_graph_target(child, 8192),
        model_graph_target(rewrite_config, 8192)
      ],
      "cascade.demo-nested-router",
      [],
      [
        %{
          "id" => "cascade.demo-nested-router",
          "models" => [child["model_id"], rewrite_config["model_id"]]
        }
      ]
    )
  end

  defp demo_composed_config(model_id, description, child_config, route_id) do
    demo_base_config(
      model_id,
      description,
      [model_graph_target(child_config, 8192)],
      route_id,
      [%{"id" => route_id, "models" => [child_config["model_id"]]}]
    )
  end

  defp demo_base_config(model_id, description, targets, route_root, dispatchers, cascades \\ []) do
    Wardwright.default_config()
    |> Map.merge(%{
      "cascades" => cascades,
      "description" => description,
      "dispatchers" => dispatchers,
      "governance" => [],
      "model_id" => model_id,
      "requires_api_key" => false,
      "route_root" => route_root,
      "stream_rules" => [],
      "targets" => targets,
      "version" => "workbench-demo.v1"
    })
    |> Wardwright.normalize_config()
  end

  defp model_graph_target(config, context_window) do
    %{
      "artifact" => config,
      "context_window" => context_window,
      "model" => config["model_id"],
      "target_kind" => "wardwright_model"
    }
  end

  defp supported_pattern_ids(config) do
    [
      if(stream_retry_capable_tree?(config), do: "tts-retry"),
      if(
        stream_rewrite_capable_tree?(config) or request_rewrite_capable_tree?(config) or
          stream_state_transition_capable_tree?(config),
        do: "stream-rewrite-state"
      ),
      "route-privacy"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> filter_existing_pattern_ids()
  end

  defp filter_existing_pattern_ids(ids) do
    existing = Wardwright.PolicyProjection.pattern_ids() |> MapSet.new()

    Enum.filter(ids, &MapSet.member?(existing, &1))
  end

  defp filter_projection_transitions("tts-retry", transitions, config) do
    retry_capable? = stream_retry_capable?(config)

    Enum.filter(transitions, fn
      {_from, "stream.release", _to, _action, _node_id} -> true
      {_from, _event, _to, _action, _node_id} -> retry_capable?
    end)
  end

  defp filter_projection_transitions("stream-rewrite-state", transitions, config) do
    request_rewrite? = request_rewrite_capable?(config)
    stream_rewrite? = stream_rewrite_capable?(config)
    stream_state_transition? = stream_state_transition_capable?(config)

    Enum.filter(transitions, fn
      {_from, "stream.release", _to, _action, _node_id} -> true
      {_from, "request.rewrite", _to, _action, _node_id} -> request_rewrite?
      {_from, "regex.rewrite", _to, _action, _node_id} -> stream_rewrite?
      {_from, "rewrite.release", _to, _action, _node_id} -> stream_rewrite?
      {_from, "regex.related-secret", _to, _action, _node_id} -> stream_rewrite? and stream_state_transition?
      {_from, "history.related-secret", _to, _action, _node_id} -> stream_state_transition?
      {_from, "receipt.write", _to, _action, _node_id} -> stream_state_transition?
      {_from, _event, _to, _action, _node_id} -> false
    end)
  end

  defp filter_projection_transitions(_pattern_id, transitions, _config), do: transitions

  defp composed_projection_transitions(pattern_id, config, parent_initial, parent_terminal) do
    composed_projection_transitions(pattern_id, config, parent_initial, parent_terminal, nil, MapSet.new(), 0)
  end

  defp composed_projection_transitions(
         _pattern_id,
         _config,
         _parent_initial,
         _parent_terminal,
         _prefix,
         _visited,
         depth
       )
       when depth >= 4, do: []

  defp composed_projection_transitions(
         pattern_id,
         config,
         parent_initial,
         parent_terminal,
         parent_prefix,
         visited,
         depth
       ) do
    config_id = Wardwright.ModelGraph.model_id(config, "")
    visited = if config_id == "", do: visited, else: MapSet.put(visited, config_id)
    parent_from = prefixed_state(parent_initial, parent_prefix)
    parent_to = prefixed_state(parent_terminal, parent_prefix)

    config
    |> Wardwright.ModelGraph.targets()
    |> Enum.flat_map(fn target ->
      artifact = Wardwright.ModelGraph.target_artifact(target)
      ref_id = Wardwright.ModelGraph.ref_id(target, artifact)

      if Wardwright.ModelGraph.wardwright_model_target?(target) and is_map(artifact) and
           not MapSet.member?(visited, ref_id) do
        child_id = graph_model_id(ref_id)
        child_prefix = joined_prefix(parent_prefix, child_id)
        child_visited = MapSet.put(visited, ref_id)

        {child_initial, child_terminal, child_transitions} =
          prefixed_projection_transitions(pattern_id, artifact, child_prefix, child_visited, depth + 1)

        [
          {
            parent_from,
            "route.delegate.#{child_id}",
            prefixed_state(child_initial, child_prefix),
            "call_wardwright_model",
            "route.#{child_id}"
          }
          | child_transitions
        ] ++
          [
            {
              prefixed_state(child_terminal, child_prefix),
              "route.return.#{child_id}",
              parent_to,
              "merge_child_receipt",
              "route.#{child_id}"
            }
          ]
      else
        []
      end
    end)
  end

  defp prefixed_projection_transitions(pattern_id, config, prefix, visited, depth) do
    config_model_id = config["model_id"] || ""
    config_version = config["version"] || ""

    {_engine_id, _artifact_label, initial_state, _default_projection, transitions} =
      :wardwright@projection_core.derive_summary(pattern_id, config_model_id, config_version)

    filtered = filter_projection_transitions(pattern_id, transitions, config)
    terminal = terminal_state(pattern_id, transitions)

    nested =
      composed_projection_transitions(pattern_id, config, initial_state, terminal, prefix, visited, depth)

    {
      initial_state,
      terminal,
      prefix_transitions(filtered, prefix) ++ nested
    }
  end

  defp prefix_transitions(transitions, prefix) do
    Enum.map(transitions, fn {from, event, to, action, node_id} ->
      {prefixed_state(from, prefix), event, prefixed_state(to, prefix), action, node_id}
    end)
  end

  defp terminal_state(_pattern_id, transitions) do
    cond do
      Enum.any?(transitions, fn {_from, _event, to, _action, _node_id} -> to == "recording" end) ->
        "recording"

      transitions != [] ->
        transitions
        |> List.last()
        |> elem(2)

      true ->
        "active"
    end
  end

  defp prefixed_state(state, nil), do: state
  defp prefixed_state(state, ""), do: state
  defp prefixed_state(state, prefix), do: "#{prefix}::#{state}"

  defp joined_prefix(nil, child_id), do: child_id
  defp joined_prefix("", child_id), do: child_id
  defp joined_prefix(prefix, child_id), do: "#{prefix}::#{child_id}"

  defp graph_model_id(model_id) do
    model_id
    |> to_string()
    |> String.trim()
    |> then(fn
      "" -> "model"
      id -> Regex.replace(~r/[^A-Za-z0-9_.-]+/, id, "_")
    end)
  end

  defp stream_retry_capable_tree?(config), do: config_tree_any?(config, &stream_retry_capable?/1)
  defp stream_rewrite_capable_tree?(config), do: config_tree_any?(config, &stream_rewrite_capable?/1)
  defp request_rewrite_capable_tree?(config), do: config_tree_any?(config, &request_rewrite_capable?/1)

  defp stream_state_transition_capable_tree?(config), do: config_tree_any?(config, &stream_state_transition_capable?/1)

  defp config_tree_any?(config, callback) do
    config_tree_any?(config, callback, MapSet.new(), 0)
  end

  defp config_tree_any?(_config, _callback, _visited, depth) when depth >= 4, do: false

  defp config_tree_any?(config, callback, visited, depth) do
    config_id = Wardwright.ModelGraph.model_id(config, "")
    visited = if config_id == "", do: visited, else: MapSet.put(visited, config_id)

    callback.(config) or
      config
      |> nested_model_configs(visited)
      |> Enum.any?(fn nested_config ->
        config_tree_any?(nested_config, callback, visited, depth + 1)
      end)
  end

  defp stream_retry_capable?(config) do
    config
    |> Map.get("stream_rules", [])
    |> Enum.any?(fn
      %{"action" => action} -> action in ["retry", "retry_with_reminder"]
      _rule -> false
    end)
  end

  defp stream_rewrite_capable?(config) do
    config
    |> Map.get("stream_rules", [])
    |> Enum.any?(fn
      %{"action" => action} -> action in ["rewrite", "rewrite_chunk", "rewrite_span", "replace"]
      _rule -> false
    end)
  end

  defp stream_state_transition_capable?(config) do
    config
    |> Map.get("stream_rules", [])
    |> Enum.any?(fn
      %{"action" => "state_transition"} -> true
      %{"transition_to" => transition_to} when is_binary(transition_to) -> String.trim(transition_to) != ""
      _rule -> false
    end)
  end

  defp request_rewrite_capable?(config) do
    config
    |> Map.get("governance", [])
    |> Enum.any?(&request_transform_rule?/1)
  end

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
    retry_slot_candidates(config, MapSet.new(), 0)
  end

  defp retry_slot_candidates(_config, _visited, depth) when depth >= 4, do: []

  defp retry_slot_candidates(config, visited, depth) do
    config_id = Wardwright.ModelGraph.model_id(config, "")
    visited = if config_id == "", do: visited, else: MapSet.put(visited, config_id)

    stream_retry_slots(config) ++
      structured_output_retry_slots(config) ++
      (config
       |> nested_model_configs(visited)
       |> Enum.flat_map(fn nested_config ->
         retry_slot_candidates(nested_config, visited, depth + 1)
       end))
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
    local_default_model_simulation_response(config) ||
      nested_default(config, &local_default_model_simulation_response/1) ||
      "The model output contains text to test."
  end

  defp local_default_model_simulation_response(config) do
    config
    |> Map.get("stream_rules", [])
    |> Enum.find(
      &(Map.get(&1, "action") in ["rewrite", "rewrite_chunk", "rewrite_span", "replace", "retry", "retry_with_reminder"])
    )
    |> case do
      %{"regex" => regex} when is_binary(regex) ->
        default_model_response_for_match(regex)

      %{"contains" => contains} when is_binary(contains) ->
        default_model_response_for_match(contains)

      %{"pattern" => pattern} when is_binary(pattern) ->
        default_model_response_for_match(pattern)

      _rule ->
        nil
    end
  end

  defp default_model_response_for_match(match) do
    cond do
      String.contains?(String.downcase(match), "moo") ->
        "The model says moo in a draft answer."

      String.contains?(match, "OldClient") ->
        "Use OldClient(arg) in the migration."

      String.contains?(match, "acct_") ->
        "The model mentions acct_4938 in a draft answer."

      String.contains?(match, "token_") ->
        "The model mentions token_alpha in a draft answer."

      true ->
        "The model output contains text to test against #{match}."
    end
  end

  defp default_model_simulation_user_input(config) do
    local_default_model_simulation_user_input(config) ||
      nested_default(config, &local_default_model_simulation_user_input/1) ||
      ""
  end

  defp local_default_model_simulation_user_input(config) do
    config
    |> Map.get("governance", [])
    |> Enum.find(&request_transform_rule?/1)
    |> case do
      %{"contains" => contains} when is_binary(contains) and contains != "" ->
        "The user says #{contains} while asking for help."

      %{"match" => match} when is_binary(match) and match != "" ->
        "The user says #{match} while asking for help."

      _rule ->
        nil
    end
  end

  defp nested_default(config, callback) do
    nested_default(config, callback, MapSet.new(), 0)
  end

  defp nested_default(_config, _callback, _visited, depth) when depth >= 4, do: nil

  defp nested_default(config, callback, visited, depth) do
    config_id = Wardwright.ModelGraph.model_id(config, "")
    visited = if config_id == "", do: visited, else: MapSet.put(visited, config_id)

    config
    |> nested_model_configs(visited)
    |> Enum.find_value(fn nested_config ->
      callback.(nested_config) || nested_default(nested_config, callback, visited, depth + 1)
    end)
  end

  defp nested_model_configs(config, visited) do
    config
    |> Wardwright.ModelGraph.targets()
    |> Enum.flat_map(fn target ->
      artifact = Wardwright.ModelGraph.target_artifact(target)
      ref_id = Wardwright.ModelGraph.ref_id(target, artifact)

      if Wardwright.ModelGraph.wardwright_model_target?(target) and is_map(artifact) and
           not MapSet.member?(visited, ref_id) do
        [artifact]
      else
        []
      end
    end)
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

  defp state_replay_events(pattern_id, simulation, config, user_input, model_response, response_attempts) do
    case delegated_child_target(config, simulation) do
      {delegate_id, child_config} ->
        child_simulation =
          Wardwright.PolicyProjection.simulate_model_turn_with_attempts(
            user_input,
            model_response,
            response_attempts,
            child_config
          )

        child_events =
          state_replay_events(pattern_id, child_simulation, child_config, user_input, model_response, response_attempts)

        case child_events do
          [] ->
            ["route.delegate.#{graph_model_id(delegate_id)}"]

          _events ->
            ["route.delegate.#{graph_model_id(delegate_id)}"] ++
              child_events ++ ["route.return.#{graph_model_id(delegate_id)}"]
        end

      nil ->
        pattern_state_replay_events(pattern_id, simulation)
    end
  end

  defp delegated_child_target(config, simulation) do
    delegate_id =
      simulation
      |> get_in(["receipt_preview", "decision", "route_lineage"])
      |> delegated_route_id()

    if delegate_id do
      config
      |> Wardwright.ModelGraph.targets()
      |> Enum.find_value(fn target ->
        artifact = Wardwright.ModelGraph.target_artifact(target)

        if Wardwright.ModelGraph.wardwright_model_target?(target) and is_map(artifact) and
             Wardwright.ModelGraph.target_model(target) == delegate_id do
          {delegate_id, artifact}
        end
      end)
    end
  end

  defp delegated_route_id(lineage) when is_list(lineage) do
    lineage
    |> Enum.find_value(fn
      %{"delegated_to" => delegated_to} when is_binary(delegated_to) and delegated_to != "" -> delegated_to
      _step -> nil
    end)
  end

  defp delegated_route_id(_lineage), do: nil

  defp pattern_state_replay_events("tts-retry", simulation) do
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

  defp pattern_state_replay_events("stream-rewrite-state", simulation) do
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

  defp pattern_state_replay_events(_pattern_id, _simulation), do: []

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
