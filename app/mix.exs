defmodule Wardwright.MixProject do
  use Mix.Project

  def project do
    [
      app: :wardwright,
      version: "0.0.8",
      elixir: "~> 1.17",
      compilers: [:gleam_deps, :gleam] ++ Mix.compilers(),
      aliases: ["deps.get": ["deps.get", "gleam.deps.get"]],
      erlc_paths: [
        "_build/#{Mix.env()}/lib/wardwright/_gleam_artefacts"
      ],
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
      {:gleam_stdlib, ">= 0.61.0 and < 1.0.0", compile: false, app: false},
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

defmodule Mix.Tasks.Compile.GleamDeps do
  @moduledoc false

  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    project_root = File.cwd!()
    app = Mix.Project.config() |> Keyword.fetch!(:app) |> Atom.to_string()

    with {:ok, _output} <- gleam_build(project_root),
         :ok <- link_gleam_packages(project_root, app) do
      {:ok, []}
    else
      {:error, output} ->
        Mix.shell().error(output)
        {:error, []}
    end
  end

  defp gleam_build(project_root) do
    case System.cmd("gleam", ["build"], cd: project_root, stderr_to_stdout: true) do
      {_output, 0} = result -> {:ok, result}
      {output, _status} -> {:error, output}
    end
  end

  defp link_gleam_packages(project_root, app) do
    source_root = gleam_build_root(project_root)
    target_root = Path.join([project_root, "_build", Atom.to_string(Mix.env()), "lib"])

    source_root
    |> File.ls!()
    |> Enum.reject(&(&1 == app))
    |> Enum.each(fn package ->
      source = Path.join(source_root, package)
      target = Path.join(target_root, package)

      File.rm_rf!(target)
      File.mkdir_p!(Path.dirname(target))

      case File.ln_s(source, target) do
        :ok -> :ok
        {:error, _reason} -> File.cp_r!(source, target)
      end

      target
      |> Path.join("ebin")
      |> Code.prepend_path()
    end)

    :ok
  end

  defp gleam_build_root(project_root) do
    env_root = Path.join([project_root, "build", Atom.to_string(Mix.env()), "erlang"])
    dev_root = Path.join([project_root, "build", "dev", "erlang"])

    if File.dir?(env_root), do: env_root, else: dev_root
  end
end
