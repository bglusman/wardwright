defmodule Wardwright.CLI.Adapters do
  @moduledoc false

  alias Wardwright.AgentAdapters.GatewayPairing
  alias Wardwright.AgentAdapters.Identity
  alias Wardwright.AgentAdapters.OmpInstaller
  alias Wardwright.AgentAdapters.OmpPack

  @key_adapter_id "adapter_id"
  @key_adapter_version "adapter_version"
  @key_expires_at "expires_at"
  @key_gateway_url "gateway_url"
  @key_runtime "runtime"
  @key_target "target"
  @key_workspace_fingerprint "workspace_fingerprint"

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

      ["install", target | rest] ->
        install(target, rest, write_fun, opts)

      ["uninstall", target | rest] ->
        uninstall(target, rest, write_fun, opts)

      ["pair", target | rest] ->
        pair(target, rest, write_fun, opts)

      ["probe", target | rest] ->
        probe(target, rest, write_fun, opts)

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

  def install(target, argv, write_fun, opts \\ [])

  def install("omp", argv, write_fun, opts) do
    with {:ok, parsed} <- parse_install_args(argv),
         :ok <- ensure_project_scope(parsed.scope),
         :ok <- ensure_runtime_detected("omp", opts) do
      workspace_root = Keyword.get(opts, :workspace_root, File.cwd!())

      case OmpInstaller.install(workspace_root, repair?: parsed.repair?) do
        {:ok, result} ->
          write_fun.(install_success_human(result))
          0

        {:error, :repair_required, inspection} ->
          write_fun.(repair_required_human(inspection))
          1
      end
    else
      {:error, message} ->
        write_fun.(message)
        2
    end
  end

  def install(_target, _argv, write_fun, _opts) do
    write_fun.("Only `wardwright adapters install omp` is implemented in this loop.")
    2
  end

  def uninstall(target, argv, write_fun, opts \\ [])

  def uninstall("omp", argv, write_fun, opts) do
    with {:ok, parsed} <- parse_scope_args(argv),
         :ok <- ensure_project_scope(parsed.scope) do
      workspace_root = Keyword.get(opts, :workspace_root, File.cwd!())
      {:ok, result} = OmpInstaller.uninstall(workspace_root)
      write_fun.(uninstall_success_human(result))
      0
    else
      {:error, message} ->
        write_fun.(message)
        2
    end
  end

  def uninstall(_target, _argv, write_fun, _opts) do
    write_fun.("Only `wardwright adapters uninstall omp` is implemented in this loop.")
    2
  end

  def pair(target, argv, write_fun, opts \\ [])

  def pair("omp", argv, write_fun, opts) do
    with {:ok, parsed} <- parse_scope_args(argv),
         :ok <- ensure_project_scope(parsed.scope),
         :ok <- ensure_runtime_detected("omp", opts),
         {:ok, gateway_token} <- gateway_token(opts),
         {:ok, identity} <- request_pairing_identity(gateway_token, opts),
         {:ok, result} <- OmpInstaller.pair(Keyword.get(opts, :workspace_root, File.cwd!()), identity) do
      write_fun.(pair_success_human(result, identity))
      0
    else
      {:error, :not_installed, _inspection} ->
        write_fun.("Cannot pair OMP adapter: run `wardwright adapters install omp` first.")
        1

      {:error, :repair_required, _inspection} ->
        write_fun.("Cannot pair OMP adapter: installed files are drifted; repair them before pairing.")
        1

      {:error, message} ->
        write_fun.(message)
        2
    end
  end

  def pair(_target, _argv, write_fun, _opts) do
    write_fun.("Only `wardwright adapters pair omp` is implemented in this loop.")
    2
  end

  def probe(target, argv, write_fun, opts \\ [])

  def probe("omp", argv, write_fun, opts) do
    with {:ok, parsed} <- parse_scope_args(argv),
         :ok <- ensure_project_scope(parsed.scope),
         {:ok, omp_bin} <- detected_runtime_path("omp", opts, "probe") do
      probe_opts =
        opts
        |> Keyword.put(:omp_bin, omp_bin)
        |> Keyword.take([:identity_secret, :node_bin, :now, :omp_bin, :probe_runner, :probe_script_path])

      case OmpInstaller.probe(Keyword.get(opts, :workspace_root, File.cwd!()), probe_opts) do
        {:ok, result} ->
          write_fun.(probe_success_human(result))
          0

        {:error, :not_installed, _inspection} ->
          write_fun.("Cannot probe OMP adapter: run `wardwright adapters install omp` first.")
          1

        {:error, :repair_required, _inspection} ->
          write_fun.("Cannot probe OMP adapter: installed files are drifted; repair them before probing.")
          1

        {:error, :not_paired, _config} ->
          write_fun.("Cannot probe OMP adapter: run `wardwright adapters pair omp` first.")
          1

        {:error, :probe_failed, result} ->
          write_fun.(probe_failed_human(result))
          1
      end
    else
      {:error, message} ->
        write_fun.(message)
        2
    end
  end

  def probe(_target, _argv, write_fun, _opts) do
    write_fun.("Only `wardwright adapters probe omp` is implemented in this loop.")
    2
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
    installation = installation_for(target, opts)

    state =
      :wardwright@adapter_core.adapter_state(
        detected?,
        supported?,
        supported?,
        installation.installed_files_present,
        installation.installed_manifest_matches,
        installation.identity_verified,
        installation.runtime_probe_passed
      )

    %{
      adapter_id: resolution.adapter_id,
      coverage: resolution.coverage,
      detected: detected?,
      detected_path: detected_path,
      fidelity: resolution.fidelity,
      install_plan: :wardwright@adapter_core.install_plan(state, "project", false),
      installed_paths: installation.installed_paths,
      label: target.label,
      next_actions: next_actions(state, target, resolution),
      runtime: if(detected?, do: runtime, else: "not_detected"),
      runtime_source: runtime_source(target, detected_path, opts),
      state: state,
      target: target.target
    }
  end

  defp installation_for(%{target: "omp"}, opts) do
    workspace_root = Keyword.get(opts, :workspace_root, File.cwd!())

    inspection =
      OmpInstaller.status(workspace_root,
        identity_secret: Keyword.get(opts, :identity_secret),
        now: Keyword.get(opts, :now, DateTime.utc_now())
      )

    %{
      identity_verified: inspection.identity_verified,
      installed_files_present: inspection.installed_files_present,
      installed_manifest_matches: inspection.installed_manifest_matches,
      installed_paths: inspection.files |> Enum.filter(& &1.present?) |> Enum.map(& &1.path),
      runtime_probe_passed: inspection.runtime_probe_passed
    }
  end

  defp installation_for(_target, _opts) do
    %{
      identity_verified: false,
      installed_files_present: false,
      installed_manifest_matches: true,
      installed_paths: [],
      runtime_probe_passed: false
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

  defp ensure_runtime_detected(target, opts) do
    case detected_runtime_path(target, opts, "install") do
      {:ok, _path} -> :ok
      error -> error
    end
  end

  defp detected_runtime_path(target_name, opts, action) do
    target = Enum.find(@targets, &(&1.target == target_name))

    case detected_path(target, opts) do
      path when is_binary(path) -> {:ok, path}
      _path -> {:error, "Cannot #{action} OMP adapter: install omp or oh-my-pi first."}
    end
  end

  defp parse_install_args(argv) do
    parse_scope_args(argv, %{repair?: false, scope: "project"})
  end

  defp parse_scope_args(argv, parsed \\ %{scope: "project"}) do
    case argv do
      [] ->
        {:ok, parsed}

      ["--repair" | rest] ->
        parse_scope_args(rest, Map.put(parsed, :repair?, true))

      ["--scope", scope | rest] when scope in ["project", "user"] ->
        parse_scope_args(rest, Map.put(parsed, :scope, scope))

      [<<"--scope=", scope::binary>> | rest] ->
        if scope in ["project", "user"] do
          parse_scope_args(rest, Map.put(parsed, :scope, scope))
        else
          {:error, "Unknown adapter scope: #{scope}"}
        end

      [unknown | _rest] ->
        {:error, "Unknown adapter option: #{unknown}"}
    end
  end

  defp ensure_project_scope("project"), do: :ok
  defp ensure_project_scope("user"), do: {:error, "User-scope adapter install is not implemented yet."}

  defp install_success_human(result) do
    verb = if result.repaired?, do: "Repaired", else: "Installed"

    """
    #{verb} OMP adapter files:
    #{Enum.map_join(result.written, "\n", &"  #{&1}")}
    """
  end

  defp repair_required_human(inspection) do
    present =
      inspection.files
      |> Enum.filter(& &1.present?)
      |> Enum.map_join("\n", &"  #{&1.path}")

    """
    OMP adapter files are present but do not match the Wardwright adapter pack.
    Review local edits before replacing them, then rerun with `--repair`.
    Present files:
    #{present}
    """
  end

  defp uninstall_success_human(result) do
    skipped =
      case result.skipped do
        [] -> "  none"
        paths -> Enum.map_join(paths, "\n", &"  #{&1}")
      end

    removed =
      case result.removed do
        [] -> "  none"
        paths -> Enum.map_join(paths, "\n", &"  #{&1}")
      end

    """
    Removed Wardwright-owned OMP adapter files:
    #{removed}

    Skipped edited or unknown files:
    #{skipped}
    """
  end

  defp pair_success_human(result, identity) do
    """
    Paired OMP adapter with Wardwright gateway.
      config: #{result.path}
      adapter: #{Map.get(identity, @key_adapter_id)}
      expires_at: #{Map.get(identity, @key_expires_at)}
    """
  end

  defp probe_success_human(result) do
    """
    OMP runtime probe passed.
      config: #{result.config_path}
      probe: #{result.evidence.probe}
      status: #{result.evidence.status}
      probed_at: #{result.evidence.probed_at}
    """
  end

  defp probe_failed_human(result) do
    output =
      result.output
      |> to_string()
      |> String.trim()

    """
    OMP runtime probe failed.
      status: #{inspect(result.status)}
    #{indent_output(output)}
    """
  end

  defp indent_output(""), do: "  output: none"

  defp indent_output(output) do
    output
    |> String.split("\n")
    |> Enum.map_join("\n", &"  #{&1}")
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

  defp request_pairing_identity(gateway_token, opts) do
    workspace_root = Keyword.get(opts, :workspace_root, File.cwd!())
    gateway_url = gateway_url(opts)

    payload =
      Map.new([
        {@key_adapter_id, OmpPack.adapter_id()},
        {@key_adapter_version, OmpPack.adapter_version()},
        {@key_gateway_url, gateway_url},
        {@key_runtime, "omp"},
        {@key_target, "omp"},
        {@key_workspace_fingerprint, Identity.workspace_fingerprint(workspace_root)}
      ])

    pair_request_fun = Keyword.get(opts, :pair_request_fun, &GatewayPairing.request/3)
    pair_request_fun.(gateway_url, gateway_token, payload)
  end

  defp gateway_url(opts) do
    Keyword.get(opts, :gateway_url) ||
      System.get_env("WARDWRIGHT_GATEWAY_URL") ||
      "http://127.0.0.1:8787"
  end

  defp gateway_token(opts) do
    token =
      if Keyword.has_key?(opts, :gateway_token) do
        Keyword.get(opts, :gateway_token)
      else
        System.get_env("WARDWRIGHT_ADMIN_TOKEN")
      end

    case token do
      token when is_binary(token) and token != "" ->
        {:ok, token}

      _token ->
        {:error, "Cannot pair OMP adapter: set WARDWRIGHT_ADMIN_TOKEN for the local gateway."}
    end
  end

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
      wardwright adapters install omp [--scope project] [--repair]
      wardwright adapters uninstall omp [--scope project]
      wardwright adapters pair omp [--scope project]
      wardwright adapters probe omp [--scope project]
    """
  end
end
