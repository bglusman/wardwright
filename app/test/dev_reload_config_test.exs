defmodule Wardwright.DevReloadConfigTest do
  use ExUnit.Case, async: true

  @app_dir Path.expand("..", __DIR__)

  test "dev reloader avoids browser refreshes for stale Gleam builds by default" do
    config = Config.Reader.read!(Path.join(@app_dir, "config/dev.exs"), env: :dev)
    endpoint_config = config[:wardwright][WardwrightWeb.Endpoint]

    assert endpoint_config[:code_reloader]
    assert endpoint_config[:reloadable_compilers] == [:elixir, :app]
    refute :gleam in endpoint_config[:reloadable_compilers]
    refute :erlang in endpoint_config[:reloadable_compilers]
    refute :gleam_deps in endpoint_config[:reloadable_compilers]

    patterns = get_in(endpoint_config, [:live_reload, :patterns])
    refute Enum.any?(patterns, &Regex.match?(&1, "src/wardwright/some_app_module.gleam"))
  end

  test "dev reloader can opt into synchronous Gleam compilation when needed" do
    previous = System.get_env("WARDWRIGHT_GLEAM_CODE_RELOADER")

    try do
      System.put_env("WARDWRIGHT_GLEAM_CODE_RELOADER", "true")
      config = Config.Reader.read!(Path.join(@app_dir, "config/dev.exs"), env: :dev)
      endpoint_config = config[:wardwright][WardwrightWeb.Endpoint]

      assert endpoint_config[:reloadable_compilers] == [:elixir, :app, :gleam, :erlang]

      patterns = get_in(endpoint_config, [:live_reload, :patterns])
      assert Enum.any?(patterns, &Regex.match?(&1, "src/wardwright/some_app_module.gleam"))
    after
      if previous do
        System.put_env("WARDWRIGHT_GLEAM_CODE_RELOADER", previous)
      else
        System.delete_env("WARDWRIGHT_GLEAM_CODE_RELOADER")
      end
    end
  end

  test "Phoenix code reloader listens for compiler diagnostics" do
    assert Phoenix.CodeReloader in Mix.Project.config()[:listeners]
  end
end
