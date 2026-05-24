defmodule Wardwright.AgentAdapters.OpenClawRuntime do
  @moduledoc false

  @config_path ".openclaw/wardwright-runtime.json"

  @key_agent_runtime "agentRuntime"
  @key_backend "backend"
  @key_cli_backend "cliBackend"
  @key_id "id"
  @key_fallback "fallback"
  @key_runtime "runtime"
  @key_runtime_source "runtime_source"
  @key_resolved "resolved"
  @key_resolved_runtime "resolved_runtime"
  @key_selected "selected"
  @key_source "source"

  def resolve(workspace_root) do
    path = Path.join(workspace_root, @config_path)

    with true <- File.regular?(path),
         {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body),
         {:ok, runtime, source} <- parse_payload(payload) do
      {:ok,
       %{
         path: @config_path,
         runtime: runtime,
         source: source,
         surface_probe_passed: false
       }}
    else
      _ -> :unknown
    end
  end

  defp parse_payload(payload) when is_map(payload) do
    agent_runtime = Map.get(payload, @key_agent_runtime, %{})
    cli_backend = Map.get(payload, @key_cli_backend, %{})
    backend = Map.get(payload, @key_backend, %{})

    raw_runtime =
      Map.get(payload, @key_runtime) ||
        map_value(agent_runtime, @key_id) ||
        map_value(cli_backend, @key_id) ||
        map_value(backend, @key_id)

    source =
      Map.get(payload, @key_runtime_source) ||
        map_value(agent_runtime, @key_source) ||
        map_value(cli_backend, @key_source) ||
        map_value(backend, @key_source)

    case normalize_runtime(raw_runtime, agent_runtime) do
      {:ok, runtime, inferred_source} -> {:ok, runtime, source || inferred_source}
      {:unsupported, runtime} -> {:ok, runtime, source || @config_path}
      :unknown -> :error
    end
  end

  defp parse_payload(_payload), do: :error

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil

  defp normalize_auto_runtime(agent_runtime) when is_map(agent_runtime) do
    resolved =
      Map.get(agent_runtime, @key_resolved) ||
        Map.get(agent_runtime, @key_resolved_runtime) ||
        Map.get(agent_runtime, @key_selected) ||
        Map.get(agent_runtime, @key_fallback)

    case normalize_runtime(resolved, %{}) do
      {:ok, "pi", _source} -> {:ok, "pi", "agentRuntime.auto -> pi"}
      {:ok, runtime, source} -> {:ok, runtime, source}
      {:unsupported, runtime} -> {:unsupported, runtime}
      :unknown -> {:unsupported, "auto"}
    end
  end

  defp normalize_auto_runtime(_agent_runtime), do: {:unsupported, "auto"}

  defp normalize_runtime(runtime, agent_runtime) when is_binary(runtime) do
    case String.downcase(runtime) do
      "auto" -> normalize_auto_runtime(agent_runtime)
      "pi" -> {:ok, "pi", @config_path}
      "openclaw-pi" -> {:ok, "pi", "openclaw-pi"}
      "codex" -> {:ok, "codex", @config_path}
      "openai-codex" -> {:ok, "codex", @config_path}
      "claude-cli" -> {:ok, "claude-cli", @config_path}
      "claude" -> {:ok, "claude-cli", @config_path}
      unsupported -> {:unsupported, unsupported}
    end
  end

  defp normalize_runtime(_runtime, _agent_runtime), do: :unknown
end
