defmodule Wardwright.AgentAdapters.OmpInstaller do
  @moduledoc false

  alias Wardwright.AgentAdapters.Identity
  alias Wardwright.AgentAdapters.OmpPack

  @key_adapter_id "adapter_id"
  @key_adapter_version "adapter_version"
  @key_gateway_identity "gateway_identity"
  @key_gateway_url "gateway_url"
  @key_paired "paired"
  @key_runtime "runtime"
  @key_runtime_probe "runtime_probe"
  @key_schema "schema"
  @key_status "status"
  @key_target "target"
  @runtime "omp"
  @runtime_probe_name "omp_ttsr_runtime_equivalence"
  @runtime_probe_schema "wardwright.omp_runtime_probe.v0"
  @schema "wardwright.adapter_config.v0"
  @status_passed "passed"

  def status(workspace_root, opts \\ []) when is_binary(workspace_root) do
    files =
      OmpPack.expected_files()
      |> Enum.map(&file_status(workspace_root, &1, opts))

    config = adapter_config(workspace_root)

    %{
      files: files,
      identity_verified: Enum.any?(files, &Map.get(&1, :identity_verified?, false)),
      installed_files_present: Enum.any?(files, & &1.present?),
      installed_manifest_matches: Enum.all?(files, & &1.matches?),
      runtime_probe_passed: runtime_probe_passed?(config)
    }
  end

  def install(workspace_root, opts \\ []) when is_binary(workspace_root) do
    repair? = Keyword.get(opts, :repair?, false)
    inspection = status(workspace_root)

    if inspection.installed_files_present and not inspection.installed_manifest_matches and not repair? do
      {:error, :repair_required, inspection}
    else
      written =
        OmpPack.expected_files()
        |> Enum.map(&write_file!(workspace_root, &1))

      {:ok, %{repaired?: inspection.installed_files_present and repair?, written: written}}
    end
  end

  def uninstall(workspace_root) when is_binary(workspace_root) do
    statuses =
      OmpPack.expected_files()
      |> Enum.map(&file_status(workspace_root, &1, []))

    removed =
      statuses
      |> Enum.filter(& &1.matches?)
      |> Enum.map(&remove_file!/1)

    skipped =
      statuses
      |> Enum.filter(fn status -> status.present? and not status.matches? end)
      |> Enum.map(& &1.path)

    prune_empty_adapter_dirs(workspace_root)

    {:ok, %{removed: removed, skipped: skipped}}
  end

  def pair(workspace_root, identity) when is_binary(workspace_root) and is_map(identity) do
    inspection = status(workspace_root)

    cond do
      not inspection.installed_files_present ->
        {:error, :not_installed, inspection}

      not inspection.installed_manifest_matches ->
        {:error, :repair_required, inspection}

      true ->
        path = Path.join(workspace_root, OmpPack.config_path())
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, OmpPack.adapter_config_content(identity))
        {:ok, %{path: OmpPack.config_path()}}
    end
  end

  def probe(workspace_root, opts \\ []) when is_binary(workspace_root) do
    inspection = status(workspace_root, opts)

    cond do
      not inspection.installed_files_present ->
        {:error, :not_installed, inspection}

      not inspection.installed_manifest_matches ->
        {:error, :repair_required, inspection}

      true ->
        with {:ok, config} <- adapter_config(workspace_root),
             :ok <- require_paired_identity(config),
             {:ok, output} <- run_runtime_probe(workspace_root, opts),
             {:ok, evidence} <- record_runtime_probe(workspace_root, config, output, opts) do
          {:ok, %{config_path: OmpPack.config_path(), evidence: evidence}}
        end
    end
  end

  defp run_runtime_probe(workspace_root, opts) do
    request = %{
      config_path: Path.join(workspace_root, OmpPack.config_path()),
      node_bin: Keyword.get(opts, :node_bin, "node"),
      omp_bin: Keyword.get(opts, :omp_bin, "omp"),
      rule_path: Path.join(workspace_root, ".omp/rules/wardwright-read-before-edit.md"),
      script_path: Keyword.get(opts, :probe_script_path, default_probe_script_path()),
      workspace_root: workspace_root
    }

    probe_runner = Keyword.get(opts, :probe_runner, &run_probe_command/1)
    probe_runner.(request)
  end

  defp run_probe_command(request) do
    env = [
      {"OMP_BIN", request.omp_bin},
      {"WARDWRIGHT_OMP_CONFIG_PATH", request.config_path},
      {"WARDWRIGHT_OMP_RULE_PATH", request.rule_path}
    ]

    case System.cmd(request.node_bin, [request.script_path],
           cd: request.workspace_root,
           env: env,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, :probe_failed, %{output: output, status: status}}
    end
  rescue
    error in ErlangError -> {:error, :probe_failed, %{output: Exception.message(error), status: nil}}
  end

  defp record_runtime_probe(workspace_root, config, output, opts) do
    evidence = %{
      adapter_id: OmpPack.adapter_id(),
      adapter_version: OmpPack.adapter_version(),
      output_sha256: sha256(output),
      probe: @runtime_probe_name,
      probed_at: DateTime.to_iso8601(Keyword.get(opts, :now, DateTime.utc_now())),
      runtime: @runtime,
      schema: @runtime_probe_schema,
      status: @status_passed,
      target: @runtime
    }

    path = Path.join(workspace_root, OmpPack.config_path())

    config
    |> Map.put(@key_runtime_probe, evidence)
    |> JSON.encode!()
    |> Kernel.<>("\n")
    |> then(&File.write!(path, &1))

    {:ok, evidence}
  end

  defp file_status(workspace_root, file, opts) do
    absolute_path = Path.join(workspace_root, file.path)

    case File.read(absolute_path) do
      {:ok, content} ->
        file_status_for_content(workspace_root, file, absolute_path, content, opts)

      {:error, :enoent} ->
        %{
          absolute_path: absolute_path,
          matches?: false,
          path: file.path,
          present?: false
        }

      {:error, _reason} ->
        %{
          absolute_path: absolute_path,
          matches?: false,
          path: file.path,
          present?: true
        }
    end
  end

  defp file_status_for_content(workspace_root, %{dynamic?: true} = file, absolute_path, content, opts) do
    {matches?, identity_verified?} = adapter_config_status(workspace_root, content, opts)

    %{
      absolute_path: absolute_path,
      identity_verified?: identity_verified?,
      matches?: matches?,
      path: file.path,
      present?: true
    }
  end

  defp file_status_for_content(_workspace_root, file, absolute_path, content, _opts) do
    %{
      absolute_path: absolute_path,
      matches?: content == file.content,
      path: file.path,
      present?: true
    }
  end

  defp adapter_config_status(workspace_root, content, opts) do
    case JSON.decode(content) do
      {:ok, config} when is_map(config) ->
        config_valid? = adapter_config_valid?(config)
        identity_verified? = adapter_identity_verified?(workspace_root, config, opts)
        {config_valid?, identity_verified?}

      _result ->
        {false, false}
    end
  end

  defp adapter_config_valid?(config) do
    Map.get(config, @key_schema) == @schema and
      Map.get(config, @key_adapter_id) == OmpPack.adapter_id() and
      Map.get(config, @key_adapter_version) == OmpPack.adapter_version() and
      Map.get(config, @key_target) == @runtime and
      Map.get(config, @key_runtime) == @runtime and
      is_boolean(Map.get(config, @key_paired)) and
      (Map.get(config, @key_gateway_identity) == nil or is_map(Map.get(config, @key_gateway_identity))) and
      (Map.get(config, @key_runtime_probe) == nil or is_map(Map.get(config, @key_runtime_probe))) and
      is_binary(Map.get(config, @key_gateway_url))
  end

  defp adapter_config(workspace_root) do
    workspace_root
    |> Path.join(OmpPack.config_path())
    |> File.read()
    |> case do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, config} when is_map(config) -> {:ok, config}
          _result -> {:error, :invalid_config}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_paired_identity(config) do
    if Map.get(config, @key_paired) == true and is_map(Map.get(config, @key_gateway_identity)) do
      :ok
    else
      {:error, :not_paired, config}
    end
  end

  defp runtime_probe_passed?({:ok, config}) do
    case Map.get(config, @key_runtime_probe) do
      probe when is_map(probe) ->
        Map.get(probe, @key_schema) == @runtime_probe_schema and
          Map.get(probe, @key_status) == @status_passed and
          Map.get(probe, @key_adapter_id) == OmpPack.adapter_id() and
          Map.get(probe, @key_adapter_version) == OmpPack.adapter_version() and
          Map.get(probe, @key_runtime) == @runtime and
          Map.get(probe, @key_target) == @runtime

      _probe ->
        false
    end
  end

  defp runtime_probe_passed?(_config), do: false

  defp adapter_identity_verified?(workspace_root, config, opts) do
    case Map.get(config, @key_gateway_identity) do
      identity when is_map(identity) ->
        case Identity.validate(identity,
               adapter_id: OmpPack.adapter_id(),
               runtime: @runtime,
               target: @runtime,
               workspace_root: workspace_root,
               secret: Keyword.get(opts, :identity_secret),
               now: Keyword.get(opts, :now, DateTime.utc_now())
             ) do
          {:ok, _claims} -> true
          {:error, _reason} -> false
        end

      _identity ->
        false
    end
  end

  defp write_file!(workspace_root, file) do
    path = Path.join(workspace_root, file.path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, file.content)
    file.path
  end

  defp remove_file!(status) do
    File.rm!(status.absolute_path)
    status.path
  end

  defp prune_empty_adapter_dirs(workspace_root) do
    [
      ".omp/rules",
      ".omp/extensions",
      ".omp"
    ]
    |> Enum.each(fn relative_path ->
      path = Path.join(workspace_root, relative_path)

      case File.rmdir(path) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end

  defp default_probe_script_path do
    case :code.priv_dir(:wardwright) do
      priv_dir when is_list(priv_dir) ->
        priv_path = Path.join([to_string(priv_dir), "agent_adapters", "omp-ttsr-runtime-equivalence.mjs"])

        if File.regular?(priv_path) do
          priv_path
        else
          source_probe_script_path()
        end

      _error ->
        source_probe_script_path()
    end
  end

  defp source_probe_script_path do
    Path.expand("../../../../scripts/omp-ttsr-runtime-equivalence.mjs", __DIR__)
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
