defmodule Wardwright.MixProject do
  use Mix.Project

  def project do
    [
      app: :wardwright,
      version: "0.0.8",
      elixir: "~> 1.17",
      compilers: Mix.compilers(),
      aliases: [
        "deps.get": ["deps.get", "gleam.deps.get", &compile_gleam_runtime/1],
        "compile.all": [&compile_gleam_runtime/1, "compile.all"]
      ],
      erlc_paths: gleam_erlc_paths(Mix.env()),
      erlc_include_path: "_build/#{Mix.env()}/lib/wardwright/include",
      prune_code_paths: false,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      tinfoil: [
        targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64],
        github: [
          repo: "bglusman/wardwright"
        ],
        homebrew: [
          enabled: true,
          tap: "bglusman/homebrew-tap",
          formula_name: "wardwright"
        ],
        installer: [
          enabled: true
        ],
        ci: [
          elixir_version: "1.19",
          otp_version: "28"
        ],
        prerelease_pattern: ~r/-(rc|beta|alpha|dev)(\.|$)/
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl],
      mod: {Wardwright.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:dune, "~> 0.3.15"},
      {:gleam_stdlib, "~> 1.0", compile: false, app: false},
      {:gleam_erlang, "~> 1.3", compile: false, app: false},
      {:gleam_json, "~> 3.1", compile: false, app: false},
      {:gleam_otp, "~> 1.2", compile: false, app: false},
      {:gleam_community_colour, "~> 2.0", compile: false, app: false},
      {:gleam_time, "~> 1.8", compile: false, app: false},
      {:houdini, "~> 1.2", compile: false, app: false},
      {:lustre, "~> 5.7", compile: false, app: false},
      {:glizzy, "~> 0.1.0", compile: false, app: false},
      {:mix_gleam, "~> 0.6", runtime: false},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:telemetry_metrics, "~> 1.0"},
      {:live_dashboard_history, "~> 0.1.5"},
      {:plug_cowboy, "~> 2.7"},
      {:exqlite, "~> 0.36"},
      {:hermes_mcp, "~> 0.14.1"},
      {:jido_ai, "~> 2.1"},
      {:burrito, "~> 1.5", runtime: false},
      {:tinfoil, "~> 0.2", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.5", only: :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:muex, "~> 0.6.1", only: :test},
      {:stream_data, "~> 1.3", only: :test}
    ]
  end

  defp compile_gleam_runtime(_args) do
    gleam_dependency_names()
    |> Enum.each(fn dependency ->
      Mix.Task.rerun("compile.gleam", [dependency, "--force"])
    end)

    Mix.Task.rerun("compile.gleam")
  end

  defp gleam_erlc_paths(env) do
    dependency_paths =
      gleam_dependency_names()
      |> Enum.map(&"_build/#{env}/lib/#{&1}/_gleam_artefacts")

    ["_build/#{env}/lib/wardwright/_gleam_artefacts" | dependency_paths]
  end

  defp gleam_dependency_names do
    ~w(
      gleam_stdlib
      gleam_erlang
      gleam_json
      gleam_otp
      gleam_community_colour
      gleam_time
      houdini
      lustre
      glizzy
    )
  end

  defp releases do
    [
      wardwright: [
        include_executables_for: [],
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            darwin_arm64: [os: :darwin, cpu: :aarch64],
            darwin_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end
end
