defmodule Wardwright.AgentAdapters.OpenCodeRuntime do
  @moduledoc false

  @config_path ".opencode/wardwright-runtime.json"

  @key_agent_runtime "agentRuntime"
  @key_adapter_id "adapter_id"
  @key_adapter_version "adapter_version"
  @key_id "id"
  @key_output_sha256 "output_sha256"
  @key_probe "probe"
  @key_probed_at "probed_at"
  @key_runtime "runtime"
  @key_runtime_source "runtime_source"
  @key_schema "schema"
  @key_source "source"
  @key_status "status"
  @key_surface_probe "surface_probe"
  @key_target "target"
  @surface_probe_name "opencode_runtime_surface"
  @surface_probe_schema "wardwright.opencode_surface_probe.v0"
  @status_passed "passed"
  @target_opencode "opencode"

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
         surface_probe_passed: surface_probe_passed?(payload, runtime)
       }}
    else
      _ -> :unknown
    end
  end

  def record_surface_probe(workspace_root, runtime, adapter_id, output, opts \\ [])
      when is_binary(workspace_root) and is_binary(runtime) and is_binary(adapter_id) do
    path = Path.join(workspace_root, @config_path)

    with {:ok, body} <- File.read(path),
         {:ok, payload} when is_map(payload) <- JSON.decode(body) do
      evidence = %{
        @key_adapter_id => adapter_id,
        @key_adapter_version => Keyword.get(opts, :adapter_version, "unknown"),
        @key_output_sha256 => sha256(output),
        @key_probe => @surface_probe_name,
        @key_probed_at => DateTime.to_iso8601(Keyword.get(opts, :now, DateTime.utc_now())),
        @key_runtime => runtime,
        @key_schema => @surface_probe_schema,
        @key_status => @status_passed,
        @key_target => @target_opencode
      }

      payload
      |> Map.put(@key_surface_probe, evidence)
      |> JSON.encode!()
      |> Kernel.<>("\n")
      |> then(&File.write!(path, &1))

      {:ok, evidence}
    else
      _ -> {:error, :runtime_not_configured}
    end
  end

  def run_surface_probe(request) when is_map(request) do
    env = [
      {"WARDWRIGHT_OPENCODE_SURFACE_PROBE", "1"},
      {"WARDWRIGHT_OPENCODE_RUNTIME", request.runtime},
      {"WARDWRIGHT_OPENCODE_ADAPTER_ID", request.adapter_id}
    ]

    args = [
      "run",
      "--format",
      "json",
      "--dir",
      request.workspace_root,
      "--command",
      "wardwright.surface_probe",
      request.runtime
    ]

    case System.cmd(request.opencode_bin, args,
           cd: request.workspace_root,
           env: env,
           stderr_to_stdout: true
         ) do
      {output, 0} -> validate_surface_probe_output(output)
      {output, status} -> {:error, :probe_failed, %{output: output, status: status}}
    end
  rescue
    error in ErlangError -> {:error, :probe_failed, %{output: Exception.message(error), status: nil}}
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

  defp surface_probe_passed?(payload, runtime) do
    adapter_id = adapter_id_for_runtime(runtime)

    case Map.get(payload, @key_surface_probe) do
      probe when is_map(probe) ->
        Map.get(probe, @key_schema) == @surface_probe_schema and
          Map.get(probe, @key_status) == @status_passed and
          Map.get(probe, @key_probe) == @surface_probe_name and
          Map.get(probe, @key_runtime) == runtime and
          Map.get(probe, @key_target) == @target_opencode and
          Map.get(probe, @key_adapter_id) == adapter_id

      _probe ->
        false
    end
  end

  defp adapter_id_for_runtime("omp"), do: "wardwright-omp"
  defp adapter_id_for_runtime("pi"), do: "wardwright-pi"
  defp adapter_id_for_runtime(_runtime), do: ""

  defp validate_surface_probe_output(output) do
    if String.contains?(output, "wardwright_surface_probe=passed") do
      {:ok, output}
    else
      {:error, :probe_failed, %{output: output, status: :missing_surface_probe_marker}}
    end
  end

  defp sha256(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end
end
