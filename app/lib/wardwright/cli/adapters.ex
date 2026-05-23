defmodule Wardwright.CLI.Adapters do
  @moduledoc false

  @targets [
    %{
      binaries: ~w(omp oh-my-pi),
      default_runtime: "omp",
      description: "Project-local OMP read-before-edit adapter.",
      label: "OMP / oh-my-pi",
      surface: "omp",
      target: "omp"
    },
    %{
      binaries: ~w(pi),
      default_runtime: "pi",
      description: "Pi adapter identity and state-fidelity probe support.",
      label: "Pi",
      surface: "pi",
      target: "pi"
    },
    %{
      binaries: ~w(opencode),
      default_runtime: nil,
      description: "Runtime-dependent support through Pi/OMP, OpenCode-native, or Codex.",
      label: "OpenCode",
      surface: "opencode",
      target: "opencode"
    },
    %{
      binaries: ~w(openclaw),
      default_runtime: nil,
      description: "Runtime integration for Pi, Codex, or supported CLI backends.",
      label: "OpenClaw",
      surface: "openclaw",
      target: "openclaw"
    },
    %{
      binaries: ~w(claude),
      default_runtime: "claude-cli",
      description: "Gateway identity candidate; native state-fidelity support is not claimed.",
      label: "Claude Code",
      surface: "claude-code",
      target: "claude-code"
    }
  ]

  def run(argv, write_fun, opts \\ []) do
    case argv do
      ["list", "--json" | _] ->
        list(opts)
        |> JSON.encode!()
        |> write_fun.()

        0

      ["list" | _] ->
        write_fun.(list_human(opts))
        0

      ["doctor", "--json" | _] ->
        doctor(opts)
        |> JSON.encode!()
        |> write_fun.()

        0

      ["doctor" | _] ->
        write_fun.(doctor_human(opts))
        0

      _ ->
        write_fun.(help())
        2
    end
  end

  def list(_opts \\ []) do
    Enum.map(@targets, fn target ->
      resolution = catalog_resolution(target)

      %{
        adapter_id: resolution.adapter_id,
        coverage: resolution.coverage,
        description: target.description,
        fidelity: resolution.fidelity,
        install_strategy: resolution.install_strategy,
        label: target.label,
        runtime: target.default_runtime || "runtime_detected_by_doctor",
        surface: target.surface,
        target: target.target
      }
    end)
  end

  def doctor(opts \\ []) do
    Enum.map(@targets, &doctor_target(&1, opts))
  end

  defp list_human(opts) do
    rows =
      opts
      |> list()
      |> Enum.map_join("\n\n", fn row ->
        "#{row.target}: #{row.label}\n  adapter: #{blank_adapter(row.adapter_id)}\n  runtime: #{row.runtime}\n  fidelity: #{row.fidelity}\n  #{row.description}"
      end)

    """
    Wardwright adapters

    #{rows}
    """
  end

  defp doctor_human(opts) do
    rows =
      opts
      |> doctor()
      |> Enum.map_join("\n\n", fn row ->
        next_actions =
          row.next_actions
          |> Enum.map_join("\n", &"  next: #{&1}")

        """
        #{row.label}: #{if row.detected, do: "detected", else: "not detected"}
          runtime: #{row.runtime}#{runtime_source(row)}
          adapter: #{blank_adapter(row.adapter_id)}
          status: #{row.state}
          install: #{row.install_plan}
        #{next_actions}
        """
        |> String.trim_trailing()
      end)

    """
    Wardwright adapter doctor

    #{rows}
    """
  end

  defp doctor_target(target, opts) do
    detected_path = detected_path(target, opts)
    runtime = runtime_for(target, detected_path, opts)
    resolution = resolution_for(target.surface, runtime)
    supported? = supported_resolution?(resolution)
    detected? = is_binary(detected_path)

    state =
      :wardwright@adapter_core.adapter_state(
        detected?,
        supported?,
        supported?,
        false,
        true,
        false,
        false
      )

    %{
      adapter_id: resolution.adapter_id,
      coverage: resolution.coverage,
      detected: detected?,
      detected_path: detected_path,
      fidelity: resolution.fidelity,
      install_plan: :wardwright@adapter_core.install_plan(state, "project", false),
      label: target.label,
      next_actions: next_actions(state, target, resolution),
      runtime: if(detected?, do: runtime, else: "not_detected"),
      runtime_source: runtime_source(target, detected_path, opts),
      state: state,
      target: target.target
    }
  end

  defp catalog_resolution(%{default_runtime: nil}), do: unsupported_resolution()

  defp catalog_resolution(target), do: resolution_for(target.surface, target.default_runtime)

  defp resolution_for(surface, runtime) when is_binary(runtime) do
    {adapter_id, coverage, install_strategy, fidelity} = :wardwright@adapter_core.resolve_adapter(surface, runtime)

    %{
      adapter_id: adapter_id,
      coverage: coverage,
      fidelity: fidelity,
      install_strategy: install_strategy
    }
  end

  defp resolution_for(_surface, _runtime), do: unsupported_resolution()

  defp unsupported_resolution do
    %{
      adapter_id: "",
      coverage: "unsupported_runtime",
      fidelity: "unsupported",
      install_strategy: "no_install"
    }
  end

  defp supported_resolution?(%{adapter_id: adapter_id}), do: adapter_id != ""

  defp detected_path(target, opts) do
    find_executable = Keyword.get(opts, :find_executable, &System.find_executable/1)

    Enum.find_value(target.binaries, fn binary ->
      case find_executable.(binary) do
        path when is_binary(path) -> path
        _ -> nil
      end
    end)
  end

  defp runtime_for(target, nil, _opts), do: target.default_runtime || "unknown"

  defp runtime_for(target, _detected_path, opts) do
    runtime_hints = Keyword.get(opts, :runtime_hints, %{})
    hinted_runtime = Map.get(runtime_hints, target.target)
    hinted_runtime || target.default_runtime || "unknown"
  end

  defp runtime_source(target, nil, _opts) do
    if target.default_runtime, do: "default", else: "not_detected"
  end

  defp runtime_source(target, _detected_path, opts) do
    runtime_hints = Keyword.get(opts, :runtime_hints, %{})

    if Map.has_key?(runtime_hints, target.target) do
      "hint"
    else
      "default"
    end
  end

  defp runtime_source(%{runtime_source: "hint"}), do: " via runtime hint"
  defp runtime_source(%{runtime_source: "default"}), do: " via default"
  defp runtime_source(_row), do: ""

  defp next_actions("not_detected", target, _resolution), do: ["install #{Enum.join(target.binaries, " or ")} first"]

  defp next_actions("installable", target, resolution) do
    ["run `wardwright adapters install #{target.target}` to #{install_summary(resolution.install_strategy)}"]
  end

  defp next_actions("unsupported_runtime", %{target: target}, _resolution) when target in ["opencode", "openclaw"] do
    [
      "runtime detection is incomplete for this surface; provide a supported Pi, OMP, or Codex runtime before installing"
    ]
  end

  defp next_actions("unsupported_runtime", _target, _resolution),
    do: action("no packaged adapter is available for this runtime yet")

  defp next_actions("installed_unverified", target, _resolution),
    do: ["run `wardwright adapters pair #{target.target}` or `wardwright adapters probe #{target.target}`"]

  defp next_actions("verified", target, _resolution),
    do: ["run `wardwright adapters probe #{target.target}` for stronger replay affordances"]

  defp next_actions("verified_with_probe", _target, _resolution),
    do: action("adapter identity and runtime probe are verified")

  defp next_actions("drifted", target, _resolution),
    do: [
      "review local edits, then run `wardwright adapters install #{target.target} --repair` if replacement is intentional"
    ]

  defp next_actions(_state, _target, _resolution), do: []

  defp install_summary("install_runtime_adapter"), do: "install the runtime adapter"
  defp install_summary("install_plugin_scaffold"), do: "install the plugin/import scaffold"
  defp install_summary("install_gateway_identity"), do: "install gateway identity support"
  defp install_summary(_install_strategy), do: "install adapter support files"

  defp action(message), do: [message]

  defp blank_adapter(""), do: "none"
  defp blank_adapter(adapter_id), do: adapter_id

  defp help do
    """
    wardwright adapters

    Usage:
      wardwright adapters list          List known adapter targets
      wardwright adapters list --json   Print machine-readable adapter targets
      wardwright adapters doctor        Detect local runtime and adapter status
      wardwright adapters doctor --json Print machine-readable doctor output
    """
  end
end
