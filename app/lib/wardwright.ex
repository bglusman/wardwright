defmodule Wardwright do
  @moduledoc """
  Minimal Wardwright model middleware runtime.

  The prototype is intentionally small: Wardwright model endpoints, model-graph
  route selection, policy evaluation, and in-memory receipts.
  """

  @model_id "coding-balanced"
  @model_version "2026-05-13.mock"
  @model_definition_version 1
  @local_model "local/qwen-coder"
  @managed_model "managed/kimi-k2.6"
  @local_context_window 32_768
  @managed_context_window 262_144
  @description_key "description"
  @default_description "Mock coding assistant Wardwright model with composable route selectors."
  @choice_index_key "index"
  @choices_key "choices"
  @content_key "content"
  @finish_reason_key "finish_reason"
  @message_key "message"
  @messages_key "messages"
  @name_key "name"
  @refusal_key "refusal"
  @role_key "role"
  @delta_key "delta"
  @preserved_delta_fields_key "preserved_delta_fields"
  @system_fingerprint_key "system_fingerprint"
  @tool_call_id_key "tool_call_id"
  @tool_calls_key "tool_calls"
  @usage_key "usage"

  def model_id, do: @model_id
  def model_id(config) when is_map(config), do: Map.get(config, "model_id", @model_id)
  def model_version, do: @model_version
  def model_definition_version, do: @model_definition_version
  def local_model, do: @local_model
  def managed_model, do: @managed_model
  def local_context_window, do: @local_context_window
  def managed_context_window, do: @managed_context_window

  def default_config do
    %{
      "alert_delivery" => %{"capacity" => 16, "on_full" => "dead_letter"},
      "alloys" => [],
      "auth" => %{"unkeyed_model_access" => "public"},
      "cascades" => [],
      "dispatchers" => [
        %{
          "id" => "dispatcher.prompt_length",
          "models" => [@local_model, @managed_model],
          "name" => "Use local until prompt length requires managed context"
        }
      ],
      "governance" => [%{"action" => "transform", "id" => "prompt_transforms", "kind" => "request_transform"}],
      "model_definition_version" => @model_definition_version,
      "model_id" => @model_id,
      "policy_cache" => %{"max_entries" => 64, "recent_limit" => 20},
      "prompt_transforms" => %{},
      "requires_api_key" => false,
      "route_root" => "dispatcher.prompt_length",
      "sinks" => [
        %{
          "delivery" => %{"capacity" => 16, "on_full" => "dead_letter"},
          "id" => "policy-alerts",
          "kind" => "memory_alert",
          "redaction" => "metadata",
          "select" => %{"types" => ["policy.alert"]}
        }
      ],
      "stream_rules" => [%{"action" => "pass", "id" => "mock_noop", "pattern" => ""}],
      "structured_output" => nil,
      "targets" => [
        %{"context_window" => @local_context_window, "model" => @local_model},
        %{"context_window" => @managed_context_window, "model" => @managed_model}
      ],
      "vcr" => %{"mode" => "metadata_only"},
      "version" => @model_version,
      @description_key => @default_description
    }
  end

  def current_config do
    configs = current_configs()
    active_model_id = :persistent_term.get({__MODULE__, :active_model_id}, @model_id)
    Map.get(configs, active_model_id, default_config())
  end

  def current_configs do
    :persistent_term.get({__MODULE__, :configs}, %{@model_id => default_config()})
  end

  def model_configs do
    current_configs()
    |> Map.values()
    |> Enum.sort_by(&model_id/1)
  end

  def model_config(model) do
    case canonical_model_id(model) do
      {:ok, model_id} ->
        case Map.fetch(current_configs(), model_id) do
          {:ok, config} -> {:ok, config}
          :error -> {:error, "unknown Wardwright model #{inspect(model)}"}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  def load_persisted_config do
    case Wardwright.SQLiteStore.list_active_models() do
      {:ok, configs} when configs != [] ->
        install_configs(configs)
        Enum.each(configs, &configure_runtime/1)
        {:ok, current_config()}

      _ ->
        config = default_config()
        install_configs([config])
        configure_runtime(config)
        Wardwright.SQLiteStore.save_model_config(config, replace_active: true)
        {:ok, config}
    end
  end

  def reset_config do
    config = default_config()
    install_configs([config])
    Wardwright.SQLiteStore.save_model_config(config, replace_active: true)
    Wardwright.PolicyCache.configure(default_config()["policy_cache"])
    Wardwright.Sinks.configure(default_config()["sinks"])
    Wardwright.ProviderRuntime.reset()
  end

  def put_config(config) when is_map(config) do
    config = normalize_config(config)

    with :ok <- validate_config(config) do
      install_configs([config])
      Wardwright.SQLiteStore.save_model_config(config, replace_active: true)
      configure_runtime(config)
      {:ok, config}
    end
  end

  def put_config(_), do: {:error, "request body must be a JSON object"}

  def put_model_config(config) when is_map(config) do
    config = normalize_config(config)

    with :ok <- validate_config(config) do
      install_model_config(config)
      Wardwright.SQLiteStore.save_model_config(config)
      configure_runtime(config)
      {:ok, config}
    end
  end

  def put_model_config(_), do: {:error, "request body must be a JSON object"}

  def archive_model_config(model) do
    with {:ok, model_id} <- canonical_model_id(model),
         {:ok, _config} <- model_config(model_id),
         :ok <- require_model_registry_store(),
         :ok <- require_archiveable_model(model_id) do
      remaining_configs = Map.delete(current_configs(), model_id)
      current_active_model_id = active_model_id()
      preferred_active_model_id = if current_active_model_id != model_id, do: current_active_model_id

      with {:ok, changed_count} <- model_registry_changed_count(Wardwright.SQLiteStore.archive_model_config(model_id)),
           true <- changed_count > 0 do
        install_configs(Map.values(remaining_configs), preferred_active_model_id)
        configure_runtime(current_config())
        {:ok, model_id}
      else
        false -> {:error, "unknown persisted Wardwright model #{inspect(model_id)}"}
        {:error, reason} -> {:error, "could not archive #{inspect(model_id)}: #{inspect(reason)}"}
      end
    end
  end

  def restore_archived_model_config(model) do
    with {:ok, model_id} <- canonical_model_id(model),
         :ok <- require_model_registry_store(),
         {:ok, config} <- archived_model_config_from_store(model_id),
         :ok <- validate_config(config),
         {:ok, _restored_config} <-
           model_registry_restored_config(Wardwright.SQLiteStore.restore_model_config(model_id)) do
      install_model_config(config)
      configure_runtime(config)
      {:ok, config}
    else
      {:error, :not_found} -> {:error, "unknown archived Wardwright model #{inspect(model)}"}
      {:error, message} -> {:error, message}
    end
  end

  def delete_archived_model_config(model) do
    with {:ok, model_id} <- canonical_model_id(model),
         :ok <- require_model_registry_store(),
         {:ok, _config} <- archived_model_config_from_store(model_id) do
      with {:ok, changed_count} <-
             model_registry_changed_count(Wardwright.SQLiteStore.delete_archived_model_config(model_id)),
           true <- changed_count > 0 do
        {:ok, model_id}
      else
        false -> {:error, "unknown archived Wardwright model #{inspect(model)}"}
        {:error, reason} -> {:error, "could not delete archived #{inspect(model)}: #{inspect(reason)}"}
      end
    else
      {:error, :not_found} -> {:error, "unknown archived Wardwright model #{inspect(model)}"}
      {:error, message} -> {:error, message}
    end
  end

  def archived_model_configs do
    {:ok, configs} = Wardwright.SQLiteStore.list_archived_models()
    configs
  end

  def archived_model_summaries, do: Enum.map(archived_model_configs(), &model_summary/1)

  defp install_configs(configs, preferred_active_model_id \\ nil) when is_list(configs) do
    configs = Map.new(configs, &{model_id(&1), &1})

    active_model_id =
      if is_binary(preferred_active_model_id) and Map.has_key?(configs, preferred_active_model_id) do
        preferred_active_model_id
      else
        configs |> Map.keys() |> Enum.sort() |> List.first() || @model_id
      end

    active_config = Map.get(configs, active_model_id, default_config())
    :persistent_term.put({__MODULE__, :config}, active_config)
    :persistent_term.put({__MODULE__, :configs}, configs)
    :persistent_term.put({__MODULE__, :active_model_id}, active_model_id)
  end

  defp install_model_config(config) do
    model_id = model_id(config)
    configs = Map.put(current_configs(), model_id, config)
    :persistent_term.put({__MODULE__, :config}, config)
    :persistent_term.put({__MODULE__, :configs}, configs)
    :persistent_term.put({__MODULE__, :active_model_id}, model_id)
  end

  defp require_archiveable_model(model_id) do
    if map_size(current_configs()) <= 1 do
      {:error, "cannot archive #{inspect(model_id)} because Wardwright needs at least one active model"}
    else
      :ok
    end
  end

  defp require_model_registry_store do
    if Wardwright.SQLiteStore.enabled?() do
      :ok
    else
      {:error, "model archive requires SQLite model registry storage"}
    end
  end

  defp archived_model_config_from_store(model_id) do
    case Wardwright.SQLiteStore.archived_model_config(model_id) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, reason}
    end
  end

  defp active_model_id do
    :persistent_term.get({__MODULE__, :active_model_id}, @model_id)
  end

  defp model_registry_changed_count({:ok, {:ok, count}}) when is_integer(count), do: {:ok, count}
  defp model_registry_changed_count({:ok, count}) when is_integer(count), do: {:ok, count}
  defp model_registry_changed_count({:error, reason}), do: {:error, reason}
  defp model_registry_changed_count(other), do: {:error, other}

  defp model_registry_restored_config({:ok, {:ok, config}}) when is_map(config), do: {:ok, config}
  defp model_registry_restored_config({:ok, {:error, reason}}), do: {:error, reason}
  defp model_registry_restored_config({:error, reason}), do: {:error, reason}
  defp model_registry_restored_config(other), do: {:error, other}

  defp configure_runtime(config) do
    if Process.whereis(Wardwright.PolicyCache) do
      Wardwright.PolicyCache.configure(config["policy_cache"])
    end

    if Process.whereis(Wardwright.Sinks) do
      Wardwright.Sinks.configure(config["sinks"])
    end

    if Process.whereis(Wardwright.ProviderRuntime) do
      Wardwright.ProviderRuntime.reset()
    end
  end

  def normalize_model(model) when is_binary(model) do
    with {:ok, config} <- model_config(model) do
      {:ok, model_id(config)}
    end
  end

  def normalize_model(_), do: {:error, "model is required"}

  defp canonical_model_id(model) when is_binary(model) do
    case String.trim(model) do
      "" -> {:error, "model is required"}
      "wardwright/" <> model_id -> {:ok, model_id}
      model_id -> {:ok, model_id}
    end
  end

  defp canonical_model_id(_), do: {:error, "model is required"}

  def model_requires_api_key?(config \\ current_config()), do: Map.get(config, "requires_api_key", false) == true

  def unkeyed_model_access(config \\ current_config()), do: get_in(config, ["auth", "unkeyed_model_access"]) || "public"

  def vcr_mode(config \\ current_config()) do
    get_in(config, ["vcr", "mode"]) || "metadata_only"
  end

  def full_session_vcr?(config \\ current_config()), do: vcr_mode(config) == "full_session"

  def externally_callable?(config \\ current_config()) do
    model_requires_api_key?(config) or unkeyed_model_access(config) == "public"
  end

  def select_route(estimated_prompt_tokens) do
    Wardwright.RoutePlanner.select(current_config(), estimated_prompt_tokens)
  end

  def select_route(estimated_prompt_tokens, attrs) when is_map(attrs) do
    Wardwright.RoutePlanner.select(current_config(), estimated_prompt_tokens, attrs)
  end

  def select_route(config, estimated_prompt_tokens, attrs) when is_map(config) and is_map(attrs) do
    Wardwright.RoutePlanner.select(config, estimated_prompt_tokens, attrs)
  end

  def provider_targets(config \\ current_config()) when is_map(config) do
    Wardwright.ModelGraph.provider_targets(config)
  end

  def estimate_prompt_tokens(messages) when is_list(messages) do
    chars =
      Enum.reduce(messages, 0, fn message, acc ->
        role = message |> Map.get("role", "") |> to_string()
        acc + String.length(role) + content_length(Map.get(message, "content"))
      end)

    max(1, div(chars + 3, 4))
  end

  def estimate_prompt_tokens(_), do: 1

  defp content_length(nil), do: 0
  defp content_length(value) when is_binary(value), do: String.length(value)

  defp content_length(value) when is_list(value) do
    Enum.reduce(value, 0, fn
      %{"text" => text}, acc when is_binary(text) -> acc + String.length(text)
      %{"content" => text}, acc when is_binary(text) -> acc + String.length(text)
      part, acc -> acc + byte_size(Jason.encode!(part))
    end)
  end

  defp content_length(value), do: byte_size(Jason.encode!(value))

  def model_record do
    model_record(current_config())
  end

  def model_record(config) when is_map(config) do
    model_id = model_id(config)

    targets =
      config
      |> Map.get("targets", [])
      |> Enum.sort_by(fn target -> {target["context_window"], target["model"]} end)

    target_ids = Enum.map(targets, &node_id(&1["model"]))

    nodes =
      selector_nodes(config, target_ids) ++
        Enum.map(targets, fn target ->
          %{
            "context_window" => target["context_window"],
            "id" => node_id(target["model"]),
            "provider_id" => target["model"] |> String.split("/", parts: 2) |> List.first(),
            "type" => "concrete_model",
            "upstream_model_id" => target["model"]
          }
        end)

    %{
      "active_version" => config["version"],
      "fallback_rate" => 0.0,
      "governance" => Map.get(config, "governance", []),
      "id" => model_id,
      "model_definition_version" => Map.get(config, "model_definition_version", @model_definition_version),
      "model_id" => model_id,
      "prompt_transforms" => Map.get(config, "prompt_transforms", %{}),
      "public_model_id" => model_id,
      "public_namespace" => "flat",
      "requires_api_key" => model_requires_api_key?(config),
      "route_graph" => %{"nodes" => nodes, "root" => Map.get(config, "route_root", "dispatcher.prompt_length")},
      "route_type" => root_route_type(config),
      "status" => "active",
      "stream_policy" => %{
        "buffer_tokens" => 256,
        "mode" => "buffered_horizon",
        "rules" => Map.get(config, "stream_rules", [])
      },
      "stream_trigger_count_24h" => 0,
      "structured_output" => Map.get(config, "structured_output"),
      "traffic_24h" => 0,
      "unkeyed_model_access" => unkeyed_model_access(config),
      "vcr" => Map.get(config, "vcr", %{"mode" => "metadata_only"}),
      @description_key => model_description(config)
    }
  end

  def model_summary do
    model_summary(current_config())
  end

  def model_summary(config) when is_map(config) do
    model_id = model_id(config)

    %{
      "active_version" => config["version"],
      "id" => model_id,
      "model_id" => model_id,
      "public_model_id" => model_id,
      "public_namespace" => "flat",
      "requires_api_key" => model_requires_api_key?(config),
      "route_type" => root_route_type(config),
      "status" => "active",
      "vcr" => Map.get(config, "vcr", %{"mode" => "metadata_only"}),
      @description_key => model_description(config)
    }
  end

  def model_records, do: Enum.map(model_configs(), &model_record/1)
  def model_summaries, do: Enum.map(model_configs(), &model_summary/1)

  defp model_description(config), do: :maps.get(@description_key, config, @default_description)

  def externally_callable_model_configs do
    Enum.filter(model_configs(), &externally_callable?/1)
  end

  defp selector_nodes(config, default_target_ids) do
    dispatchers =
      config
      |> Map.get("dispatchers", [])
      |> case do
        [] -> [%{"id" => "dispatcher.prompt_length", "models" => default_target_ids}]
        configured -> configured
      end
      |> Enum.map(fn dispatcher ->
        %{
          "id" => dispatcher["id"],
          "strategy" => "smallest_context_window",
          "targets" => selector_target_ids(dispatcher, "models"),
          "type" => "dispatcher"
        }
      end)

    cascades =
      config
      |> Map.get("cascades", [])
      |> Enum.map(fn cascade ->
        %{
          "id" => cascade["id"],
          "strategy" => "ordered_fallback",
          "targets" => selector_target_ids(cascade, "models"),
          "type" => "cascade"
        }
      end)

    alloys =
      config
      |> Map.get("alloys", [])
      |> Enum.map(fn alloy ->
        %{
          "id" => alloy["id"],
          "partial_context" => Map.get(alloy, "partial_context", false),
          "strategy" => Map.get(alloy, "strategy", "weighted"),
          "targets" => selector_target_ids(alloy, "constituents"),
          "type" => "alloy"
        }
      end)

    dispatchers ++ cascades ++ alloys
  end

  defp selector_target_ids(selector, key) do
    selector
    |> Map.get(key, Map.get(selector, "targets", []))
    |> Enum.map(fn
      model when is_binary(model) -> node_id(model)
      %{"model" => model} -> node_id(model)
      other -> node_id(to_string(other))
    end)
  end

  defp root_route_type(config) do
    root = Map.get(config, "route_root", "dispatcher.prompt_length")

    cond do
      Enum.any?(Map.get(config, "alloys", []), &(&1["id"] == root)) -> "alloy"
      Enum.any?(Map.get(config, "cascades", []), &(&1["id"] == root)) -> "cascade"
      true -> "dispatcher"
    end
  end

  def providers do
    model_configs()
    |> Enum.flat_map(&provider_targets/1)
    |> Enum.reduce(%{}, fn target, acc ->
      provider = target["model"] |> String.split("/", parts: 2) |> List.first()
      Map.put_new(acc, {provider, target["model"]}, target)
    end)
    |> Enum.map(fn {{provider, _model}, target} ->
      {kind, base_url} = provider_kind_and_base_url(provider, target)

      %{
        "base_url" => base_url,
        # boundary-map-ok
        "capabilities" => Wardwright.ProviderCapabilities.for_provider(kind, credential_source(target)),
        "credential_owner" => "wardwright",
        "credential_source" => credential_source(target),
        "health" => "healthy",
        "id" => provider,
        "kind" => kind
      }
    end)
  end

  def model_access(origin \\ "http://127.0.0.1:8787") do
    WardwrightWeb.ModelAccessProjection.build(
      model_configs(),
      Wardwright.ProviderRuntime.providers_status(),
      origin
    )
  end

  def complete_selected_model(selected_model, request, config) when is_map(config) do
    started = System.monotonic_time(:millisecond)

    target =
      config
      |> provider_targets()
      |> Enum.find(fn target -> target["model"] == selected_model end)

    case target do
      nil ->
        provider_outcome(nil, "completed", started, nil, false, true)

      target ->
        case validate_provider_request(target, request) do
          :ok ->
            Wardwright.ProviderRuntime.complete(target, request, fn ->
              complete_target(target, request)
            end)
            |> provider_outcome_from_result(started)

          {:error, reason} ->
            provider_outcome(nil, "provider_error", started, reason, false, false)
        end
    end
  end

  def stream_selected_model(selected_model, request, config) when is_map(config) do
    started = System.monotonic_time(:millisecond)

    target =
      config
      |> provider_targets()
      |> Enum.find(fn target -> target["model"] == selected_model end)

    case target do
      nil ->
        provider_outcome([], "completed", started, nil, false, true)

      target ->
        case validate_provider_request(target, request) do
          :ok ->
            Wardwright.ProviderRuntime.stream(target, request, fn ->
              stream_target(target, request)
            end)
            |> provider_outcome_from_result(started)
            |> normalize_stream_outcome()

          {:error, reason} ->
            provider_outcome(nil, "provider_error", started, reason, false, false)
        end
    end
  end

  def stream_selected_model_each(selected_model, request, acc, chunk_fun, config)
      when is_map(config) and is_function(chunk_fun, 2) do
    started = System.monotonic_time(:millisecond)

    target =
      config
      |> provider_targets()
      |> Enum.find(fn target -> target["model"] == selected_model end)

    case target do
      nil ->
        {result, acc} =
          stream_mock_chunks(
            [
              "Mock Wardwright stream ",
              "routed to #{selected_model} ",
              "for #{Map.get(request, "model")}."
            ],
            acc,
            chunk_fun
          )

        stream_each_outcome(acc, result, started, false, true)

      target ->
        case validate_provider_request(target, request) do
          :ok ->
            {result, acc} =
              Wardwright.ProviderRuntime.stream_each(
                target,
                request,
                fn emit -> stream_target_each(target, request, emit) end,
                acc,
                chunk_fun
              )

            stream_each_outcome(
              acc,
              result,
              started,
              provider_kind(target) != "mock",
              provider_kind(target) == "mock"
            )

          {:error, reason} ->
            {provider_outcome(nil, "provider_error", started, reason, false, false), acc}
        end
    end
  end

  defp validate_provider_request(target, request) do
    target
    |> provider_kind()
    |> Wardwright.ProviderCapabilities.validate_request(request)
  end

  defp complete_target(target, request) do
    case provider_kind(target) do
      "mock" ->
        {:mock, nil}

      "ollama" ->
        complete_with_ollama(target, request)

      "openai-compatible" ->
        complete_with_openai_compatible(target, request)

      "canned_sequence" ->
        complete_with_canned_sequence(target, request)

      kind ->
        {:error, "unsupported provider kind #{inspect(kind)}"}
    end
  end

  defp stream_target(target, request) do
    case provider_kind(target) do
      "mock" ->
        {:mock,
         [
           "Mock Wardwright stream ",
           "routed to #{target["model"]} ",
           "for #{Map.get(request, "model")}."
         ]}

      "canned_sequence" ->
        stream_with_canned_sequence(target, request)

      "ollama" ->
        stream_with_ollama(target, request)

      "openai-compatible" ->
        stream_with_openai_compatible(target, request)

      kind ->
        {:error, "unsupported provider kind #{inspect(kind)}"}
    end
  end

  defp stream_target_each(target, request, emit) do
    case provider_kind(target) do
      "mock" ->
        [
          "Mock Wardwright stream ",
          "routed to #{target["model"]} ",
          "for #{Map.get(request, "model")}."
        ]
        |> Enum.each(emit)

        {:mock, :done}

      "canned_sequence" ->
        stream_canned_sequence_each(target, request, emit)

      "ollama" ->
        stream_ollama_each(target, request, emit)

      "openai-compatible" ->
        stream_openai_compatible_each(target, request, emit)

      kind ->
        {:error, "unsupported provider kind #{inspect(kind)}"}
    end
  end

  defp complete_with_canned_sequence(target, request) do
    delay_ms = non_negative_integer(Map.get(target, "canned_delay_ms"), 0)
    if delay_ms > 0, do: Process.sleep(delay_ms)

    outputs = Map.get(target, "canned_outputs", [])
    attempt_index = request |> Map.get("wardwright_attempt_index", 0) |> integer_value() || 0

    case Enum.at(outputs, attempt_index) || List.last(outputs) do
      output when is_binary(output) -> {:ok, output}
      _ -> {:error, "canned_sequence target has no outputs"}
    end
  end

  defp stream_with_canned_sequence(target, request) do
    delay_ms = non_negative_integer(Map.get(target, "canned_delay_ms"), 0)
    if delay_ms > 0, do: Process.sleep(delay_ms)

    attempt_index = request |> Map.get("wardwright_attempt_index", 0) |> integer_value() || 0

    chunks =
      target
      |> Map.get("canned_stream_attempt_chunks", [])
      |> attempt_stream_chunks(attempt_index)
      |> case do
        [] -> Map.get(target, "canned_stream_chunks", [])
        chunks -> chunks
      end
      |> case do
        [] ->
          target
          |> Map.get("canned_outputs", [])
          |> Enum.at(attempt_index)
          |> case do
            output when is_binary(output) -> chunk_text(output)
            _ -> []
          end

        chunks ->
          chunks
      end

    case chunks do
      chunks when is_list(chunks) and chunks != [] -> {:ok, Enum.map(chunks, &to_string/1)}
      _ -> {:error, "canned_sequence target has no stream chunks"}
    end
  end

  defp stream_canned_sequence_each(target, request, emit) do
    delay_ms = non_negative_integer(Map.get(target, "canned_delay_ms"), 0)
    stream_error = blank_to_nil(to_string(Map.get(target, "canned_stream_error", "")))

    target
    |> canned_stream_chunks(request)
    |> case do
      chunks when is_list(chunks) and chunks != [] ->
        Enum.each(chunks, fn chunk ->
          if delay_ms > 0, do: Process.sleep(delay_ms)
          emit.(to_string(chunk))
        end)

        case stream_error do
          nil -> {:ok, :done}
          reason -> {:error, reason}
        end

      _ ->
        {:error, "canned_sequence target has no stream chunks"}
    end
  end

  defp canned_stream_chunks(target, request) do
    attempt_index = request |> Map.get("wardwright_attempt_index", 0) |> integer_value() || 0

    target
    |> Map.get("canned_stream_attempt_chunks", [])
    |> attempt_stream_chunks(attempt_index)
    |> case do
      [] -> Map.get(target, "canned_stream_chunks", [])
      chunks -> chunks
    end
    |> case do
      [] ->
        target
        |> Map.get("canned_outputs", [])
        |> Enum.at(attempt_index)
        |> case do
          output when is_binary(output) -> chunk_text(output)
          _ -> []
        end

      chunks ->
        chunks
    end
  end

  defp attempt_stream_chunks(attempt_chunks, attempt_index)
       when is_list(attempt_chunks) and is_integer(attempt_index) do
    case Enum.at(attempt_chunks, attempt_index) do
      chunks when is_list(chunks) -> chunks
      _ -> []
    end
  end

  defp attempt_stream_chunks(_attempt_chunks, _attempt_index), do: []

  defp chunk_text(text) when is_binary(text) do
    [text]
  end

  def normalize_config(config) do
    model_id =
      config
      |> Map.get("model_id", "")
      |> to_string()
      |> String.trim()

    %{
      "alert_delivery" => normalize_alert_delivery(Map.get(config, "alert_delivery", %{})),
      "alloys" => normalize_selectors(Map.get(config, "alloys", []), "constituents"),
      "auth" => normalize_auth(Map.get(config, "auth", %{})),
      "cascades" => normalize_selectors(Map.get(config, "cascades", []), "models"),
      "dispatchers" => normalize_selectors(Map.get(config, "dispatchers", []), "models"),
      "governance" => Map.get(config, "governance", []),
      "model_definition_version" =>
        config
        |> Map.get("model_definition_version", @model_definition_version)
        |> positive_integer(@model_definition_version),
      "model_id" => model_id,
      "policy_cache" => normalize_policy_cache(Map.get(config, "policy_cache", %{})),
      "prompt_transforms" => Map.get(config, "prompt_transforms", %{}),
      "requires_api_key" => Map.get(config, "requires_api_key", false) == true,
      "route_root" =>
        config
        |> Map.get("route_root", "dispatcher.prompt_length")
        |> to_string()
        |> String.trim()
        |> then(fn
          "" -> "dispatcher.prompt_length"
          route_root -> route_root
        end),
      "sinks" =>
        Wardwright.Sinks.normalize_config(
          Map.get(config, "sinks"),
          normalize_alert_delivery(Map.get(config, "alert_delivery", %{}))
        ),
      "stream_rules" => Map.get(config, "stream_rules", []),
      "structured_output" => Map.get(config, "structured_output"),
      "targets" =>
        config
        |> Map.get("targets", [])
        |> Enum.map(fn target ->
          normalized_target = %{
            "canned_delay_ms" => non_negative_integer(Map.get(target, "canned_delay_ms"), 0),
            "canned_outputs" => normalize_canned_outputs(Map.get(target, "canned_outputs", [])),
            "canned_stream_attempt_chunks" =>
              normalize_canned_stream_attempt_chunks(Map.get(target, "canned_stream_attempt_chunks", [])),
            "canned_stream_chunks" => normalize_canned_outputs(Map.get(target, "canned_stream_chunks", [])),
            "canned_stream_error" => target |> Map.get("canned_stream_error", "") |> to_string() |> String.trim(),
            "context_window" => integer_value(Map.get(target, "context_window")),
            "credential_env" => target |> Map.get("credential_env", "") |> to_string() |> String.trim(),
            "credential_fnox_key" => target |> Map.get("credential_fnox_key", "") |> to_string() |> String.trim(),
            "model" => target |> Map.get("model", "") |> to_string() |> String.trim(),
            "provider_base_url" => target |> Map.get("provider_base_url", "") |> to_string() |> String.trim(),
            "provider_headers" => normalize_headers(Map.get(target, "provider_headers", %{})),
            "provider_kind" => target |> Map.get("provider_kind", "") |> to_string() |> String.trim(),
            "provider_timeout_ms" => positive_integer(Map.get(target, "provider_timeout_ms"), 180_000),
            "target_kind" =>
              target
              |> Map.get("target_kind", Map.get(target, "kind", Wardwright.ModelGraph.default_target_kind(target)))
              |> to_string()
              |> String.trim()
          }

          normalized_target =
            case Wardwright.ModelGraph.target_artifact(target) do
              artifact when is_map(artifact) -> Map.put(normalized_target, "artifact", normalize_config(artifact))
              _other -> normalized_target
            end

          normalized_target |> Enum.reject(fn {_key, value} -> value == "" or value == [] end) |> Map.new()
        end),
      "vcr" => normalize_vcr(Map.get(config, "vcr", %{})),
      "version" =>
        config
        |> Map.get("version", @model_version)
        |> to_string()
        |> String.trim()
        |> then(fn
          "" -> @model_version
          version -> version
        end),
      @description_key => normalize_description(config)
    }
  end

  defp normalize_description(config) do
    config
    |> model_description()
    |> to_string()
    |> String.trim()
    |> then(fn
      "" -> @default_description
      description -> description
    end)
  end

  defp normalize_canned_outputs(outputs) when is_list(outputs), do: Enum.map(outputs, &to_string/1)

  defp normalize_canned_outputs(_), do: []

  defp normalize_canned_stream_attempt_chunks(attempts) when is_list(attempts) do
    Enum.map(attempts, &normalize_canned_outputs/1)
  end

  defp normalize_canned_stream_attempt_chunks(_), do: []

  defp normalize_selectors(selectors, model_key) when is_list(selectors) do
    Enum.map(selectors, fn selector ->
      %{
        "fallback_model" => selector |> Map.get("fallback_model", "") |> to_string() |> String.trim(),
        "id" => selector |> Map.get("id", "") |> to_string() |> String.trim(),
        "min_context_window" => integer_value(Map.get(selector, "min_context_window")),
        "name" => selector |> Map.get("name", "") |> to_string() |> String.trim(),
        "partial_context" => Map.get(selector, "partial_context", false) == true,
        "strategy" => selector |> Map.get("strategy", "") |> to_string() |> String.trim(),
        model_key => normalize_selector_models(Map.get(selector, model_key, Map.get(selector, "targets", [])))
      }
      |> Enum.reject(fn {_key, value} -> value in ["", nil, []] end)
      |> Map.new()
    end)
  end

  defp normalize_selectors(_selectors, _model_key), do: []

  defp normalize_selector_models(models) when is_list(models) do
    Enum.map(models, fn
      model when is_binary(model) ->
        String.trim(model)

      model when is_map(model) ->
        %{
          "context_window" => integer_value(Map.get(model, "context_window")),
          "model" => model |> Map.get("model", "") |> to_string() |> String.trim(),
          "weight" => integer_value(Map.get(model, "weight"))
        }
        |> Enum.reject(fn {_key, value} -> value in ["", nil] end)
        |> Map.new()

      model ->
        to_string(model)
    end)
  end

  defp normalize_selector_models(_models), do: []

  defp normalize_alert_delivery(config) when is_map(config) do
    %{
      "capacity" => non_negative_integer(Map.get(config, "capacity"), 16),
      "on_full" =>
        case Map.get(config, "on_full") do
          value when value in ["drop", "dead_letter", "fail_closed"] -> value
          _ -> "dead_letter"
        end
    }
  end

  defp normalize_alert_delivery(_), do: %{"capacity" => 16, "on_full" => "dead_letter"}

  defp normalize_policy_cache(config) when is_map(config) do
    %{
      "max_entries" => positive_integer(Map.get(config, "max_entries"), 64),
      "recent_limit" => positive_integer(Map.get(config, "recent_limit"), 20)
    }
  end

  defp normalize_policy_cache(_), do: %{"max_entries" => 64, "recent_limit" => 20}

  defp normalize_auth(config) when is_map(config) do
    access =
      case Map.get(config, "unkeyed_model_access", "public") do
        value when value in ["public", "internal"] -> value
        _ -> "public"
      end

    %{"unkeyed_model_access" => access}
  end

  defp normalize_auth(_), do: %{"unkeyed_model_access" => "public"}

  defp normalize_vcr(config) when is_map(config) do
    mode =
      case Map.get(config, "mode", "metadata_only") do
        value when value in ["metadata_only", "full_session"] -> value
        _ -> "metadata_only"
      end

    %{"mode" => mode}
  end

  defp normalize_vcr(_), do: %{"mode" => "metadata_only"}

  defp validate_config(%{"model_id" => model_id, "targets" => targets} = config) do
    cond do
      model_id == "" ->
        {:error, "model_id must not be empty"}

      String.contains?(model_id, "/") ->
        {:error, "model_id must be unprefixed"}

      targets == [] ->
        {:error, "targets must not be empty"}

      true ->
        with :ok <- validate_targets(targets) do
          Wardwright.RoutePlanner.validate(config)
        end
    end
  end

  defp validate_targets(targets) do
    Enum.reduce_while(targets, MapSet.new(), fn target, seen ->
      cond do
        Wardwright.ModelGraph.target_model(target) == "" ->
          {:halt, {:error, "target model must not be empty"}}

        not is_integer(Wardwright.ModelGraph.target_context_window(target)) or
            Wardwright.ModelGraph.target_context_window(target) <= 0 ->
          {:halt, {:error, "target #{Wardwright.ModelGraph.target_model(target)} context_window must be positive"}}

        MapSet.member?(seen, Wardwright.ModelGraph.target_model(target)) ->
          {:halt, {:error, "duplicate target #{Wardwright.ModelGraph.target_model(target)}"}}

        credential_reference?(target) and
            System.get_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS") != "1" ->
          {:halt, {:error, "credential references in __test/config require WARDWRIGHT_ALLOW_TEST_CREDENTIALS=1"}}

        Wardwright.ModelGraph.wardwright_model_target?(target) and
            not is_map(Wardwright.ModelGraph.target_artifact(target)) ->
          {:halt, {:error, "model target #{Wardwright.ModelGraph.target_model(target)} must include artifact"}}

        true ->
          {:cont, MapSet.put(seen, Wardwright.ModelGraph.target_model(target))}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      other -> other
    end
  end

  defp node_id(model), do: String.replace(model, "/", ".")

  defp credential_reference?(target) do
    Map.get(target, "credential_env", "") != "" or
      Map.get(target, "credential_fnox_key", "") != ""
  end

  defp provider_kind_and_base_url(provider, target) do
    kind = provider_kind(target)
    base_url = Map.get(target, "provider_base_url", "")

    cond do
      base_url != "" ->
        {kind, public_provider_base_url(base_url)}

      provider == "ollama" ->
        {"ollama",
         System.get_env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
         |> public_provider_base_url()}

      true ->
        {kind, "mock://#{provider}"}
    end
  end

  defp public_provider_base_url(base_url) when is_binary(base_url) do
    case URI.parse(base_url) do
      %URI{host: host, scheme: scheme} = uri when is_binary(scheme) and is_binary(host) ->
        path = uri.path || ""
        port = if uri.port in [nil, 80, 443], do: "", else: ":#{uri.port}"
        "#{scheme}://#{host}#{port}#{path}"

      _ ->
        base_url
    end
  end

  defp public_provider_base_url(base_url), do: base_url

  defp provider_kind(target) do
    cond do
      Map.get(target, "provider_kind", "") != "" -> target["provider_kind"]
      String.starts_with?(target["model"], "ollama/") -> "ollama"
      true -> "mock"
    end
  end

  defp credential_source(target) do
    cond do
      Map.get(target, "credential_fnox_key", "") != "" -> "fnox"
      Map.get(target, "credential_env", "") != "" -> "env"
      true -> "none"
    end
  end

  defp complete_with_ollama(target, request) do
    model = provider_model(target)

    base_url =
      Map.get(target, "provider_base_url") ||
        System.get_env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")

    body =
      Jason.encode!(%{
        messages: provider_messages(request),
        model: model,
        stream: false
      })
      |> encode_provider_body(request, ["tools"])

    http_post("#{String.trim_trailing(base_url, "/")}/api/chat", body, [])
    |> case do
      {:ok, response} -> {:ok, get_in(response, ["message", "content"]) || ""}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_with_ollama(target, request) do
    model = provider_model(target)

    base_url =
      Map.get(target, "provider_base_url") ||
        System.get_env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")

    body =
      Jason.encode!(%{
        messages: provider_messages(request),
        model: model,
        stream: true
      })
      |> encode_provider_body(request, ["tools"])

    "#{String.trim_trailing(base_url, "/")}/api/chat"
    |> http_post_stream(body, [])
    |> case do
      {:ok, response_body} -> {:ok, parse_ollama_stream_chunks(response_body)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_ollama_each(target, request, emit) do
    model = provider_model(target)

    base_url =
      Map.get(target, "provider_base_url") ||
        System.get_env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")

    body =
      Jason.encode!(%{
        messages: provider_messages(request),
        model: model,
        stream: true
      })
      |> encode_provider_body(request, ["tools"])

    "#{String.trim_trailing(base_url, "/")}/api/chat"
    |> http_post_stream_each(
      body,
      [],
      {:lines, "", stream_metadata("ollama_ndjson")},
      &parse_ollama_stream_part/3,
      emit
    )
  end

  defp complete_with_openai_compatible(target, request) do
    with base_url when base_url != "" <- Map.get(target, "provider_base_url", ""),
         {:ok, credential} <- provider_credential(target) do
      body =
        Jason.encode!(%{
          messages: provider_messages(request),
          model: provider_model(target),
          stream: false
        })
        |> encode_provider_body(request, openai_compatible_forward_fields())

      headers = provider_headers(target) ++ [{~c"authorization", ~c"Bearer #{credential}"}]

      "#{String.trim_trailing(base_url, "/")}/chat/completions"
      |> http_post(body, headers)
      |> case do
        {:ok, response} ->
          {:ok, openai_chat_message_result(response)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      "" -> {:error, "provider_base_url is required for openai-compatible targets"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_with_openai_compatible(target, request) do
    with base_url when base_url != "" <- Map.get(target, "provider_base_url", ""),
         {:ok, credential} <- provider_credential(target) do
      body =
        Jason.encode!(%{
          messages: provider_messages(request),
          model: provider_model(target),
          stream: true
        })
        |> encode_provider_body(request, openai_compatible_forward_fields())

      headers = provider_headers(target) ++ [{~c"authorization", ~c"Bearer #{credential}"}]

      "#{String.trim_trailing(base_url, "/")}/chat/completions"
      |> http_post_stream(body, headers)
      |> case do
        {:ok, response_body} -> {:ok, parse_openai_sse_chunks(response_body)}
        {:error, reason} -> {:error, reason}
      end
    else
      "" -> {:error, "provider_base_url is required for openai-compatible targets"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_openai_compatible_each(target, request, emit) do
    with base_url when base_url != "" <- Map.get(target, "provider_base_url", ""),
         {:ok, credential} <- provider_credential(target) do
      body =
        Jason.encode!(%{
          messages: provider_messages(request),
          model: provider_model(target),
          stream: true
        })
        |> encode_provider_body(request, openai_compatible_forward_fields())

      headers = provider_headers(target) ++ [{~c"authorization", ~c"Bearer #{credential}"}]

      "#{String.trim_trailing(base_url, "/")}/chat/completions"
      |> http_post_stream_each(
        body,
        headers,
        {:sse, "", stream_metadata("openai_sse")},
        &parse_openai_sse_part/3,
        emit
      )
    else
      "" -> {:error, "provider_base_url is required for openai-compatible targets"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp http_post(url, body, headers) do
    request = {
      String.to_charlist(url),
      [{~c"content-type", ~c"application/json"} | headers],
      ~c"application/json",
      body
    }

    case :httpc.request(:post, request, [{:timeout, 180_000}], body_format: :binary) do
      {:ok, {{_, status, _}, _headers, response_body}} when status in 200..299 ->
        Jason.decode(response_body)

      {:ok, {{_, status, _}, _headers, _response_body}} ->
        {:error, "provider returned #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp http_post_stream(url, body, headers) do
    request = {
      String.to_charlist(url),
      [{~c"content-type", ~c"application/json"} | headers],
      ~c"application/json",
      body
    }

    case :httpc.request(
           :post,
           request,
           [{:timeout, 180_000}],
           sync: false,
           stream: {:self, :once}
         ) do
      {:ok, request_id} ->
        collect_http_stream(request_id, [], nil)

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp http_post_stream_each(url, body, headers, parser_state, parser_fun, emit) do
    request = {
      String.to_charlist(url),
      [{~c"content-type", ~c"application/json"} | headers],
      ~c"application/json",
      body
    }

    case :httpc.request(
           :post,
           request,
           [{:timeout, 180_000}],
           sync: false,
           stream: {:self, :once}
         ) do
      {:ok, request_id} ->
        collect_http_stream_each(request_id, nil, parser_state, parser_fun, emit)

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp collect_http_stream(request_id, parts, handler_pid) do
    receive do
      {:http, {^request_id, :stream_start, _headers, pid}} ->
        :ok = :httpc.stream_next(pid)
        collect_http_stream(request_id, parts, pid)

      {:http, {^request_id, :stream_start, _headers}} ->
        collect_http_stream(request_id, parts, handler_pid)

      {:http, {^request_id, :stream, part}} ->
        if handler_pid, do: :ok = :httpc.stream_next(handler_pid)
        collect_http_stream(request_id, [part | parts], handler_pid)

      {:http, {^request_id, :stream_end, _headers}} ->
        {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}

      {:http, {^request_id, {{_, status, _}, _headers, response_body}}}
      when status in 200..299 ->
        {:ok, response_body}

      {:http, {^request_id, {{_, status, _}, _headers, _response_body}}} ->
        {:error, "provider returned #{status}"}

      {:http, {^request_id, {:error, reason}}} ->
        {:error, inspect(reason)}
    after
      180_000 ->
        :httpc.cancel_request(request_id)
        {:error, "provider stream timed out after 180000ms"}
    end
  end

  defp collect_http_stream_each(request_id, handler_pid, parser_state, parser_fun, emit) do
    receive do
      {_stream_ref, :cancel} ->
        :httpc.cancel_request(request_id)
        {:error, "provider stream cancelled"}

      {:http, {^request_id, :stream_start, _headers, pid}} ->
        :ok = :httpc.stream_next(pid)
        collect_http_stream_each(request_id, pid, parser_state, parser_fun, emit)

      {:http, {^request_id, :stream_start, _headers}} ->
        collect_http_stream_each(request_id, handler_pid, parser_state, parser_fun, emit)

      {:http, {^request_id, :stream, part}} ->
        if handler_pid, do: :ok = :httpc.stream_next(handler_pid)
        parser_state = parser_fun.(IO.iodata_to_binary(part), parser_state, emit)
        collect_http_stream_each(request_id, handler_pid, parser_state, parser_fun, emit)

      {:http, {^request_id, :stream_end, _headers}} ->
        parser_state = finalize_stream_parser(parser_state, parser_fun, emit)
        {:ok, stream_parser_result(parser_state)}

      {:http, {^request_id, {{_, status, _}, _headers, response_body}}}
      when status in 200..299 ->
        parser_state =
          response_body
          |> IO.iodata_to_binary()
          |> parser_fun.(parser_state, emit)
          |> finalize_stream_parser(parser_fun, emit)

        {:ok, stream_parser_result(parser_state)}

      {:http, {^request_id, {{_, status, _}, _headers, _response_body}}} ->
        {:error, "provider returned #{status}"}

      {:http, {^request_id, {:error, reason}}} ->
        {:error, inspect(reason)}
    after
      180_000 ->
        :httpc.cancel_request(request_id)
        {:error, "provider stream timed out after 180000ms"}
    end
    |> case do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  defp parse_ollama_stream_part(part, {:lines, pending}, emit) do
    parse_ollama_stream_part(part, {:lines, pending, stream_metadata("ollama_ndjson")}, emit)
    |> then(fn {:lines, pending, _metadata} -> {:lines, pending} end)
  end

  defp parse_ollama_stream_part(part, {:lines, pending, metadata}, emit) do
    {lines, pending} = split_stream_lines(pending <> part)

    metadata =
      Enum.reduce(lines, metadata, fn line, metadata ->
        case Jason.decode(String.trim(line)) do
          {:ok, event} ->
            metadata = ollama_stream_metadata(metadata, event)

            content =
              json_get(json_get(event, "message"), "content") || json_get(event, "response")

            if content not in [nil, ""], do: emit.(content)
            metadata

          {:error, _} ->
            metadata
        end
      end)

    {:lines, pending, metadata}
  end

  defp finalize_stream_parser({:lines, _pending} = parser_state, parser_fun, emit) do
    parser_fun.("\n", parser_state, emit)
  end

  defp finalize_stream_parser({:lines, _pending, _metadata} = parser_state, parser_fun, emit) do
    parser_fun.("\n", parser_state, emit)
  end

  defp finalize_stream_parser({:sse, _pending} = parser_state, parser_fun, emit) do
    parser_fun.("\n\n", parser_state, emit)
  end

  defp finalize_stream_parser({:sse, _pending, _metadata} = parser_state, parser_fun, emit) do
    parser_fun.("\n\n", parser_state, emit)
  end

  defp stream_parser_metadata({:sse, _pending, metadata}) when map_size(metadata) > 0, do: metadata

  defp stream_parser_metadata({:lines, _pending, metadata}) when map_size(metadata) > 0, do: metadata

  defp stream_parser_metadata(_parser_state), do: nil

  defp stream_parser_result(parser_state) do
    case stream_parser_metadata(parser_state) do
      nil -> :done
      metadata -> {:provider_metadata, metadata}
    end
  end

  defp ollama_stream_metadata(metadata, event) do
    metadata
    |> put_if_present("done", json_get(event, "done"))
    |> put_if_present("done_reason", json_get(event, "done_reason"))
    |> put_if_present("total_duration", json_get(event, "total_duration"))
    |> put_if_present("load_duration", json_get(event, "load_duration"))
    |> put_if_present("prompt_eval_count", json_get(event, "prompt_eval_count"))
    |> put_if_present("eval_count", json_get(event, "eval_count"))
  end

  defp parse_openai_sse_part(part, {:sse, pending}, emit) do
    parse_openai_sse_part(part, {:sse, pending, stream_metadata("openai_sse")}, emit)
    |> then(fn {:sse, pending, _metadata} -> {:sse, pending} end)
  end

  defp parse_openai_sse_part(part, {:sse, pending, metadata}, emit) do
    {events, pending} = split_sse_events(pending <> part)

    metadata =
      Enum.reduce(events, metadata, fn event, metadata ->
        event
        |> String.split(["\r\n", "\n"], trim: true)
        |> Enum.flat_map(&sse_data_values/1)
        |> Enum.reduce(metadata, fn
          "[DONE]", metadata ->
            put_if_present(metadata, "done", true)

          data, metadata ->
            case Jason.decode(data) do
              {:ok, event} ->
                choice = openai_choice(event)
                metadata = openai_stream_metadata(metadata, event)

                content =
                  choice
                  |> openai_choice_content()

                if openai_choice_tool_calls?(choice), do: emit.(openai_tool_call_delta(choice))
                if content not in [nil, ""], do: emit.(content)
                metadata

              {:error, _} ->
                metadata
            end
        end)
      end)

    {:sse, pending, metadata}
  end

  defp openai_stream_metadata(metadata, event) do
    choice = openai_choice(event)

    metadata
    |> put_if_present("finish_reason", json_get(choice, "finish_reason"))
    |> put_if_present("choice_index", json_get(choice, "index"))
    |> put_if_present("usage", json_get(event, "usage"))
    |> put_if_present("system_fingerprint", json_get(event, "system_fingerprint"))
    |> put_if_present("refusal", json_get(json_get(choice, "delta"), "refusal"))
    |> put_preserved_delta_field(choice, @tool_calls_key)
  end

  defp stream_metadata(format), do: put_if_present(%{}, "stream_format", format)

  defp openai_choice(event) do
    case json_get(event, "choices") do
      [choice | _] when is_map(choice) -> choice
      _ -> %{}
    end
  end

  defp openai_choice_content(choice) do
    json_get(json_get(choice, "delta"), "content") ||
      json_get(json_get(choice, "message"), "content")
  end

  defp openai_choice_tool_calls?(choice) do
    case json_get(json_get(choice, @delta_key), @tool_calls_key) do
      calls when is_list(calls) -> calls != []
      _ -> false
    end
  end

  defp openai_tool_call_delta(choice) do
    %{
      wardwright_stream_choice_index: json_get(choice, "index") || 0,
      wardwright_stream_delta: %{@tool_calls_key => json_get(json_get(choice, @delta_key), @tool_calls_key)}
    }
  end

  defp put_preserved_delta_field(metadata, choice, field) do
    case json_get(json_get(choice, @delta_key), field) do
      value when value in [nil, []] ->
        metadata

      _value ->
        fields =
          metadata
          |> Map.get(@preserved_delta_fields_key, [])
          |> List.wrap()
          |> Kernel.++([field])
          |> Enum.uniq()
          |> Enum.sort()

        Map.put(metadata, @preserved_delta_fields_key, fields)
    end
  end

  defp json_get(map, key) when is_map(map), do: Map.get(map, key)
  defp json_get(_value, _key), do: nil

  defp sse_data_values("data:" <> data), do: [String.trim(data)]
  defp sse_data_values(_line), do: []

  defp split_stream_lines(buffer) do
    parts = String.split(buffer, ["\r\n", "\n"])

    case parts do
      [] -> {[], ""}
      parts -> {Enum.slice(parts, 0, max(length(parts) - 1, 0)), List.last(parts) || ""}
    end
  end

  defp split_sse_events(buffer) do
    cond do
      String.contains?(buffer, "\n\n") ->
        parts = String.split(buffer, "\n\n")
        {Enum.slice(parts, 0, max(length(parts) - 1, 0)), List.last(parts) || ""}

      String.contains?(buffer, "\r\n\r\n") ->
        parts = String.split(buffer, "\r\n\r\n")
        {Enum.slice(parts, 0, max(length(parts) - 1, 0)), List.last(parts) || ""}

      true ->
        {[], buffer}
    end
  end

  defp parse_ollama_stream_chunks(response_body) do
    response_body
    |> stream_lines()
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, event} -> [get_in(event, ["message", "content"]) || event["response"]]
        {:error, _} -> []
      end
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp parse_openai_sse_chunks(response_body) do
    response_body
    |> stream_lines()
    |> Enum.flat_map(fn
      "data: [DONE]" ->
        []

      "data: " <> data ->
        case Jason.decode(data) do
          {:ok, event} ->
            [
              get_in(event, ["choices", Access.at(0), "delta", "content"]) ||
                get_in(event, ["choices", Access.at(0), "message", "content"])
            ]

          {:error, _} ->
            []
        end

      _line ->
        []
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp stream_lines(response_body) when is_binary(response_body) do
    response_body
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp provider_credential(target) do
    cond do
      Map.get(target, "credential_env", "") != "" ->
        key = target["credential_env"]

        System.get_env(key)
        |> blank_to_nil()
        |> case do
          nil -> {:error, "credential env var #{key} is not set"}
          value -> {:ok, value}
        end

      Map.get(target, "credential_fnox_key", "") != "" ->
        key = target["credential_fnox_key"]

        case System.cmd("fnox", ["get", key], stderr_to_stdout: false) do
          {value, 0} ->
            case blank_to_nil(value) do
              nil -> {:error, "fnox credential #{key} is empty"}
              value -> {:ok, value}
            end

          {_output, _status} ->
            {:error, "fnox credential #{key} is unavailable"}
        end

      true ->
        {:error, "credential_env or credential_fnox_key is required"}
    end
  end

  defp provider_model(target) do
    target["model"]
    |> String.split("/", parts: 2)
    |> case do
      [_provider, model] -> model
      [model] -> model
    end
  end

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {key, value} ->
      {key |> to_string() |> String.trim(), value |> to_string() |> String.trim()}
    end)
    |> Enum.reject(fn {key, value} ->
      key == "" or value == "" or String.downcase(key) == "authorization"
    end)
    |> Map.new()
  end

  defp normalize_headers(_), do: %{}

  defp provider_headers(target) do
    target
    |> Map.get("provider_headers", %{})
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  defp provider_messages(request) do
    request
    |> json_get(@messages_key)
    |> Kernel.||([])
    |> Enum.filter(&is_map/1)
    |> Enum.map(&provider_message/1)
  end

  defp provider_message(message) do
    %{}
    |> put_if_present(:content, json_get(message, @content_key))
    |> put_if_present(:name, json_get(message, @name_key))
    |> put_if_present(:role, json_get(message, @role_key) || "")
    |> put_if_present(:tool_call_id, json_get(message, @tool_call_id_key))
    |> put_if_present(:tool_calls, json_get(message, @tool_calls_key))
  end

  defp encode_provider_body(encoded_body, request, forward_fields) when is_binary(encoded_body) do
    encoded_body
    |> Jason.decode!()
    |> Map.merge(forward_request_fields(request, forward_fields))
    |> Jason.encode!()
  end

  defp forward_request_fields(request, fields) do
    fields
    |> Enum.reduce(%{}, fn field, acc ->
      put_if_present(acc, field, Map.get(request, field))
    end)
  end

  defp openai_compatible_forward_fields do
    [
      "frequency_penalty",
      "max_completion_tokens",
      "max_tokens",
      "presence_penalty",
      "response_format",
      "seed",
      "stop",
      "temperature",
      "tool_choice",
      "tools",
      "top_p"
    ]
  end

  defp openai_chat_message_result(response) do
    choice = response |> json_get(@choices_key) |> List.wrap() |> List.first() || %{}

    message =
      case json_get(choice, @message_key) || %{} do
        message when is_map(message) -> message
        _message -> %{}
      end

    metadata =
      %{}
      |> put_if_present("choice_index", json_get(choice, @choice_index_key))
      |> put_if_present("finish_reason", json_get(choice, @finish_reason_key))
      |> put_if_present("refusal", json_get(message, @refusal_key))
      |> put_if_present("system_fingerprint", json_get(response, @system_fingerprint_key))
      |> put_if_present("usage", json_get(response, @usage_key))

    {:chat_message, normalize_openai_assistant_message(message), metadata}
  end

  defp normalize_openai_assistant_message(message) when is_map(message) do
    case json_get(message, @role_key) do
      role when is_binary(role) and role != "" -> message
      _role -> Map.put(message, @role_key, "assistant")
    end
  end

  defp provider_outcome_from_result({:ok, {:provider_metadata, metadata}}, started) do
    nil
    |> provider_outcome("completed", started, nil, true, false)
    |> Map.put(:provider_metadata, metadata)
  end

  defp provider_outcome_from_result({:ok, {:chat_message, message, metadata}}, started) do
    message
    |> json_get(@content_key)
    |> provider_outcome("completed", started, nil, true, false)
    |> Map.put(:provider_metadata, metadata)
    |> Map.put(:response_message, message)
  end

  defp provider_outcome_from_result({:ok, content}, started) do
    provider_outcome(content, "completed", started, nil, true, false)
  end

  defp provider_outcome_from_result({:mock, content}, started) do
    provider_outcome(content, "completed", started, nil, false, true)
  end

  defp provider_outcome_from_result({:error, reason}, started) do
    provider_outcome(nil, "provider_error", started, reason, true, false)
  end

  defp provider_outcome(content, status, started, error, called_provider, mock) do
    %{
      called_provider: called_provider,
      content: content,
      error: error,
      latency_ms: max(0, System.monotonic_time(:millisecond) - started),
      mock: mock,
      status: status
    }
  end

  defp normalize_stream_outcome(%{content: chunks} = outcome) when is_list(chunks) do
    outcome
    |> Map.put(:content, Enum.join(chunks, ""))
    |> Map.put(:stream_chunks, chunks)
  end

  defp normalize_stream_outcome(outcome), do: outcome

  defp stream_mock_chunks(chunks, acc, chunk_fun) do
    Enum.reduce_while(chunks, {{:mock, :done}, acc}, fn chunk, {_result, acc} ->
      case chunk_fun.(chunk, acc) do
        {:cont, acc} -> {:cont, {{:mock, :done}, acc}}
        {:halt, acc} -> {:halt, {{:halted, :cancelled}, acc}}
      end
    end)
  end

  defp stream_each_outcome(acc, result, started, called_provider, mock) do
    provider =
      case result do
        {:ok, {:provider_metadata, metadata}} ->
          nil
          |> provider_outcome("completed", started, nil, true, false)
          |> Map.put(:provider_metadata, metadata)

        {:ok, _} ->
          provider_outcome(nil, "completed", started, nil, called_provider, mock)

        {:mock, _} ->
          provider_outcome(nil, "completed", started, nil, false, true)

        {:halted, _} ->
          provider_outcome(nil, "cancelled", started, nil, called_provider, mock)

        {:error, reason} ->
          provider_outcome(nil, "provider_error", started, reason, called_provider, mock)

        _ ->
          provider_outcome(nil, "provider_error", started, inspect(result), called_provider, mock)
      end

    {provider, acc}
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: if(String.trim(value) != "", do: String.trim(value))

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp integer_value(_), do: nil

  defp positive_integer(value, default) do
    case integer_value(value) do
      value when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end

  defp non_negative_integer(value, default) do
    case integer_value(value) do
      value when is_integer(value) and value >= 0 -> value
      _ -> default
    end
  end
end
