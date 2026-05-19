defmodule Wardwright.DevReloadConfigTest do
  use ExUnit.Case, async: true

  @app_dir Path.expand("..", __DIR__)

  test "dev reloader watches app Gleam sources without recompiling dependencies per request" do
    config = Config.Reader.read!(Path.join(@app_dir, "config/dev.exs"), env: :dev)
    endpoint_config = config[:wardwright][WardwrightWeb.Endpoint]

    assert endpoint_config[:code_reloader]
    assert endpoint_config[:reloadable_compilers] == [:gleam, :erlang, :elixir, :app]
    refute :gleam_deps in endpoint_config[:reloadable_compilers]

    patterns = get_in(endpoint_config, [:live_reload, :patterns])
    assert Enum.any?(patterns, &Regex.match?(&1, "src/wardwright/some_app_module.gleam"))
  end

  test "Phoenix code reloader listens for compiler diagnostics" do
    assert Phoenix.CodeReloader in Mix.Project.config()[:listeners]
  end
end
