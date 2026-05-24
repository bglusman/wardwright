defmodule Wardwright.AgentAdapters.ClaudeCodePack do
  @moduledoc false

  alias Wardwright.AgentAdapters.CanonicalJson

  @adapter_id "wardwright-claude-code"
  @adapter_version "0.1.0-rc.1"
  @config_path ".wardwright/adapters/claude-code-adapter.json"
  @default_gateway_url "http://127.0.0.1:8787"
  @fidelity "prompt_handoff"
  @key_fidelity "fidelity"
  @key_gateway_url "gateway_url"
  @key_native_state_fidelity "native_state_fidelity"
  @manifest_path ".wardwright/adapters/claude-code-adapter-manifest.json"
  @runtime "claude-cli"
  @target "claude-code"

  def adapter_id, do: @adapter_id
  def adapter_version, do: @adapter_version
  def config_path, do: @config_path
  def fidelity, do: @fidelity
  def manifest_path, do: @manifest_path
  def runtime, do: @runtime
  def target, do: @target

  def required_config_fields do
    %{
      @key_fidelity => @fidelity,
      @key_native_state_fidelity => false
    }
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
      fidelity: @fidelity,
      gateway_identity: identity,
      gateway_url: gateway_url(identity),
      native_state_fidelity: false,
      paired: is_map(identity),
      runtime: @runtime,
      schema: "wardwright.adapter_config.v0",
      target: @target
    }
    |> CanonicalJson.encode!()
    |> Kernel.<>("\n")
  end

  defp manifest_content(files) do
    %{
      adapter_id: @adapter_id,
      adapter_version: @adapter_version,
      fidelity: @fidelity,
      files: Enum.map(files, &manifest_entry/1),
      native_state_fidelity: false,
      runtime: @runtime,
      schema: "wardwright.adapter_manifest.v0",
      target: @target
    }
    |> CanonicalJson.encode!()
    |> Kernel.<>("\n")
  end

  defp manifest_entry(%{dynamic?: true} = file) do
    %{
      dynamic: true,
      path: file.path,
      validator: "adapter_config_schema"
    }
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
