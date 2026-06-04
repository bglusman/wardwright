defmodule Mix.Tasks.Compile.GleamDeps do
  use Mix.Task.Compiler

  @recursive true

  @impl Mix.Task.Compiler
  def run(_args) do
    build_lib = Path.join(Mix.Project.build_path(), "lib")
    File.mkdir_p!(build_lib)

    case System.find_executable("gleam") do
      nil ->
        Mix.shell().error("Could not find the gleam executable")
        {:error, []}

      gleam ->
        compile_packages(gleam, build_lib)
    end
  end

  defp compile_packages(gleam, build_lib) do
    gleam_package_names()
    |> Enum.reduce_while(:ok, fn package, :ok ->
      case compile_package(gleam, build_lib, package) do
        :ok -> {:cont, :ok}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :ok -> {:ok, []}
      :error -> {:error, []}
    end
  end

  defp gleam_package_names do
    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Enum.map(&dependency_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&gleam_dependency?/1)
  end

  defp dependency_name({package, _requirement}) when is_atom(package), do: Atom.to_string(package)

  defp dependency_name({package, _requirement, _opts}) when is_atom(package), do: Atom.to_string(package)

  defp dependency_name(_dependency), do: nil

  defp gleam_dependency?(package) do
    File.regular?(Path.join(["deps", package, "gleam.toml"]))
  end

  defp compile_package(gleam, build_lib, package) do
    dep_path = Path.join("deps", package)
    output_path = Path.join(build_lib, package)

    if File.regular?(Path.join(dep_path, "gleam.toml")) do
      File.rm_rf!(output_path)
      Mix.shell().info("Compiling Gleam dependency #{package}")

      args = [
        "compile-package",
        "--target",
        "erlang",
        "--package",
        ".",
        "--out",
        Path.expand(output_path),
        "--lib",
        Path.expand(build_lib)
      ]

      case System.cmd(gleam, args, cd: dep_path, stderr_to_stdout: true) do
        {_output, 0} ->
          output_path
          |> Path.join("ebin")
          |> Path.expand()
          |> Code.prepend_path()

          :ok

        {output, _status} ->
          Mix.shell().error(output)
          :error
      end
    else
      Mix.shell().error("Missing Gleam dependency #{package}; run mix deps.get")
      :error
    end
  end
end

defmodule Wardwright.MixProject do
  use Mix.Project

  @gleam_release_runtime_deps ~w(
    act
    gleam_community_colour
    gleam_erlang
    gleam_json
    gleam_otp
    gleam_stdlib
    gleam_time
    glizzy
    houdini
    lustre
    non_empty_list
    trie_again
  )

  def project do
    [
      app: :wardwright,
      version: "0.0.11",
      elixir: "~> 1.18",
      compilers: [:gleam_deps, :gleam] ++ Mix.compilers(),
      aliases: ["deps.get": ["deps.get", "gleam.deps.get"]],
      erlc_paths: [
        "_build/#{Mix.env()}/lib/wardwright/_gleam_artefacts"
      ],
      erlc_include_path: "_build/#{Mix.env()}/lib/wardwright/include",
      listeners: [Phoenix.CodeReloader],
      prune_code_paths: false,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      assay: [
        dialyzer: [
          apps: [:project_plus_deps, :crypto, :inets, :ssl, :public_key, :mix],
          warning_apps: :project
        ]
      ],
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
          elixir_version: "1.20.0",
          otp_version: "29.0"
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
      {:dune, "~> 0.3.16"},
      {:gleam_stdlib, "~> 1.0", compile: false, app: false, override: true},
      {:gleam_erlang, "~> 1.3", compile: false, app: false},
      {:gleam_json, "~> 3.1", compile: false, app: false},
      {:gleam_otp, "~> 1.2", compile: false, app: false},
      {:gleam_community_colour, "~> 2.0", compile: false, app: false},
      {:gleam_time, "~> 1.8", compile: false, app: false},
      {:houdini, "~> 1.2", compile: false, app: false},
      {:lustre, "~> 5.7", compile: false, app: false},
      {:glizzy, "~> 0.1.0", compile: false, app: false},
      {:act, "~> 0.4", compile: false, app: false},
      {:non_empty_list, "~> 2.3", compile: false, app: false},
      {:trie_again, "~> 1.1", compile: false, app: false},
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
      {:assay, "~> 0.5.2", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
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
        steps: [:assemble, &include_gleam_runtime_modules/1, &Burrito.wrap/1],
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

  defp include_gleam_runtime_modules(%Mix.Release{} = release) do
    app_ebin =
      Path.join([
        release.path,
        "lib",
        "#{release.name}-#{release.version}",
        "ebin"
      ])

    build_lib = Path.join(Mix.Project.build_path(), "lib")

    for dep <- @gleam_release_runtime_deps do
      dep_ebin = Path.join([build_lib, dep, "ebin"])

      if !File.dir?(dep_ebin) do
        Mix.raise("Gleam runtime dependency #{dep} was not compiled at #{dep_ebin}")
      end

      dep_ebin
      |> Path.join("*.beam")
      |> Path.wildcard()
      |> Enum.each(fn beam ->
        File.cp!(beam, Path.join(app_ebin, Path.basename(beam)))
      end)
    end

    release
  end
end
