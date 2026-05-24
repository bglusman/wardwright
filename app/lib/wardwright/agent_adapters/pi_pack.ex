defmodule Wardwright.AgentAdapters.PiPack do
  @moduledoc false

  @adapter_id "wardwright-pi"
  @adapter_version "0.1.0-rc.1"
  @config_path ".wardwright/adapters/pi-adapter.json"
  @default_gateway_url "http://127.0.0.1:8787"
  @key_gateway_url "gateway_url"
  @manifest_path ".wardwright/adapters/pi-adapter-manifest.json"

  def adapter_id, do: @adapter_id
  def adapter_version, do: @adapter_version
  def config_path, do: @config_path
  def manifest_path, do: @manifest_path

  def export_only_items do
    [
      "pi_session_jsonl",
      "state_fidelity_probe_json",
      "import_commands"
    ]
  end

  def expected_files do
    files = content_files()

    files ++
      [
        %{
          content: manifest_content(files),
          path: @manifest_path
        }
      ]
  end

  def content_files do
    [
      %{
        content: adapter_config_content(),
        dynamic?: true,
        path: @config_path
      }
    ]
  end

  def adapter_config_content(identity \\ nil) do
    %{
      adapter_id: @adapter_id,
      adapter_version: @adapter_version,
      export_only: export_only_items(),
      gateway_identity: identity,
      gateway_url: gateway_url(identity),
      paired: is_map(identity),
      runtime: "pi",
      schema: "wardwright.adapter_config.v0",
      target: "pi"
    }
    |> JSON.encode!()
    |> Kernel.<>("\n")
  end

  defp manifest_content(files) do
    %{
      adapter_id: @adapter_id,
      adapter_version: @adapter_version,
      export_only: export_only_items(),
      files: Enum.map(files, &manifest_entry/1),
      runtime: "pi",
      schema: "wardwright.adapter_manifest.v0",
      target: "pi"
    }
    |> JSON.encode!()
    |> Kernel.<>("\n")
  end

  defp manifest_entry(file) do
    %{
      path: file.path,
      sha256: sha256(file.content)
    }
  end

  defp gateway_url(identity) when is_map(identity), do: Map.get(identity, @key_gateway_url, @default_gateway_url)
  defp gateway_url(_identity), do: @default_gateway_url

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
