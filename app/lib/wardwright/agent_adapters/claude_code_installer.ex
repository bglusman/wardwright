defmodule Wardwright.AgentAdapters.ClaudeCodeInstaller do
  @moduledoc false

  alias Wardwright.AgentAdapters.ClaudeCodePack
  alias Wardwright.AgentAdapters.MetadataInstaller

  def status(workspace_root, opts \\ []) when is_binary(workspace_root) do
    MetadataInstaller.status(workspace_root, ClaudeCodePack, opts)
  end

  def install(workspace_root, opts \\ []) when is_binary(workspace_root) do
    MetadataInstaller.install(workspace_root, ClaudeCodePack, opts)
  end

  def uninstall(workspace_root) when is_binary(workspace_root) do
    MetadataInstaller.uninstall(workspace_root, ClaudeCodePack)
  end

  def pair(workspace_root, identity) when is_binary(workspace_root) and is_map(identity) do
    MetadataInstaller.pair(workspace_root, ClaudeCodePack, identity)
  end
end
