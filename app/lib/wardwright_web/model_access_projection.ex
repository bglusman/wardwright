defmodule WardwrightWeb.ModelAccessProjection do
  @moduledoc """
  Builds user- and agent-facing model access metadata from the active policy config.

  This module is a boundary projection: it turns the current map-shaped config into
  JSON-ready maps for the workbench and protected admin API while avoiding exposure
  of credential values.
  """

  def build(config_or_configs, provider_statuses, origin \\ "http://127.0.0.1:8787")

  def build(configs, provider_statuses, origin) when is_list(configs) do
    origin = normalize_origin(origin)
    configs = Enum.sort_by(configs, &Map.get(&1, "model_id", ""))

    %{
      "provider_models" =>
        configs
        |> Enum.flat_map(&provider_model_access_records(&1, provider_statuses))
        |> Enum.uniq_by(&{&1["target_model_id"], &1["provider_id"], &1["raw_model_id"]}),
      "service" => %{
        "admin_command" => "wardwright admin",
        "base_url" => origin,
        "chat_completions_url" => "#{origin}/v1/chat/completions",
        "mcp_url" => "#{origin}/mcp",
        "models_url" => "#{origin}/v1/models",
        "openai_base_url" => "#{origin}/v1",
        "tools_command" => "wardwright tools",
        "wardwright_models_url" => "#{origin}/v1/wardwright/models"
      },
      "wardwright_models" => Enum.map(configs, &wardwright_model_access_record(&1, origin))
    }
  end

  def build(config, provider_statuses, origin) when is_map(config) do
    build([config], provider_statuses, origin)
  end

  defp wardwright_model_access_record(config, origin) do
    model_id = Map.get(config, "model_id", Wardwright.model_id())

    %{
      "active_version" => Map.get(config, "version", Wardwright.model_version()),
      "agent_model_ids" => [model_id, "wardwright/#{model_id}"],
      "chat_completions_url" => "#{origin}/v1/chat/completions",
      "id" => model_id,
      "openai_base_url" => "#{origin}/v1",
      "provider_target_models" => config |> Wardwright.provider_targets() |> Enum.map(& &1["model"]),
      "route_root" => Map.get(config, "route_root", "dispatcher.prompt_length"),
      "route_type" => root_route_type(config),
      "server_tool_targets" => server_tool_target_records(config),
      "server_tools" => server_tool_records(config),
      "target_models" => config |> Map.get("targets", []) |> Enum.map(& &1["model"]),
      "tool_advertisement" => tool_advertisement_record(config),
      "tool_mediation" => tool_mediation_record(config),
      "vcr" => Map.get(config, "vcr", %{"mode" => "metadata_only"})
    }
  end

  def server_tool_records(config) when is_map(config) do
    config
    |> Map.get("server_tools", [])
    |> List.wrap()
    |> Enum.map(&server_tool_record/1)
    |> Enum.reject(&is_nil/1)
  end

  def server_tool_records(_config), do: []

  def server_tool_target_records(config) when is_map(config) do
    config
    |> Wardwright.provider_targets()
    |> Enum.map(fn target ->
      kind = provider_kind(target)

      %{
        "kind" => kind,
        "model" => Map.get(target, "model", ""),
        "server_tools_supported" => kind == "openai-compatible",
        "support" => if(kind == "openai-compatible", do: "tool-capable", else: "no-tool-injection")
      }
    end)
  end

  def server_tool_target_records(_config), do: []

  def tool_mediation_record(config) when is_map(config) do
    mediation = Map.get(config, "tool_mediation", %{})
    rules = mediation |> Map.get("rules", []) |> then(fn rules -> if is_list(rules), do: rules, else: [] end)

    %{
      "mode" => Map.get(mediation, "mode", "patch"),
      "rule_count" => length(rules)
    }
  end

  def tool_mediation_record(_config), do: %{"mode" => "patch", "rule_count" => 0}

  def tool_advertisement_record(config) when is_map(config) do
    tools = server_tool_records(config)
    targets = server_tool_target_records(config)
    enabled_tools = Enum.count(tools, &(&1["enabled"] != false))
    target_count = length(targets)
    tool_capable_targets = Enum.count(targets, &(&1["server_tools_supported"] == true))

    guaranteed =
      if target_count > 0 and tool_capable_targets == target_count do
        enabled_tools
      else
        0
      end

    conditional =
      if tool_capable_targets > 0 and tool_capable_targets < target_count do
        enabled_tools
      else
        0
      end

    %{
      "conditional_server_tools" => conditional,
      "guaranteed_server_tools" => guaranteed,
      "mode" => "intersection"
    }
  end

  def tool_advertisement_record(_config) do
    %{"conditional_server_tools" => 0, "guaranteed_server_tools" => 0, "mode" => "intersection"}
  end

  defp server_tool_record(%{} = tool) do
    name = tool |> Map.get("name", "") |> to_string() |> String.trim()
    engine = tool |> Map.get("engine", "builtin") |> to_string() |> String.trim()

    if name != "" do
      %{
        "enabled" => Map.get(tool, "enabled", true) == true,
        "engine" => if(engine == "", do: "builtin", else: engine),
        "input_keys" => input_keys(tool),
        "limits" => public_limits(Map.get(tool, "limits", %{})),
        "name" => name,
        "parameter_keys" => parameter_keys(tool),
        "source" => server_tool_source(tool),
        "visibility_level" => "local_verified"
      }
    end
  end

  defp server_tool_record(_tool), do: nil

  defp server_tool_source(%{"engine" => "builtin"}), do: "builtin"
  defp server_tool_source(%{"source" => source}) when is_binary(source) and source != "", do: "dune_source"

  defp server_tool_source(%{"snippet_id" => snippet_id}) when is_binary(snippet_id) and snippet_id != "",
    do: "dune_snippet"

  defp server_tool_source(%{"path" => path}) when is_binary(path) and path != "", do: "beam_path"
  defp server_tool_source(%{"module" => module}) when is_binary(module) and module != "", do: "beam_module"
  defp server_tool_source(%{"engine" => engine}) when is_binary(engine) and engine != "", do: engine
  defp server_tool_source(_tool), do: "builtin"

  defp public_limits(limits) when is_map(limits) do
    limits
    |> Map.take(["timeout_ms", "max_reductions", "max_heap_size"])
    |> Enum.filter(fn {_key, value} -> is_integer(value) and value > 0 end)
    |> Map.new()
  end

  defp public_limits(_limits), do: %{}

  defp parameter_keys(tool) do
    tool
    |> get_in(["parameters", "properties"])
    |> case do
      properties when is_map(properties) -> properties |> Map.keys() |> Enum.sort()
      _properties -> []
    end
  end

  defp input_keys(%{"input" => input}) when is_map(input), do: input |> Map.keys() |> Enum.sort()
  defp input_keys(_tool), do: []

  defp provider_model_access_records(config, provider_statuses) do
    provider_runtime =
      Map.new(provider_statuses, fn status ->
        {{status["provider_id"], status["model"]}, status}
      end)

    config
    |> Wardwright.provider_targets()
    |> Enum.map(fn target ->
      provider = target["model"] |> String.split("/", parts: 2) |> List.first()
      {kind, base_url} = provider_kind_and_base_url(provider, target)
      runtime = Map.get(provider_runtime, {provider, target["model"]}, %{})

      %{
        "attempt_count" => Map.get(runtime, "attempt_count", 0),
        "base_url" => base_url,
        "configured" => Map.get(runtime, "configured", true),
        "context_window" => target["context_window"],
        "credential_source" => credential_source(target),
        "health" => Map.get(runtime, "health", "unknown"),
        "kind" => kind,
        "last_latency_ms" => Map.get(runtime, "last_latency_ms"),
        "last_status" => Map.get(runtime, "last_status"),
        "provider_id" => provider,
        "raw_model_id" => provider_model(target),
        "target_model_id" => target["model"]
      }
    end)
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

  defp provider_model(target) do
    target["model"]
    |> String.split("/", parts: 2)
    |> case do
      [_provider, model] -> model
      [model] -> model
    end
  end

  defp root_route_type(config) do
    root = Map.get(config, "route_root", "dispatcher.prompt_length")

    cond do
      Enum.any?(Map.get(config, "alloys", []), &(&1["id"] == root)) -> "alloy"
      Enum.any?(Map.get(config, "cascades", []), &(&1["id"] == root)) -> "cascade"
      true -> "dispatcher"
    end
  end

  defp normalize_origin(origin) when is_binary(origin) do
    origin = String.trim(origin)

    cond do
      origin == "" -> "http://127.0.0.1:8787"
      String.ends_with?(origin, "/") -> String.trim_trailing(origin, "/")
      true -> origin
    end
  end

  defp normalize_origin(_), do: "http://127.0.0.1:8787"
end
