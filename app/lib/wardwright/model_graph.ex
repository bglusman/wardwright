defmodule Wardwright.ModelGraph do
  @moduledoc """
  Shared accessors for Wardwright model graph artifacts.

  Core modules should not each rediscover the string-keyed artifact shape. This
  module is the boundary between normalized JSON-like model manifests and the
  pure routing/runtime code that consumes them.
  """

  @max_depth 8

  @artifact_key "artifact"
  @config_key "config"
  @context_window_key "context_window"
  @delegated_to_key "delegated_to"
  @kind_key "kind"
  @model_key "model"
  @model_id_key "model_id"
  @reason_key "reason"
  @route_id_key "route_id"
  @route_type_key "route_type"
  @selected_context_window_key "selected_context_window"
  @selected_model_key "selected_model"
  @target_kind_key "target_kind"
  @targets_key "targets"
  @version_key "version"
  @wardwright_model_kind "wardwright_model"

  @type artifact :: map()
  @type model_id :: String.t()
  @type target :: map()
  @type visited_models :: [model_id()]

  @spec max_depth() :: pos_integer()
  def max_depth, do: @max_depth

  @spec model_id(artifact(), String.t()) :: model_id()
  def model_id(config, default \\ "anonymous-model") when is_map(config) do
    config
    |> Map.get(@model_id_key, default)
    |> to_string()
  end

  @spec version(artifact()) :: term()
  def version(config) when is_map(config), do: Map.get(config, @version_key)

  @spec targets(artifact() | term()) :: [target()]
  def targets(config) when is_map(config), do: Map.get(config, @targets_key, [])
  def targets(_config), do: []

  @spec target_model(target() | term()) :: model_id()
  def target_model(target) when is_map(target) do
    target
    |> Map.get(@model_key, "")
    |> to_string()
  end

  def target_model(_target), do: ""

  @spec target_context_window(target() | term()) :: term()
  def target_context_window(target) when is_map(target), do: Map.get(target, @context_window_key)
  def target_context_window(_target), do: nil

  @spec target_artifact(target() | term()) :: artifact() | nil | term()
  def target_artifact(target) when is_map(target) do
    Map.get(target, @artifact_key, Map.get(target, @config_key))
  end

  def target_artifact(_target), do: nil

  @spec wardwright_model_target?(target() | term()) :: boolean()
  def wardwright_model_target?(target) when is_map(target) do
    Map.get(target, @target_kind_key) == @wardwright_model_kind or
      Map.get(target, @kind_key) == @wardwright_model_kind or
      is_map(Map.get(target, @artifact_key)) or is_map(Map.get(target, @config_key))
  end

  def wardwright_model_target?(_target), do: false

  @spec default_target_kind(target() | term()) :: String.t()
  def default_target_kind(target) do
    if is_map(target_artifact(target)), do: @wardwright_model_kind, else: "provider"
  end

  @spec ref_id(target(), artifact() | term()) :: model_id()
  def ref_id(target, artifact) when is_map(artifact) do
    artifact
    |> Map.get(@model_id_key, target_model(target))
    |> to_string()
  end

  def ref_id(target, _artifact), do: target_model(target)

  @spec provider_targets(artifact() | term()) :: [target()]
  def provider_targets(config) when is_map(config) do
    provider_targets(config, [], 0)
  end

  def provider_targets(_config), do: []

  @spec provider_targets(artifact(), visited_models(), non_neg_integer()) :: [target()]
  defp provider_targets(_config, _visited, depth) when depth > @max_depth, do: []

  defp provider_targets(config, visited, depth) do
    id = model_id(config, "")
    visited = if id == "", do: visited, else: [id | visited]

    config
    |> targets()
    |> Enum.flat_map(fn target ->
      if wardwright_model_target?(target) do
        artifact = target_artifact(target)
        ref_id = ref_id(target, artifact)

        if is_map(artifact) and ref_id not in visited do
          provider_targets(artifact, visited, depth + 1)
        else
          []
        end
      else
        [target]
      end
    end)
  end

  def provider_prefix(model) when is_binary(model) do
    model |> String.split("/", parts: 2) |> List.first()
  end

  def provider_prefix(_model), do: ""

  def lineage_step(config, decision, extra \\ %{}) do
    %{
      @model_key => model_id(config),
      @reason_key => decision.reason,
      @route_id_key => decision.route_id,
      @route_type_key => decision.route_type,
      @selected_context_window_key => decision.selected_context_window,
      @selected_model_key => decision.selected_model,
      @version_key => version(config)
    }
    |> Map.merge(extra)
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  def delegated_to_extra(target), do: %{@delegated_to_key => target_model(target)}
end
