defmodule Wardwright.AgentAdapters.OpenCodeRuntime do
  @moduledoc false

  @config_path ".opencode/wardwright-runtime.json"

  @key_agent_runtime "agentRuntime"
  @key_id "id"
  @key_runtime "runtime"
  @key_runtime_source "runtime_source"
  @key_source "source"

  def resolve(workspace_root) do
    path = Path.join(workspace_root, @config_path)

    with true <- File.regular?(path),
         {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body),
         {:ok, runtime, source} <- parse_payload(payload) do
      {:ok, %{path: @config_path, runtime: runtime, source: source}}
    else
      _ -> :unknown
    end
  end

  defp parse_payload(payload) when is_map(payload) do
    agent_runtime = Map.get(payload, @key_agent_runtime, %{})
    raw_runtime = Map.get(payload, @key_runtime) || map_value(agent_runtime, @key_id)
    source = Map.get(payload, @key_runtime_source) || map_value(agent_runtime, @key_source)

    case normalize_runtime(raw_runtime) do
      {:ok, runtime, inferred_source} -> {:ok, runtime, source || inferred_source}
      {:unsupported, runtime} -> {:ok, runtime, source || @config_path}
      :unknown -> :error
    end
  end

  defp parse_payload(_payload), do: :error

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil

  defp normalize_runtime(runtime) when is_binary(runtime) do
    case String.downcase(runtime) do
      "pi" -> {:ok, "pi", @config_path}
      "pi-opencode-bridge" -> {:ok, "pi", "pi-opencode-bridge"}
      "omp" -> {:ok, "omp", @config_path}
      "omp-opencode-bridge" -> {:ok, "omp", "omp-opencode-bridge"}
      "opencode-native" -> {:ok, "opencode-native", @config_path}
      "native" -> {:ok, "opencode-native", @config_path}
      "codex" -> {:ok, "codex", @config_path}
      "openai-codex" -> {:ok, "codex", @config_path}
      unsupported -> {:unsupported, unsupported}
    end
  end

  defp normalize_runtime(_runtime), do: :unknown
end
