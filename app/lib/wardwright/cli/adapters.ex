defmodule Wardwright.CLI.Adapters do
  @moduledoc false

  alias Wardwright.AgentAdapters.GatewayPairing
  alias Wardwright.AgentAdapters.Identity
  alias Wardwright.AgentAdapters.OmpInstaller
  alias Wardwright.AgentAdapters.OmpPack
  alias Wardwright.AgentAdapters.OpenCodeRuntime

  @key_adapter_id "adapter_id"
  @key_adapter_version "adapter_version"
  @key_expires_at "expires_at"
  @key_gateway_url "gateway_url"
  @key_probe "probe"
  @key_probed_at "probed_at"
  @key_runtime "runtime"
  @key_status "status"
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

  def install("opencode", argv, write_fun, opts) do
    with {:ok, parsed} <- parse_install_args(argv),
         :ok <- ensure_project_scope(parsed.scope),
         {:ok, opencode_bin} <- detected_runtime_path("opencode", opts, "install") do
      target = Enum.find(@targets, &(&1.target == "opencode"))
      runtime_info = runtime_info_for(target, opencode_bin, opts)
      resolution = resolution_for(target.surface, runtime_info.runtime)

      write_fun.(opencode_install_unavailable_human(runtime_info, resolution))
      2
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

  def probe("opencode", argv, write_fun, opts) do
    with {:ok, parsed} <- parse_scope_args(argv),
         :ok <- ensure_project_scope(parsed.scope),
         {:ok, opencode_bin} <- detected_runtime_path("opencode", opts, "probe") do
      workspace_root = Keyword.get(opts, :workspace_root, File.cwd!())
      target = Enum.find(@targets, &(&1.target == "opencode"))
      runtime_info = runtime_info_for(target, opencode_bin, opts)
      resolution = resolution_for(target.surface, runtime_info.runtime)

      with :ok <- ensure_opencode_surface_probe_supported(runtime_info.runtime, resolution),
           :ok <- ensure_runtime_adapter_probe_verified(runtime_info.runtime, opts),
           {:ok, output} <-
             run_opencode_surface_probe(workspace_root, opencode_bin, runtime_info.runtime, resolution, opts),
           {:ok, evidence} <-
             OpenCodeRuntime.record_surface_probe(workspace_root, runtime_info.runtime, resolution.adapter_id, output,
               adapter_version: OmpPack.adapter_version(),
               now: Keyword.get(opts, :now, DateTime.utc_now())
             ) do
        write_fun.(opencode_probe_success_human(evidence))
        0
      else
        {:error, :runtime_not_configured} ->
          write_fun.(
            "Cannot probe OpenCode surface: write .opencode/wardwright-runtime.json with a supported runtime first."
          )

          1

        {:error, :probe_failed, result} ->
          write_fun.(opencode_probe_failed_human(result))
          1

        {:error, message} ->
          write_fun.(message)
          1
      end
    else
      {:error, message} ->
        write_fun.(message)
        2
    end
  end

  def probe(_target, _argv, write_fun, _opts) do
    write_fun.(
      "Only `wardwright adapters probe omp` and `wardwright adapters probe opencode` are implemented in this loop."
    )

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
          surface_probe: #{row.surface_probe}
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
    runtime_info = runtime_info_for(target, detected_path, opts)
    runtime = runtime_info.runtime
    resolution = resolution_for(target.surface, runtime)
    supported? = supported_resolution?(resolution)
    detected? = is_binary(detected_path)
    installation = installation_for(target, resolution, runtime_info, opts)
    fidelity = :wardwright@adapter_core.surface_fidelity(resolution.fidelity, installation.surface_probe_passed)

    installable? = installable_resolution?(resolution)

    state =
      :wardwright@adapter_core.adapter_state(
        detected?,
        supported?,
        installable?,
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
      fidelity: fidelity,
      install_plan: doctor_install_plan(state, target, resolution),
      installed_paths: installation.installed_paths,
      label: target.label,
      next_actions: next_actions(state, target, resolution, installation),
      runtime: if(detected?, do: runtime, else: "not_detected"),
      runtime_source: runtime_info.source,
      state: state,
      surface_probe: surface_probe_label(target, installation),
      target: target.target
    }
  end

  defp installation_for(%{target: "omp"}, _resolution, _runtime_info, opts) do
    runtime_adapter_installation("omp", opts)
  end

  defp installation_for(%{target: "opencode"}, %{coverage: "covered_through_runtime"}, runtime_info, opts) do
    runtime_info.runtime
    |> runtime_adapter_installation(opts)
    |> Map.put(:surface_probe_passed, Map.get(runtime_info, :surface_probe_passed, false))
  end

  defp installation_for(_target, _resolution, _runtime_info, _opts) do
    default_installation()
  end

  defp runtime_adapter_installation("omp", opts) do
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
      runtime_probe_passed: inspection.runtime_probe_passed,
      surface_probe_passed: false
    }
  end

  defp runtime_adapter_installation(_runtime, _opts), do: default_installation()

  defp default_installation do
    %{
      identity_verified: false,
      installed_files_present: false,
      installed_manifest_matches: true,
      installed_paths: [],
      runtime_probe_passed: false,
      surface_probe_passed: false
    }
  end

  defp doctor_install_plan("installable", %{target: "opencode"}, resolution), do: resolution.install_strategy

  defp doctor_install_plan(state, _target, _resolution),
    do: :wardwright@adapter_core.install_plan(state, "project", false)

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

  defp installable_resolution?(%{install_strategy: "no_install"}), do: false
  defp installable_resolution?(%{adapter_id: adapter_id}), do: adapter_id != ""

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
      path when is_binary(path) ->
        {:ok, path}

      _path ->
        {:error, "Cannot #{action} #{target.label} adapter: install #{Enum.join(target.binaries, " or ")} first."}
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

  defp opencode_probe_success_human(evidence) do
    """
    OpenCode surface probe passed.
      probe: #{Map.get(evidence, @key_probe)}
      status: #{Map.get(evidence, @key_status)}
      runtime: #{Map.get(evidence, @key_runtime)}
      probed_at: #{Map.get(evidence, @key_probed_at)}
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

  defp opencode_probe_failed_human(result) do
    output =
      result.output
      |> to_string()
      |> String.trim()

    """
    OpenCode surface probe failed.
      status: #{inspect(result.status)}
      output_sha256: #{sha256(output)}
    """
  end

  defp opencode_install_unavailable_human(%{runtime: "opencode-native"}, %{coverage: "surface_scaffold"}) do
    """
    Cannot install OpenCode-native adapter files: the packaged plugin/import scaffold is not available yet.
    Use the current harness export scaffold for best-effort handoff; doctor will keep this surface lower fidelity.
    """
  end

  defp opencode_install_unavailable_human(
         %{runtime: runtime},
         %{install_strategy: "install_runtime_adapter"} = resolution
       ) do
    runtime_target = runtime_adapter_target(resolution.adapter_id)

    """
    Cannot install OpenCode directly for runtime #{runtime}.
    Run `wardwright adapters install #{runtime_target}` to install the runtime adapter used by OpenCode.
    """
  end

  defp opencode_install_unavailable_human(%{runtime: "codex"}, _resolution) do
    """
    Cannot install OpenCode Codex-backed adapter files yet.
    Codex-backed OpenCode uses gateway identity support and must not run the OMP/Pi runtime probe.
    """
  end

  defp opencode_install_unavailable_human(_runtime_info, _resolution) do
    "Cannot install OpenCode adapter files: resolve OpenCode to a supported packaged runtime first."
  end

  defp indent_output(""), do: "  output: none"

  defp indent_output(output) do
    output
    |> String.split("\n")
    |> Enum.map_join("\n", &"  #{&1}")
  end

  defp runtime_info_for(target, nil, _opts) do
    %{
      runtime: target.default_runtime || "unknown",
      source: if(target.default_runtime, do: "default", else: "not_detected"),
      surface_probe_passed: false
    }
  end

  defp runtime_info_for(target, _detected_path, opts) do
    runtime_hints = Keyword.get(opts, :runtime_hints, %{})

    if Map.has_key?(runtime_hints, target.target) do
      %{runtime: Map.fetch!(runtime_hints, target.target), source: "runtime hint", surface_probe_passed: false}
    else
      detected_runtime_info_for(target, opts)
    end
  end

  defp detected_runtime_info_for(%{target: "opencode"} = target, opts) do
    workspace_root = Keyword.get(opts, :workspace_root, File.cwd!())

    case OpenCodeRuntime.resolve(workspace_root) do
      {:ok, runtime} ->
        %{runtime: runtime.runtime, source: runtime.source, surface_probe_passed: runtime.surface_probe_passed}

      :unknown ->
        %{runtime: target.default_runtime || "unknown", source: "default", surface_probe_passed: false}
    end
  end

  defp detected_runtime_info_for(target, _opts),
    do: %{runtime: target.default_runtime || "unknown", source: "default", surface_probe_passed: false}

  defp runtime_source(%{runtime_source: "default"}), do: " via default"
  defp runtime_source(%{runtime_source: "not_detected"}), do: ""
  defp runtime_source(%{runtime_source: source}) when is_binary(source) and source != "", do: " via #{source}"
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

  defp next_actions("not_detected", target, _resolution, _installation),
    do: ["install #{Enum.join(target.binaries, " or ")} first"]

  defp next_actions(
         "installable",
         %{target: "opencode"},
         %{coverage: "covered_through_runtime"} = resolution,
         _installation
       ) do
    runtime_target = runtime_adapter_target(resolution.adapter_id)

    ["run `wardwright adapters install #{runtime_target}` to install the runtime adapter used by OpenCode"]
  end

  defp next_actions("installable", %{target: "opencode"}, %{install_strategy: "install_plugin_scaffold"}, _installation) do
    [
      "OpenCode-native plugin install is not packaged yet; use the current harness export scaffold for best-effort handoff"
    ]
  end

  defp next_actions(
         "unsupported_runtime",
         %{target: "opencode"},
         %{coverage: "surface_scaffold", install_strategy: "no_install"},
         _installation
       ) do
    [
      "OpenCode-native packaged plugin install is unavailable; use the current harness export scaffold for best-effort handoff"
    ]
  end

  defp next_actions(
         "installable",
         %{target: "opencode"},
         %{install_strategy: "install_gateway_identity"},
         _installation
       ) do
    action(
      "install Codex/gateway identity support when that adapter surface is packaged; do not run the OMP runtime probe"
    )
  end

  defp next_actions("installable", target, resolution, _installation) do
    ["run `wardwright adapters install #{target.target}` to #{install_summary(resolution.install_strategy)}"]
  end

  defp next_actions("unsupported_runtime", %{target: target}, _resolution, _installation)
       when target in ["opencode", "openclaw"] do
    [
      "runtime detection is incomplete for this surface; provide a supported Pi, OMP, or Codex runtime before installing"
    ]
  end

  defp next_actions("unsupported_runtime", _target, _resolution, _installation),
    do: action("no packaged adapter is available for this runtime yet")

  defp next_actions("installed_unverified", target, _resolution, _installation),
    do: ["run `wardwright adapters pair #{target.target}` or `wardwright adapters probe #{target.target}`"]

  defp next_actions("verified", target, _resolution, _installation),
    do: ["run `wardwright adapters probe #{target.target}` for stronger replay affordances"]

  defp next_actions("verified_with_probe", %{target: "opencode"}, %{coverage: "covered_through_runtime"}, %{
         surface_probe_passed: false
       }), do: action("run `wardwright adapters probe opencode` to verify OpenCode reaches the runtime adapter")

  defp next_actions("verified_with_probe", %{target: "opencode"}, %{coverage: "covered_through_runtime"}, %{
         surface_probe_passed: true
       }), do: action("OpenCode surface and underlying runtime probe are verified")

  defp next_actions("verified_with_probe", _target, _resolution, _installation),
    do: action("adapter identity and runtime probe are verified")

  defp next_actions("drifted", target, _resolution, _installation),
    do: [
      "review local edits, then run `wardwright adapters install #{target.target} --repair` if replacement is intentional"
    ]

  defp next_actions(_state, _target, _resolution, _installation), do: []

  defp ensure_opencode_surface_probe_supported(runtime, %{coverage: "covered_through_runtime"})
       when runtime in ["omp", "pi"], do: :ok

  defp ensure_opencode_surface_probe_supported("opencode-native", _resolution),
    do:
      {:error,
       "Cannot probe OpenCode surface: OpenCode-native is lower-fidelity and has no packaged surface probe yet."}

  defp ensure_opencode_surface_probe_supported("codex", _resolution),
    do:
      {:error,
       "Cannot probe OpenCode surface: Codex-backed OpenCode uses gateway identity support, not the OMP/Pi runtime probe."}

  defp ensure_opencode_surface_probe_supported(_runtime, _resolution),
    do: {:error, "Cannot probe OpenCode surface: resolve OpenCode to a supported Pi or OMP runtime first."}

  defp ensure_runtime_adapter_probe_verified("omp", opts) do
    case runtime_adapter_installation("omp", opts) do
      %{identity_verified: true, runtime_probe_passed: true} -> :ok
      _installation -> {:error, "Cannot probe OpenCode surface: run `wardwright adapters probe omp` first."}
    end
  end

  defp ensure_runtime_adapter_probe_verified("pi", _opts),
    do: {:error, "Cannot probe OpenCode surface: packaged Pi runtime probe is not implemented yet."}

  defp run_opencode_surface_probe(workspace_root, opencode_bin, runtime, resolution, opts) do
    request = %{
      adapter_id: resolution.adapter_id,
      opencode_bin: opencode_bin,
      runtime: runtime,
      workspace_root: workspace_root
    }

    probe_runner = Keyword.get(opts, :opencode_surface_probe_runner, &OpenCodeRuntime.run_surface_probe/1)
    probe_runner.(request)
  end

  defp surface_probe_label(%{target: "opencode"}, %{surface_probe_passed: true}), do: "passed"
  defp surface_probe_label(%{target: "opencode"}, _installation), do: "not_run"
  defp surface_probe_label(_target, _installation), do: "not_applicable"

  defp sha256(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end

  defp install_summary("install_runtime_adapter"), do: "install the runtime adapter"
  defp install_summary("install_plugin_scaffold"), do: "install the plugin/import scaffold"
  defp install_summary("install_gateway_identity"), do: "install gateway identity support"
  defp install_summary(_install_strategy), do: "install adapter support files"

  defp runtime_adapter_target("wardwright-omp"), do: "omp"
  defp runtime_adapter_target("wardwright-pi"), do: "pi"
  defp runtime_adapter_target(_adapter_id), do: "opencode"

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
