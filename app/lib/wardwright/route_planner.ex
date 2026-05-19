defmodule Wardwright.RoutePlanner do
  @moduledoc """
  Pure Wardwright model route planning.

  The current low-level route nodes are intentionally small:

  * context-fit nodes choose the smallest eligible context window
  * ordered fallback nodes keep declaration-order fallback plans
  * blended route nodes choose by deterministic-all, weighted, or
    round-robin-style selection

  A selector target can also delegate to another embedded Wardwright model
  artifact. That first implementation is route-DAG composition: the nested
  artifact contributes route selection and lineage, but its request/output
  policies do not yet wrap the outer policy execution.
  """

  alias Wardwright.ModelGraph

  @max_route_dag_depth ModelGraph.max_depth()

  @type artifact :: map()
  @type attrs :: map()
  @type decision :: map()
  @type visited_models :: [String.t()]
  @type validation_result :: :ok | {:error, String.t()}

  @spec select(artifact(), integer(), attrs()) :: decision()
  def select(config, estimated_prompt_tokens, attrs \\ %{}) when is_map(config) do
    select_config(config, estimated_prompt_tokens, attrs, [])
  end

  @spec select_config(artifact(), integer(), attrs(), visited_models()) :: decision()
  defp select_config(config, estimated_prompt_tokens, attrs, visited) do
    targets =
      config
      |> ModelGraph.targets()
      |> filter_targets(Map.get(attrs, "allowed_targets"))
      |> target_index()

    forced_targets =
      Map.merge(provider_target_index(config, Map.get(attrs, "allowed_targets")), targets)

    forced_model = Map.get(attrs, "forced_model")

    decision =
      if forced_model in [nil, ""] do
        config
        |> root_selector()
        |> select_selector(config, targets, max(1, estimated_prompt_tokens), attrs)
      else
        select_forced_model(
          forced_model,
          config,
          targets,
          forced_targets,
          max(1, estimated_prompt_tokens),
          attrs
        )
      end

    decision
    |> resolve_model_graph_target(
      config,
      targets,
      max(1, estimated_prompt_tokens),
      attrs,
      visited
    )
    |> Map.put(:estimated_prompt_tokens, max(1, estimated_prompt_tokens))
    |> Map.put(:policy_route_constraints, route_constraints(attrs))
  end

  @spec validate(artifact()) :: validation_result()
  def validate(config) when is_map(config) do
    with :ok <- validate_local_config(config) do
      validate_model_graph(config, [], 0)
    end
  end

  @spec validate_local_config(artifact()) :: validation_result()
  defp validate_local_config(config) when is_map(config) do
    targets = target_index(ModelGraph.targets(config))

    with :ok <- validate_root(config),
         :ok <- validate_selectors("alloy", Map.get(config, "alloys", []), targets),
         :ok <- validate_selectors("cascade", Map.get(config, "cascades", []), targets) do
      validate_selectors("dispatcher", Map.get(config, "dispatchers", []), targets)
    end
  end

  @spec resolve_model_graph_target(decision(), artifact(), map(), integer(), attrs(), visited_models()) :: decision()
  defp resolve_model_graph_target(decision, config, targets, estimated, attrs, visited) do
    decision = Map.put_new(decision, :route_lineage, [ModelGraph.lineage_step(config, decision)])

    cond do
      decision.route_blocked ->
        decision

      target = Map.get(targets, decision.selected_model) ->
        if ModelGraph.wardwright_model_target?(target) do
          resolve_wardwright_target(decision, config, target, estimated, attrs, visited)
        else
          decision
        end

      true ->
        decision
    end
  end

  @spec resolve_wardwright_target(decision(), artifact(), map(), integer(), attrs(), visited_models()) :: decision()
  defp resolve_wardwright_target(decision, config, target, estimated, attrs, visited) do
    artifact = ModelGraph.target_artifact(target)
    ref_id = ModelGraph.ref_id(target, artifact)

    cond do
      not is_map(artifact) ->
        blocked_graph_decision(
          decision,
          config,
          "model target #{inspect(ModelGraph.target_model(target))} is missing an embedded artifact"
        )

      length(visited) >= @max_route_dag_depth ->
        blocked_graph_decision(
          decision,
          config,
          "model graph exceeded max depth #{@max_route_dag_depth}"
        )

      ref_id in visited ->
        blocked_graph_decision(
          decision,
          config,
          "model graph cycle detected at #{inspect(ref_id)}"
        )

      true ->
        nested = select_config(artifact, estimated, attrs, [ref_id | visited])

        nested
        |> Map.put(:route_type, "model_graph")
        |> Map.put(:route_id, "#{decision.route_id} -> #{nested.route_id}")
        |> Map.put(:combine_strategy, "route_dag_delegate")
        |> Map.put(:fallback_used, decision.fallback_used or nested.fallback_used)
        |> Map.put(:skipped, Map.get(decision, :skipped, []) ++ Map.get(nested, :skipped, []))
        |> Map.put(:reason, graph_reason(nested, target))
        |> Map.put(
          :rule,
          "delegate through a Wardwright model route graph, then call the selected provider target"
        )
        |> Map.put(
          :route_lineage,
          [
            ModelGraph.lineage_step(config, decision, ModelGraph.delegated_to_extra(target))
          ] ++
            Map.get(nested, :route_lineage, [])
        )
    end
  end

  defp blocked_graph_decision(decision, config, reason) do
    decision
    |> Map.put(:route_type, "model_graph")
    |> Map.put(:combine_strategy, "route_dag_delegate")
    |> Map.put(:route_blocked, true)
    |> Map.put(:selected_model, "unconfigured/no-target")
    |> Map.put(:selected_provider, "unconfigured")
    |> Map.put(:selected_context_window, nil)
    |> Map.put(:selected_models, [])
    |> Map.put(:fallback_models, [])
    |> Map.put(:reason, reason)
    |> Map.put(:rule, "reject invalid Wardwright model route graph")
    |> Map.put(:route_lineage, [ModelGraph.lineage_step(config, decision)])
  end

  defp graph_reason(nested, target) do
    "delegated through #{ModelGraph.target_model(target)}: #{nested.reason}"
  end

  defp root_selector(config) do
    root = Map.get(config, "route_root", "")
    first_dispatcher = first_selector_id(config, "dispatchers")
    first_cascade = first_selector_id(config, "cascades")
    first_alloy = first_selector_id(config, "alloys")

    :wardwright@route_core.default_root(root, first_dispatcher, first_cascade, first_alloy)
  end

  defp select_selector("__targets_dispatcher__", config, targets, estimated, _attrs) do
    dispatcher = %{
      "id" => "dispatcher.prompt_length",
      "models" => config |> ModelGraph.targets() |> Enum.map(&ModelGraph.target_model/1)
    }

    select_dispatcher(dispatcher, targets, estimated)
  end

  defp select_selector(root, config, targets, estimated, attrs) do
    cond do
      selector = find_selector(config, "dispatchers", root) ->
        select_dispatcher(selector, targets, estimated)

      selector = find_selector(config, "cascades", root) ->
        select_cascade(selector, targets, estimated)

      selector = find_selector(config, "alloys", root) ->
        select_alloy(selector, targets, estimated, attrs)

      true ->
        select_dispatcher(%{"id" => root, "models" => Map.keys(targets)}, targets, estimated)
        |> Map.put(:reason, "route root #{inspect(root)} was not configured")
    end
  end

  defp select_dispatcher(dispatcher, targets, estimated) do
    models =
      dispatcher
      |> models_for(targets, "models")
      |> Enum.sort_by(fn model ->
        {Map.fetch!(model, "context_window"), Map.fetch!(model, "model")}
      end)
      |> Enum.map(&target_for_core/1)

    all_targets = all_targets_for_core(targets)

    :wardwright@route_core.select_dispatcher(models, all_targets, estimated)
    |> route_selection_decision(%{
      combine_strategy: "smallest_context_window",
      route_id: Map.fetch!(dispatcher, "id"),
      route_type: "dispatcher",
      rule: "select the smallest configured context window that fits the estimated prompt"
    })
  end

  defp select_forced_model(model, config, targets, forced_targets, estimated, attrs) do
    forced = forced_targets |> Map.get(model) |> forced_target_for_core()

    skipped_targets =
      forced_targets
      |> Map.delete(model)
      |> Map.values()
      |> Enum.map(&target_for_core/1)

    forced
    |> :wardwright@route_core.select_forced_model(skipped_targets, estimated)
    |> forced_selection_decision(%{
      combine_strategy: "policy_forced_model",
      fallback_models: [],
      fallback_used: false,
      route_id: "policy.forced_model",
      route_type: "policy_override",
      rule: "apply policy route override before provider selection"
    })
    |> maybe_forced_fallback(model, config, targets, forced_targets, estimated, attrs)
  end

  defp maybe_forced_fallback(decision, model, config, targets, forced_targets, estimated, attrs) do
    if decision.route_blocked == true and allow_fallback?(attrs) do
      select_forced_fallback(
        config,
        targets,
        estimated,
        attrs,
        forced_failure_skips(model, Map.get(forced_targets, model), estimated),
        decision.reason
      )
    else
      decision
    end
  end

  defp select_forced_fallback(config, targets, estimated, attrs, forced_skipped, forced_reason) do
    fallback =
      config
      |> root_selector()
      |> select_selector(config, targets, estimated, Map.delete(attrs, "forced_model"))

    fallback
    |> Map.put(:route_type, "policy_override_fallback")
    |> Map.put(:route_id, "policy.forced_model")
    |> Map.put(:combine_strategy, "policy_forced_model_with_explicit_fallback")
    |> Map.put(:fallback_used, true)
    |> Map.put(:skipped, forced_skipped ++ Map.get(fallback, :skipped, []))
    |> Map.put(:reason, forced_fallback_reason(forced_reason))
    |> Map.put(:rule, "apply policy route override, then fall back only when allowed")
  end

  defp forced_failure_skips(model, nil, _estimated) do
    [%{"reason" => "forced_model_unavailable", "target" => model}]
  end

  defp forced_failure_skips(_model, forced, estimated), do: [context_skip(forced, estimated)]

  defp allow_fallback?(attrs), do: Map.fetch(attrs, "allow_fallback") == {:ok, true}

  defp select_cascade(cascade, targets, estimated) do
    models = cascade |> models_for(targets, "models") |> Enum.map(&target_for_core/1)
    all_targets = all_targets_for_core(targets)

    :wardwright@route_core.select_cascade(models, all_targets, estimated)
    |> route_selection_decision(%{
      combine_strategy: "ordered_fallback",
      route_id: Map.fetch!(cascade, "id"),
      route_type: "cascade",
      rule: "try configured models in order, skipping models whose context window cannot fit"
    })
  end

  defp route_selection_decision(
         {:route_selection, selected_model, selected_context_window, selected_models, fallback_models, skipped,
          route_blocked?, reason},
         attrs
       ) do
    attrs
    |> Map.put(:selected_model, selected_model)
    |> Map.put(
      :selected_context_window,
      if(!route_blocked?, do: selected_context_window)
    )
    |> Map.put(:selected_provider, provider_from_model(selected_model))
    |> Map.put(:selected_models, selected_models)
    |> Map.put(:fallback_models, fallback_models)
    |> Map.put(:skipped, Enum.map(skipped, &route_skip_from_core/1))
    |> Map.put(:reason, reason)
    |> Map.put_new(:fallback_used, false)
    |> Map.put(:route_blocked, route_blocked?)
  end

  defp forced_selection_decision(
         {:forced_selection, selected_model, selected_context_window, selected_models, skipped, route_blocked?, reason},
         attrs
       ) do
    attrs
    |> Map.put(:selected_model, selected_model)
    |> Map.put(
      :selected_context_window,
      if(!route_blocked?, do: selected_context_window)
    )
    |> Map.put(:selected_provider, provider_from_model(selected_model))
    |> Map.put(:selected_models, selected_models)
    |> Map.put(:skipped, Enum.map(skipped, &route_skip_from_core/1))
    |> Map.put(:reason, reason)
    |> Map.put(:route_blocked, route_blocked?)
  end

  defp select_alloy(alloy, targets, estimated, attrs) do
    models = models_for(alloy, targets, "constituents")
    partial_context = Map.get(alloy, "partial_context", false)

    {eligible, skipped} =
      if partial_context do
        split_by_context(models, estimated)
      else
        min_context = alloy_min_context(alloy, models)

        if estimated <= min_context do
          {models, []}
        else
          {[], context_skips(models, estimated)}
        end
      end

    {ordered, strategy} = alloy_order(alloy, eligible, attrs, estimated)

    selected =
      List.first(ordered) || fallback_model(alloy, targets) || largest_known_model(targets)

    selected_models = selected_models(selected, ordered)

    decision(selected, %{
      combine_strategy: strategy,
      fallback_models: Enum.drop(selected_models, 1),
      fallback_used: eligible == [],
      reason: alloy_reason(partial_context, skipped, selected_models),
      route_id: alloy["id"],
      route_type: "alloy",
      rule: "blend eligible alloy constituents while respecting declared context windows",
      selected_models: selected_models,
      skipped: skipped
    })
  end

  defp alloy_order(alloy, [], _attrs, _estimated),
    do: {[], normalize_alloy_strategy(Map.get(alloy, "strategy", "weighted"))}

  defp alloy_order(alloy, eligible, attrs, estimated) do
    strategy = normalize_alloy_strategy(Map.get(alloy, "strategy", "weighted"))

    ordered =
      case strategy do
        "deterministic_all" ->
          eligible

        "round_robin" ->
          rotate_by_seed(eligible, route_seed(attrs, estimated))

        "weighted" ->
          weighted_without_replacement(eligible, route_seed(attrs, estimated))
      end

    {ordered, strategy}
  end

  defp normalize_alloy_strategy(strategy) do
    strategy = string_value(strategy)

    :wardwright@route_core.normalize_alloy_strategy(strategy)
  end

  defp weighted_without_replacement(models, seed) do
    {ordered, _seed} =
      Enum.reduce(1..length(models), {[], models}, fn _, {ordered, remaining} ->
        total_weight = Enum.reduce(remaining, 0, fn model, acc -> acc + model_weight(model) end)
        total_weight = max(1, total_weight)
        selected_offset = :erlang.phash2({seed, Enum.map(remaining, & &1["model"])}, total_weight)
        {selected, next_remaining} = pop_weighted(remaining, selected_offset)
        {[selected | ordered], next_remaining}
      end)

    Enum.reverse(ordered)
  end

  defp pop_weighted(models, selected_offset) do
    {selected, remaining, _running} =
      Enum.reduce(models, {nil, [], 0}, fn model, {selected, remaining, running} ->
        weight = model_weight(model)

        cond do
          selected != nil ->
            {selected, [model | remaining], running}

          selected_offset < running + weight ->
            {model, remaining, running + weight}

          true ->
            {nil, [model | remaining], running + weight}
        end
      end)

    {selected || List.first(models), Enum.reverse(remaining)}
  end

  defp rotate_by_seed(models, seed) do
    offset = :erlang.phash2(seed, length(models))
    {left, right} = Enum.split(models, offset)
    right ++ left
  end

  defp route_seed(attrs, estimated) do
    Map.get(attrs, "route_seed") ||
      Map.get(attrs, "client_request_id") ||
      Map.get(attrs, "session_id") ||
      estimated
  end

  defp model_weight(model), do: integer_value(Map.get(model, "weight")) || 1

  defp all_targets_for_core(targets) do
    targets
    |> Map.values()
    |> Enum.sort_by(fn target ->
      {Map.fetch!(target, "context_window"), Map.fetch!(target, "model")}
    end)
    |> Enum.map(&target_for_core/1)
  end

  defp target_for_core(model) do
    {:target, Map.fetch!(model, "model"), Map.fetch!(model, "context_window"), model_weight(model)}
  end

  defp forced_target_for_core(nil), do: []
  defp forced_target_for_core(model), do: [target_for_core(model)]

  defp route_skip_from_core({:context_too_small, target, context_window, estimated}) do
    %{
      "context_window" => context_window,
      "estimated_prompt_tokens" => estimated,
      "reason" => "context_window_too_small",
      "target" => target
    }
  end

  defp route_skip_from_core({:policy_route_gate, target, context_window}) do
    Map.new([
      {"target", target},
      {"reason", "policy_route_gate"},
      {"context_window", context_window}
    ])
  end

  defp split_by_context(models, estimated) do
    Enum.reduce(models, {[], []}, fn model, {eligible, skipped} ->
      if model["context_window"] >= estimated do
        {[model | eligible], skipped}
      else
        {eligible, [context_skip(model, estimated) | skipped]}
      end
    end)
    |> then(fn {eligible, skipped} -> {Enum.reverse(eligible), Enum.reverse(skipped)} end)
  end

  defp context_skips(models, estimated), do: Enum.map(models, &context_skip(&1, estimated))

  defp context_skip(model, estimated) do
    %{
      "context_window" => model["context_window"],
      "estimated_prompt_tokens" => estimated,
      "reason" => "context_window_too_small",
      "target" => model["model"]
    }
  end

  defp selected_models(nil, eligible), do: Enum.map(eligible, & &1["model"])
  defp selected_models(selected, []), do: [selected["model"]]
  defp selected_models(_selected, eligible), do: Enum.map(eligible, & &1["model"])

  defp decision(selected, attrs) do
    selected_model = if selected, do: selected["model"], else: "unconfigured/no-target"
    selected_context_window = if selected, do: selected["context_window"]

    attrs
    |> Map.put(:selected_model, selected_model)
    |> Map.put(:selected_context_window, selected_context_window)
    |> Map.put(:selected_provider, provider_from_model(selected_model))
    |> Map.put_new(:fallback_used, false)
    |> Map.put(:route_blocked, selected == nil)
  end

  defp alloy_reason(partial_context, skipped, _selected_models) do
    skipped_count = length(skipped)

    :wardwright@route_core.alloy_reason(partial_context, skipped_count)
  end

  defp alloy_min_context(alloy, models) do
    Map.get(alloy, "min_context_window") ||
      models |> Enum.map(& &1["context_window"]) |> Enum.min(fn -> 0 end)
  end

  defp fallback_model(selector, targets) do
    fallback = Map.get(selector, "fallback_model", "")
    if fallback != "", do: Map.get(targets, fallback)
  end

  defp largest_known_model(targets) do
    targets
    |> Map.values()
    |> Enum.sort_by(fn target ->
      {ModelGraph.target_context_window(target), ModelGraph.target_model(target)}
    end)
    |> List.last()
  end

  defp target_index(targets) do
    Map.new(targets, fn target -> {ModelGraph.target_model(target), target} end)
  end

  defp provider_target_index(config, allowed_targets) do
    config
    |> ModelGraph.provider_targets()
    |> filter_targets(allowed_targets)
    |> target_index()
  end

  defp filter_targets(targets, allowed_targets) when is_list(allowed_targets) do
    allowed_targets =
      allowed_targets
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if allowed_targets == [] do
      targets
    else
      Enum.filter(targets, &target_allowed?(&1, allowed_targets))
    end
  end

  defp filter_targets(targets, _allowed_targets), do: targets

  defp target_allowed?(target, allowed_targets) do
    if ModelGraph.wardwright_model_target?(target) do
      true
    else
      provider_target_allowed?(target, allowed_targets)
    end
  end

  defp provider_target_allowed?(target, allowed_targets) do
    model = ModelGraph.target_model(target)
    provider = ModelGraph.provider_prefix(model)

    Enum.any?(allowed_targets, fn allowed ->
      allowed == model or allowed == provider or String.starts_with?(model, allowed <> "/")
    end)
  end

  defp route_constraints(attrs) do
    %{
      "allow_fallback" => Map.get(attrs, "allow_fallback"),
      "allowed_targets" => Map.get(attrs, "allowed_targets"),
      "forced_model" => Map.get(attrs, "forced_model")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], false] end)
    |> Map.new()
  end

  defp models_for(selector, targets, key) do
    selector
    |> Map.get(key, Map.get(selector, "targets", []))
    |> Enum.map(&model_ref(&1, targets))
    |> Enum.reject(&is_nil/1)
  end

  defp model_ref(model, targets) when is_binary(model), do: Map.get(targets, model)

  defp model_ref(model, targets) when is_map(model) do
    target = Map.get(targets, model["model"], %{})
    Map.merge(target, model)
  end

  defp model_ref(_model, _targets), do: nil

  defp find_selector(config, key, id) do
    config
    |> Map.get(key, [])
    |> Enum.find(fn selector -> selector["id"] == id end)
  end

  defp validate_selectors(kind, selectors, targets) do
    Enum.reduce_while(selectors, MapSet.new(), fn selector, seen ->
      id = Map.get(selector, "id", "")

      cond do
        id == "" ->
          {:halt, {:error, "#{kind} id must not be empty"}}

        MapSet.member?(seen, id) ->
          {:halt, {:error, "duplicate #{kind} #{id}"}}

        true ->
          case validate_selector_models(kind, selector, targets) do
            :ok -> {:cont, MapSet.put(seen, id)}
            error -> {:halt, error}
          end
      end
    end)
    |> case do
      %MapSet{} -> :ok
      other -> other
    end
  end

  defp validate_root(config) do
    root = Map.get(config, "route_root", "")

    selector_ids =
      ["alloys", "cascades", "dispatchers"]
      |> Enum.flat_map(fn key -> Enum.map(Map.get(config, key, []), & &1["id"]) end)

    cond do
      root in ["", "__targets_dispatcher__"] ->
        :ok

      root == "dispatcher.prompt_length" and Map.get(config, "dispatchers", []) == [] ->
        :ok

      root in selector_ids ->
        :ok

      true ->
        {:error, "route_root #{root} does not match a configured selector"}
    end
  end

  defp validate_selector_models("alloy", selector, targets) do
    with :ok <- validate_model_references("alloy", selector, targets, "constituents") do
      validate_alloy_models(selector, targets)
    end
  end

  defp validate_selector_models(kind, selector, targets) do
    with :ok <- validate_model_references(kind, selector, targets, "models") do
      validate_ordered_selector_models(kind, selector, targets)
    end
  end

  defp validate_model_references(kind, selector, targets, key) do
    selector
    |> Map.get(key, Map.get(selector, "targets", []))
    |> Enum.find(fn
      model when is_binary(model) -> not Map.has_key?(targets, model)
      _model -> false
    end)
    |> case do
      nil -> :ok
      model -> {:error, "#{kind} #{selector["id"]} references unknown target #{model}"}
    end
  end

  @spec validate_model_graph(artifact(), visited_models(), non_neg_integer()) :: validation_result()
  defp validate_model_graph(config, visited, depth) do
    model_id = ModelGraph.model_id(config)

    cond do
      depth > @max_route_dag_depth ->
        {:error, "model graph exceeds max depth #{@max_route_dag_depth}"}

      model_id != "" and model_id in visited ->
        {:error, "model graph cycle detected at #{model_id}"}

      true ->
        visited = if model_id == "", do: visited, else: [model_id | visited]

        config
        |> ModelGraph.targets()
        |> Enum.reduce_while(:ok, fn target, :ok ->
          if ModelGraph.wardwright_model_target?(target) do
            validate_model_graph_target(target, visited, depth)
          else
            {:cont, :ok}
          end
        end)
    end
  end

  @spec validate_model_graph_target(map(), visited_models(), non_neg_integer()) ::
          {:cont, validation_result()} | {:halt, {:error, String.t()}}
  defp validate_model_graph_target(target, visited, depth) do
    artifact = ModelGraph.target_artifact(target)
    ref_id = ModelGraph.ref_id(target, artifact)

    cond do
      not is_map(artifact) ->
        {:halt, {:error, "model target #{ModelGraph.target_model(target)} must include artifact"}}

      ref_id in visited ->
        {:halt, {:error, "model graph cycle detected at #{ref_id}"}}

      true ->
        case validate_local_config(artifact) do
          :ok ->
            {:cont, validate_model_graph(artifact, visited, depth + 1)}

          {:error, message} ->
            {:halt, {:error, "model target #{ModelGraph.target_model(target)}: #{message}"}}
        end
    end
  end

  defp validate_alloy_models(selector, targets) do
    models = models_for(selector, targets, "constituents")

    cond do
      length(models) < 2 ->
        {:error, "alloy #{selector["id"]} must define at least 2 constituents"}

      invalid_model = Enum.find(models, &invalid_model?/1) ->
        {:error, "alloy #{selector["id"]} target #{invalid_model["model"]} context_window must be positive"}

      invalid_weight = Enum.find(models, &(model_weight(&1) <= 0)) ->
        {:error, "alloy #{selector["id"]} target #{invalid_weight["model"]} weight must be positive"}

      not valid_alloy_strategy?(Map.get(selector, "strategy", "weighted")) ->
        {:error, "alloy #{selector["id"]} strategy must be weighted, round_robin, or deterministic_all"}

      true ->
        :ok
    end
  end

  defp validate_ordered_selector_models(kind, selector, targets) do
    models = models_for(selector, targets, "models")

    cond do
      models == [] ->
        {:error, "#{kind} #{selector["id"]} must define at least 1 model"}

      invalid_model = Enum.find(models, &invalid_model?/1) ->
        {:error, "#{kind} #{selector["id"]} target #{invalid_model["model"]} context_window must be positive"}

      true ->
        :ok
    end
  end

  defp invalid_model?(model),
    do: model["model"] in [nil, ""] or not is_integer(model["context_window"]) or model["context_window"] <= 0

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer_value(_), do: nil

  defp forced_fallback_reason(forced_reason) do
    :wardwright@route_core.forced_fallback_reason(forced_reason)
  end

  defp provider_from_model(model) do
    model |> String.split("/", parts: 2) |> List.first()
  end

  defp valid_alloy_strategy?(strategy) do
    strategy = string_value(strategy)

    :wardwright@route_core.validate_strategy(strategy)
  end

  defp first_selector_id(config, key) do
    case Map.get(config, key, []) do
      [%{"id" => id} | _rest] when is_binary(id) -> id
      _selectors -> ""
    end
  end

  defp string_value(value) when is_binary(value), do: value
  defp string_value(_value), do: ""
end
