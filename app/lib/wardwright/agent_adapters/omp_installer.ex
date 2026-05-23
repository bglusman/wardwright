defmodule Wardwright.AgentAdapters.OmpInstaller do
  @moduledoc false

  alias Wardwright.AgentAdapters.OmpPack

  def status(workspace_root) when is_binary(workspace_root) do
    files =
      OmpPack.expected_files()
      |> Enum.map(&file_status(workspace_root, &1))

    %{
      files: files,
      installed_files_present: Enum.any?(files, & &1.present?),
      installed_manifest_matches: Enum.all?(files, & &1.matches?)
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
      |> Enum.map(&file_status(workspace_root, &1))

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

  defp file_status(workspace_root, file) do
    absolute_path = Path.join(workspace_root, file.path)

    case File.read(absolute_path) do
      {:ok, content} ->
        %{
          absolute_path: absolute_path,
          matches?: content == file.content,
          path: file.path,
          present?: true
        }

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
end
