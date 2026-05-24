defmodule Wardwright.AgentAdapters.PiInstaller do
  @moduledoc false

  alias Wardwright.AgentAdapters.MetadataInstaller
  alias Wardwright.AgentAdapters.PiPack

  def status(workspace_root, opts \\ []) when is_binary(workspace_root) do
    MetadataInstaller.status(workspace_root, PiPack, opts)
  end

  def install(workspace_root, opts \\ []) when is_binary(workspace_root) do
    MetadataInstaller.install(workspace_root, PiPack, opts)
  end

  def uninstall(workspace_root) when is_binary(workspace_root) do
    MetadataInstaller.uninstall(workspace_root, PiPack)
  end

  def pair(workspace_root, identity) when is_binary(workspace_root) and is_map(identity) do
    MetadataInstaller.pair(workspace_root, PiPack, identity)
  end
end
