defmodule Wardwright.PathsTest do
  use ExUnit.Case, async: false

  setup do
    old_config_home = System.get_env("XDG_CONFIG_HOME")
    old_data_home = System.get_env("XDG_DATA_HOME")

    on_exit(fn ->
      restore_env("XDG_CONFIG_HOME", old_config_home)
      restore_env("XDG_DATA_HOME", old_data_home)
    end)

    :ok
  end

  test "uses XDG config and data roots when present" do
    System.put_env("XDG_CONFIG_HOME", "/tmp/wardwright-config")
    System.put_env("XDG_DATA_HOME", "/tmp/wardwright-data")

    assert Wardwright.Paths.config_path("authoring_agent.env") ==
             "/tmp/wardwright-config/wardwright/authoring_agent.env"

    assert Wardwright.Paths.config_path("recipes/policies") ==
             "/tmp/wardwright-config/wardwright/recipes/policies"

    assert Wardwright.Paths.data_path("wardwright.sqlite3") ==
             "/tmp/wardwright-data/wardwright/wardwright.sqlite3"
  end

  test "normalizes XDG roots before appending Wardwright path" do
    System.put_env("XDG_CONFIG_HOME", "~/.config")
    System.put_env("XDG_DATA_HOME", "relative-data-home")

    assert Wardwright.Paths.config_path("authoring_agent.env") ==
             Path.join([System.user_home!(), ".config", "wardwright", "authoring_agent.env"])

    assert Wardwright.Paths.data_path("wardwright.sqlite3") ==
             Path.join([File.cwd!(), "relative-data-home", "wardwright", "wardwright.sqlite3"])
  end

  test "defaults to standard user config and data locations" do
    System.delete_env("XDG_CONFIG_HOME")
    System.delete_env("XDG_DATA_HOME")

    assert Wardwright.Paths.config_path("authoring_agent.env") ==
             Path.join([System.user_home!(), ".config", "wardwright", "authoring_agent.env"])

    assert Wardwright.Paths.data_path("wardwright.sqlite3") ==
             Path.join([System.user_home!(), ".local", "share", "wardwright", "wardwright.sqlite3"])
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
