defmodule Wardwright.Paths do
  @moduledoc false

  def config_dir do
    xdg_dir("XDG_CONFIG_HOME", Path.join(System.user_home!(), ".config"))
  end

  def data_dir do
    xdg_dir("XDG_DATA_HOME", Path.join(Path.join(System.user_home!(), ".local"), "share"))
  end

  def config_path(name) when is_binary(name) do
    Path.join(config_dir(), name)
  end

  def data_path(name) when is_binary(name) do
    Path.join(data_dir(), name)
  end

  defp xdg_dir(env_key, fallback_root) do
    case System.get_env(env_key) do
      nil -> Path.join(fallback_root, "wardwright")
      "" -> Path.join(fallback_root, "wardwright")
      root -> Path.join(Path.expand(root), "wardwright")
    end
  end
end
