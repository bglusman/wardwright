defmodule Wardwright.AgentAdapters.MetadataInstaller do
  @moduledoc false

  alias Wardwright.AgentAdapters.Identity

  @key_adapter_id "adapter_id"
  @key_adapter_version "adapter_version"
  @key_gateway_identity "gateway_identity"
  @key_gateway_url "gateway_url"
  @key_paired "paired"
  @key_runtime "runtime"
  @key_schema "schema"
  @key_target "target"
  @schema "wardwright.adapter_config.v0"

  def status(workspace_root, pack, opts \\ []) when is_binary(workspace_root) do
    files =
      pack.expected_files()
      |> Enum.map(&file_status(workspace_root, pack, &1, opts))

    %{
      export_only: pack_export_only(pack),
      files: files,
      identity_verified: Enum.any?(files, &Map.get(&1, :identity_verified?, false)),
      installed_files_present: Enum.any?(files, & &1.present?),
      installed_manifest_matches: Enum.all?(files, & &1.matches?),
      runtime_probe_passed: false
    }
  end

  def install(workspace_root, pack, opts \\ []) when is_binary(workspace_root) do
    repair? = Keyword.get(opts, :repair?, false)
    inspection = status(workspace_root, pack)

    if inspection.installed_files_present and not inspection.installed_manifest_matches and not repair? do
      {:error, :repair_required, inspection}
    else
      written =
        pack.expected_files()
        |> Enum.map(&write_file!(workspace_root, &1))

      {:ok,
       %{
         export_only: pack_export_only(pack),
         repaired?: inspection.installed_files_present and repair?,
         written: written
       }}
    end
  end

  def uninstall(workspace_root, pack) when is_binary(workspace_root) do
    statuses =
      pack.expected_files()
      |> Enum.map(&file_status(workspace_root, pack, &1, []))

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

  def pair(workspace_root, pack, identity) when is_binary(workspace_root) and is_map(identity) do
    inspection = status(workspace_root, pack)

    cond do
      not inspection.installed_files_present ->
        {:error, :not_installed, inspection}

      not inspection.installed_manifest_matches ->
        {:error, :repair_required, inspection}

      true ->
        path = Path.join(workspace_root, pack.config_path())
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, pack.adapter_config_content(identity))
        {:ok, %{path: pack.config_path()}}
    end
  end

  defp file_status(workspace_root, pack, file, opts) do
    absolute_path = Path.join(workspace_root, file.path)

    case File.read(absolute_path) do
      {:ok, content} ->
        file_status_for_content(workspace_root, pack, file, absolute_path, content, opts)

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

  defp file_status_for_content(workspace_root, pack, %{dynamic?: true} = file, absolute_path, content, opts) do
    {matches?, identity_verified?} = adapter_config_status(workspace_root, pack, content, opts)

    %{
      absolute_path: absolute_path,
      identity_verified?: identity_verified?,
      matches?: matches?,
      path: file.path,
      present?: true
    }
  end

  defp file_status_for_content(_workspace_root, _pack, file, absolute_path, content, _opts) do
    %{
      absolute_path: absolute_path,
      matches?: content == file.content,
      path: file.path,
      present?: true
    }
  end

  defp adapter_config_status(workspace_root, pack, content, opts) do
    case JSON.decode(content) do
      {:ok, config} when is_map(config) ->
        config_valid? = adapter_config_valid?(pack, config)
        identity_verified? = adapter_identity_verified?(workspace_root, pack, config, opts)
        {config_valid?, identity_verified?}

      _result ->
        {false, false}
    end
  end

  defp adapter_config_valid?(pack, config) do
    Map.get(config, @key_schema) == @schema and
      Map.get(config, @key_adapter_id) == pack.adapter_id() and
      Map.get(config, @key_adapter_version) == pack.adapter_version() and
      Map.get(config, @key_target) == pack.target() and
      Map.get(config, @key_runtime) == pack.runtime() and
      is_boolean(Map.get(config, @key_paired)) and
      (Map.get(config, @key_gateway_identity) == nil or is_map(Map.get(config, @key_gateway_identity))) and
      is_binary(Map.get(config, @key_gateway_url)) and
      required_config_fields_match?(pack, config)
  end

  defp required_config_fields_match?(pack, config) do
    pack_required_config_fields(pack)
    |> Enum.all?(fn {key, expected} -> Map.get(config, key) == expected end)
  end

  defp adapter_identity_verified?(workspace_root, pack, config, opts) do
    case Map.get(config, @key_gateway_identity) do
      identity when is_map(identity) ->
        case Identity.validate(identity,
               adapter_id: pack.adapter_id(),
               runtime: pack.runtime(),
               target: pack.target(),
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

  defp pack_export_only(pack) do
    if function_exported?(pack, :export_only_items, 0), do: apply(pack, :export_only_items, []), else: []
  end

  defp pack_required_config_fields(pack) do
    if function_exported?(pack, :required_config_fields, 0), do: apply(pack, :required_config_fields, []), else: %{}
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
      ".wardwright/adapters",
      ".wardwright"
    ]
    |> Enum.each(fn relative_path ->
      path = Path.join(workspace_root, relative_path)

      case File.rmdir(path) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end
end
