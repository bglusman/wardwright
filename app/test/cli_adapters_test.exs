defmodule Wardwright.CLIAdaptersTest do
  use ExUnit.Case, async: true

  alias Wardwright.AgentAdapters.ClaudeCodePack
  alias Wardwright.AgentAdapters.Identity
  alias Wardwright.AgentAdapters.OmpPack
  alias Wardwright.AgentAdapters.PiPack
  alias Wardwright.CLI.Adapters

  test "list prints stable adapter targets without claiming runtime-specific OpenCode support" do
    collector = collector()

    assert 0 = Adapters.run(["list"], collector)

    output = collected()
    assert output =~ "Wardwright adapters"
    assert output =~ "omp: OMP / oh-my-pi"
    assert output =~ "adapter: wardwright-omp"
    assert output =~ "opencode: OpenCode"
    assert output =~ "runtime: runtime_detected_by_doctor"
    assert output =~ "fidelity: unsupported"
  end

  test "list JSON exposes stable target metadata for agents" do
    collector = collector()

    assert 0 = Adapters.run(["list", "--json"], collector)

    targets = collected() |> JSON.decode!()

    assert Enum.map(targets, & &1["target"]) == ["omp", "pi", "opencode", "openclaw", "claude-code"]

    omp = Enum.find(targets, &(&1["target"] == "omp"))
    assert omp["adapter_id"] == "wardwright-omp"
    assert omp["coverage"] == "native_runtime"
    assert omp["fidelity"] == "tts_runtime_probe"

    opencode = Enum.find(targets, &(&1["target"] == "opencode"))
    assert opencode["runtime"] == "runtime_detected_by_doctor"
    assert opencode["adapter_id"] == ""
  end

  test "doctor reports not_detected in an empty executable environment" do
    results = Adapters.doctor(find_executable: fn _binary -> nil end)

    assert Enum.all?(results, &(&1.detected == false))
    assert Enum.all?(results, &(&1.state == "not_detected"))

    omp = Enum.find(results, &(&1.target == "omp"))
    assert omp.runtime == "not_detected"
    assert omp.install_plan == "no_install"
    assert omp.next_actions == ["install omp or oh-my-pi first"]
  end

  test "doctor JSON exposes machine-readable state, runtime, paths, and next actions" do
    collector = collector()

    assert 0 = Adapters.run(["doctor", "--json"], collector, find_executable: fn _binary -> nil end)

    results = collected() |> JSON.decode!()

    omp = Enum.find(results, &(&1["target"] == "omp"))
    assert omp["detected"] == false
    assert omp["detected_path"] == nil
    assert omp["runtime"] == "not_detected"
    assert omp["state"] == "not_detected"
    assert omp["install_plan"] == "no_install"
    assert omp["installed_paths"] == []
    assert omp["next_actions"] == ["install omp or oh-my-pi first"]
  end

  test "doctor distinguishes native OMP from OpenCode covered through an OMP runtime" do
    finder = fn
      "omp" -> "/tmp/fake-bin/omp"
      "opencode" -> "/tmp/fake-bin/opencode"
      _binary -> nil
    end

    results =
      Adapters.doctor(
        find_executable: finder,
        runtime_hints: %{"opencode" => "omp"}
      )

    omp = Enum.find(results, &(&1.target == "omp"))
    assert omp.detected == true
    assert omp.runtime == "omp"
    assert omp.adapter_id == "wardwright-omp"
    assert omp.coverage == "native_runtime"
    assert omp.state == "installable"
    assert omp.install_plan == "install_project_files"

    opencode = Enum.find(results, &(&1.target == "opencode"))
    assert opencode.detected == true
    assert opencode.runtime == "omp"
    assert opencode.runtime_source == "runtime hint"
    assert opencode.adapter_id == "wardwright-omp"
    assert opencode.coverage == "covered_through_runtime"
    assert opencode.fidelity == "runtime_verified"
    assert opencode.state == "installable"
    assert opencode.install_plan == "install_runtime_adapter"

    assert opencode.next_actions == [
             "run `wardwright adapters install omp` to install the runtime adapter used by OpenCode"
           ]
  end

  test "doctor resolves OpenCode Pi bridge runtime from project configuration" do
    workspace = tmp_workspace("wardwright-opencode-pi-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "pi-opencode-bridge"
    })

    results =
      Adapters.doctor(
        find_executable: fake_opencode_finder(),
        workspace_root: workspace
      )

    opencode = Enum.find(results, &(&1.target == "opencode"))
    assert opencode.detected == true
    assert opencode.runtime == "pi"
    assert opencode.runtime_source == "pi-opencode-bridge"
    assert opencode.adapter_id == "wardwright-pi"
    assert opencode.coverage == "covered_through_runtime"
    assert opencode.fidelity == "runtime_verified"
    assert opencode.state == "installable"
    assert opencode.install_plan == "install_runtime_adapter"

    assert opencode.next_actions == [
             "run `wardwright adapters install pi` to install the runtime adapter used by OpenCode"
           ]
  end

  test "doctor keeps OpenCode-native lower fidelity instead of claiming Pi or OMP runtime verification" do
    workspace = tmp_workspace("wardwright-opencode-native-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_opencode_runtime_config(workspace, %{
      "agentRuntime" => %{
        "id" => "opencode-native",
        "source" => "project config"
      }
    })

    results =
      Adapters.doctor(
        find_executable: fake_opencode_finder(),
        workspace_root: workspace
      )

    opencode = Enum.find(results, &(&1.target == "opencode"))
    assert opencode.runtime == "opencode-native"
    assert opencode.runtime_source == "project config"
    assert opencode.adapter_id == "wardwright-opencode"
    assert opencode.coverage == "surface_scaffold"
    assert opencode.fidelity == "session_import_best_effort"
    assert opencode.state == "unsupported_runtime"
    assert opencode.install_plan == "no_install"
    refute opencode.fidelity == "runtime_verified"

    assert opencode.next_actions == [
             "OpenCode-native packaged plugin install is unavailable; use the current harness export scaffold for best-effort handoff"
           ]
  end

  test "install opencode refuses native scaffold without writing plugin files" do
    workspace = tmp_workspace("wardwright-opencode-native-install-refusal")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "opencode-native"
    })

    collector = collector()

    assert 2 =
             Adapters.run(["install", "opencode"], collector,
               find_executable: fake_opencode_finder(),
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "packaged plugin/import scaffold is not available yet"
    refute File.exists?(Path.join(workspace, ".opencode/plugins/wardwright-state-fidelity.ts"))
  end

  test "install pi writes Wardwright metadata and reports replay pieces as export-only" do
    workspace = tmp_workspace("wardwright-pi-install")
    collector = collector()

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "pi"], collector,
               find_executable: fake_pi_finder(),
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Installed Pi adapter metadata"
    assert output =~ "Export-only Pi replay pieces"
    assert output =~ "pi_session_jsonl"
    refute File.exists?(Path.join(workspace, ".pi"))

    assert File.exists?(Path.join(workspace, PiPack.config_path()))
    assert File.exists?(Path.join(workspace, PiPack.manifest_path()))

    results =
      Adapters.doctor(
        find_executable: fake_pi_finder(),
        workspace_root: workspace
      )

    pi = Enum.find(results, &(&1.target == "pi"))
    assert pi.state == "installed_unverified"
    assert pi.install_plan == "pair_or_probe"
    assert pi.export_only == ["pi_session_jsonl", "state_fidelity_probe_json", "import_commands"]
    assert PiPack.config_path() in pi.installed_paths

    assert pi.next_actions == [
             "run `wardwright adapters pair pi`; replay-state probes remain export-only for Pi"
           ]
  end

  test "pair pi verifies gateway identity without claiming a persistent runtime probe" do
    workspace = tmp_workspace("wardwright-pi-pair")
    secret = String.duplicate("pi-pair-secret", 4)
    now = ~U[2026-05-24 01:00:00Z]

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "pi"], collector(),
               find_executable: fake_pi_finder(),
               workspace_root: workspace
             )

    pair_request_fun = fn "http://127.0.0.1:8787", "gateway-token", payload ->
      assert payload["adapter_id"] == "wardwright-pi"
      assert payload["runtime"] == "pi"
      assert payload["target"] == "pi"
      assert payload["workspace_fingerprint"] == Identity.workspace_fingerprint(workspace)
      Identity.issue(payload, secret: secret, now: now)
    end

    collector = collector()

    assert 0 =
             Adapters.run(["pair", "pi"], collector,
               find_executable: fake_pi_finder(),
               gateway_token: "gateway-token",
               identity_secret: secret,
               now: now,
               pair_request_fun: pair_request_fun,
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Paired Pi adapter with Wardwright gateway"
    refute output =~ "gateway-token"

    config = JSON.decode!(File.read!(Path.join(workspace, PiPack.config_path())))
    assert config["paired"] == true
    assert get_in(config, ["gateway_identity", "adapter_id"]) == "wardwright-pi"
    assert config["export_only"] == ["pi_session_jsonl", "state_fidelity_probe_json", "import_commands"]

    results =
      Adapters.doctor(
        find_executable: fake_pi_finder(),
        identity_secret: secret,
        now: DateTime.add(now, 60, :second),
        workspace_root: workspace
      )

    pi = Enum.find(results, &(&1.target == "pi"))
    assert pi.state == "verified"
    assert pi.fidelity == "state_import_probe"
    assert pi.surface_probe == "not_applicable"

    assert pi.next_actions == [
             "Pi identity is verified; use harness export and state-fidelity verification for replay evidence"
           ]
  end

  test "uninstall pi removes Wardwright-owned metadata but leaves edited metadata in place" do
    workspace = tmp_workspace("wardwright-pi-uninstall")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "pi"], collector(),
               find_executable: fake_pi_finder(),
               workspace_root: workspace
             )

    config_path = Path.join(workspace, PiPack.config_path())
    File.write!(config_path, "local metadata edit\n")

    collector = collector()

    assert 0 =
             Adapters.run(["uninstall", "pi"], collector, workspace_root: workspace)

    output = collected()
    assert output =~ "Removed Wardwright-owned Pi adapter metadata"
    assert output =~ PiPack.manifest_path()
    assert output =~ "Skipped edited or unknown files"
    assert output =~ PiPack.config_path()

    assert File.read!(config_path) == "local metadata edit\n"
    refute File.exists?(Path.join(workspace, PiPack.manifest_path()))
  end

  test "probe pi is explicit about export-only state fidelity instead of marking runtime verification" do
    workspace = tmp_workspace("wardwright-pi-export-only-probe")
    collector = collector()

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 1 =
             Adapters.run(["probe", "pi"], collector,
               find_executable: fake_pi_finder(),
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Pi state-fidelity probing is export-only"
    assert output =~ "wardwright-state-fidelity-probe.json"
  end

  test "install and pair Claude Code writes prompt-handoff gateway identity metadata without probe claims" do
    workspace = tmp_workspace("wardwright-claude-code-install-pair")
    secret = String.duplicate("claude-pair-secret", 3)
    now = ~U[2026-05-24 02:00:00Z]

    on_exit(fn -> File.rm_rf!(workspace) end)

    collector = collector()

    assert 0 =
             Adapters.run(["install", "claude-code"], collector,
               find_executable: fake_claude_finder(),
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Installed Claude Code adapter metadata"
    assert output =~ "prompt_handoff"
    assert File.exists?(Path.join(workspace, ClaudeCodePack.config_path()))
    refute File.exists?(Path.join(workspace, ".claude"))

    results =
      Adapters.doctor(
        find_executable: fake_claude_finder(),
        workspace_root: workspace
      )

    claude = Enum.find(results, &(&1.target == "claude-code"))
    assert claude.state == "installed_unverified"
    assert claude.fidelity == "prompt_handoff"
    assert claude.install_plan == "pair_identity"
    assert claude.surface_probe == "not_applicable"

    assert claude.next_actions == [
             "run `wardwright adapters pair claude-code`; fidelity remains prompt_handoff"
           ]

    pair_request_fun = fn "http://127.0.0.1:8787", "gateway-token", payload ->
      assert payload["adapter_id"] == "wardwright-claude-code"
      assert payload["runtime"] == "claude-cli"
      assert payload["target"] == "claude-code"
      assert payload["workspace_fingerprint"] == Identity.workspace_fingerprint(workspace)
      Identity.issue(payload, secret: secret, now: now)
    end

    collector = collector()

    assert 0 =
             Adapters.run(["pair", "claude-code"], collector,
               find_executable: fake_claude_finder(),
               gateway_token: "gateway-token",
               identity_secret: secret,
               now: now,
               pair_request_fun: pair_request_fun,
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Paired Claude Code adapter with Wardwright gateway"
    refute output =~ "gateway-token"

    config = JSON.decode!(File.read!(Path.join(workspace, ClaudeCodePack.config_path())))
    assert config["paired"] == true
    assert config["fidelity"] == "prompt_handoff"
    assert config["native_state_fidelity"] == false
    assert get_in(config, ["gateway_identity", "adapter_id"]) == "wardwright-claude-code"

    results =
      Adapters.doctor(
        find_executable: fake_claude_finder(),
        identity_secret: secret,
        now: DateTime.add(now, 60, :second),
        workspace_root: workspace
      )

    claude = Enum.find(results, &(&1.target == "claude-code"))
    assert claude.state == "verified"
    assert claude.install_plan == "identity_verified"

    assert claude.next_actions == [
             "Claude Code identity is verified; use prompt or model-context handoff without native resume claims"
           ]
  end

  test "uninstall claude-code preserves edited adapter metadata" do
    workspace = tmp_workspace("wardwright-claude-code-uninstall")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "claude-code"], collector(),
               find_executable: fake_claude_finder(),
               workspace_root: workspace
             )

    config_path = Path.join(workspace, ClaudeCodePack.config_path())
    File.write!(config_path, "local Claude metadata edit\n")

    collector = collector()

    assert 0 =
             Adapters.run(["uninstall", "claude-code"], collector, workspace_root: workspace)

    output = collected()
    assert output =~ "Removed Wardwright-owned Claude Code adapter metadata"
    assert output =~ ClaudeCodePack.manifest_path()
    assert output =~ "Skipped edited or unknown files"
    assert output =~ ClaudeCodePack.config_path()

    assert File.read!(config_path) == "local Claude metadata edit\n"
    refute File.exists?(Path.join(workspace, ClaudeCodePack.manifest_path()))
  end

  test "doctor resolves OpenCode Codex runtime as gateway identity support without OMP probe claims" do
    workspace = tmp_workspace("wardwright-opencode-codex-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "openai-codex",
      "runtime_source" => "opencode provider config"
    })

    collector = collector()

    assert 0 =
             Adapters.run(["doctor", "--json"], collector,
               find_executable: fake_opencode_finder(),
               workspace_root: workspace
             )

    results = collected() |> JSON.decode!()
    opencode = Enum.find(results, &(&1["target"] == "opencode"))

    assert opencode["runtime"] == "codex"
    assert opencode["runtime_source"] == "opencode provider config"
    assert opencode["adapter_id"] == "wardwright-codex"
    assert opencode["coverage"] == "gateway_identity"
    assert opencode["fidelity"] == "prompt_handoff"
    assert opencode["state"] == "installable"
    assert opencode["install_plan"] == "install_gateway_identity"
    refute Enum.any?(opencode["next_actions"], &String.contains?(&1, "probe omp"))
  end

  test "doctor resolves OpenClaw auto Pi runtime through the Pi adapter" do
    workspace = tmp_workspace("wardwright-openclaw-pi-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_openclaw_runtime_config(workspace, %{
      "agentRuntime" => %{
        "id" => "Auto",
        "resolved" => "pi"
      }
    })

    results =
      Adapters.doctor(
        find_executable: fake_openclaw_finder(),
        workspace_root: workspace
      )

    openclaw = Enum.find(results, &(&1.target == "openclaw"))
    assert openclaw.detected == true
    assert openclaw.runtime == "pi"
    assert openclaw.runtime_source == "agentRuntime.auto -> pi"
    assert openclaw.adapter_id == "wardwright-pi"
    assert openclaw.coverage == "covered_through_runtime"
    assert openclaw.fidelity == "runtime_verified"
    assert openclaw.state == "installable"

    assert openclaw.next_actions == [
             "run `wardwright adapters install pi` to install the runtime adapter used by OpenClaw"
           ]
  end

  test "doctor resolves OpenClaw Codex runtime as gateway identity without Pi or OMP probe claims" do
    workspace = tmp_workspace("wardwright-openclaw-codex-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_openclaw_runtime_config(workspace, %{
      "agentRuntime" => %{
        "id" => "openai-codex",
        "source" => "OpenClaw agentRuntime.id"
      }
    })

    collector = collector()

    assert 0 =
             Adapters.run(["doctor", "--json"], collector,
               find_executable: fake_openclaw_finder(),
               workspace_root: workspace
             )

    results = collected() |> JSON.decode!()
    openclaw = Enum.find(results, &(&1["target"] == "openclaw"))

    assert openclaw["runtime"] == "codex"
    assert openclaw["runtime_source"] == "OpenClaw agentRuntime.id"
    assert openclaw["adapter_id"] == "wardwright-codex"
    assert openclaw["coverage"] == "gateway_identity"
    assert openclaw["fidelity"] == "prompt_handoff"
    assert openclaw["state"] == "installable"
    assert openclaw["install_plan"] == "install_gateway_identity"
    refute Enum.any?(openclaw["next_actions"], &String.contains?(&1, "probe omp"))
    refute Enum.any?(openclaw["next_actions"], &String.contains?(&1, "probe pi"))
  end

  test "doctor resolves OpenClaw Claude CLI backend through Claude Code identity support" do
    workspace = tmp_workspace("wardwright-openclaw-claude-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_openclaw_runtime_config(workspace, %{
      "cliBackend" => %{
        "id" => "claude-cli",
        "source" => "OpenClaw CLI backend"
      }
    })

    results =
      Adapters.doctor(
        find_executable: fake_openclaw_finder(),
        workspace_root: workspace
      )

    openclaw = Enum.find(results, &(&1.target == "openclaw"))
    assert openclaw.runtime == "claude-cli"
    assert openclaw.runtime_source == "OpenClaw CLI backend"
    assert openclaw.adapter_id == "wardwright-claude-code"
    assert openclaw.coverage == "gateway_identity"
    assert openclaw.fidelity == "prompt_handoff"
    assert openclaw.state == "installable"
    assert openclaw.install_plan == "install_gateway_identity"

    assert openclaw.next_actions == [
             "run `wardwright adapters install claude-code` to install the Claude CLI adapter used by OpenClaw"
           ]
  end

  test "doctor keeps unknown OpenClaw runtime unsupported without adapter claims" do
    workspace = tmp_workspace("wardwright-openclaw-unknown-runtime")
    on_exit(fn -> File.rm_rf!(workspace) end)

    write_openclaw_runtime_config(workspace, %{
      "agentRuntime" => %{
        "id" => "experimental-runtime",
        "source" => "OpenClaw agentRuntime.id"
      }
    })

    results =
      Adapters.doctor(
        find_executable: fake_openclaw_finder(),
        workspace_root: workspace
      )

    openclaw = Enum.find(results, &(&1.target == "openclaw"))
    assert openclaw.runtime == "experimental-runtime"
    assert openclaw.runtime_source == "OpenClaw agentRuntime.id"
    assert openclaw.adapter_id == ""
    assert openclaw.coverage == "unsupported_runtime"
    assert openclaw.fidelity == "unsupported"
    assert openclaw.state == "unsupported_runtime"
    assert openclaw.install_plan == "no_install"
  end

  test "doctor distinguishes OpenCode runtime verification from missing surface verification" do
    workspace = tmp_workspace("wardwright-opencode-runtime-verified")
    secret = String.duplicate("opencode-runtime-secret", 3)
    now = ~U[2026-05-23 22:00:00Z]

    on_exit(fn -> File.rm_rf!(workspace) end)

    setup_verified_omp_runtime(workspace, secret, now)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "omp-opencode-bridge"
    })

    results =
      Adapters.doctor(
        find_executable: fake_omp_and_opencode_finder(),
        identity_secret: secret,
        now: DateTime.add(now, 120, :second),
        workspace_root: workspace
      )

    opencode = Enum.find(results, &(&1.target == "opencode"))
    assert opencode.state == "verified_with_probe"
    assert opencode.fidelity == "runtime_verified"
    assert opencode.surface_probe == "not_run"

    assert opencode.next_actions == [
             "run `wardwright adapters probe opencode` to verify OpenCode reaches the runtime adapter"
           ]
  end

  test "probe opencode records surface verification only after the OMP runtime adapter is probed" do
    workspace = tmp_workspace("wardwright-opencode-surface-probe")
    secret = String.duplicate("opencode-surface-secret", 3)
    now = ~U[2026-05-23 22:30:00Z]
    test_pid = self()

    on_exit(fn -> File.rm_rf!(workspace) end)

    setup_verified_omp_runtime(workspace, secret, now)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "omp-opencode-bridge"
    })

    surface_probe_runner = fn request ->
      send(test_pid, {:opencode_surface_probe_request, request})

      assert request.opencode_bin == "/tmp/fake-bin/opencode"
      assert request.runtime == "omp"
      assert request.adapter_id == "wardwright-omp"
      assert request.workspace_root == workspace

      {:ok, "wardwright_surface_probe=passed\n"}
    end

    collector = collector()

    assert 0 =
             Adapters.run(["probe", "opencode"], collector,
               find_executable: fake_omp_and_opencode_finder(),
               identity_secret: secret,
               now: DateTime.add(now, 180, :second),
               opencode_surface_probe_runner: surface_probe_runner,
               workspace_root: workspace
             )

    assert_receive {:opencode_surface_probe_request, _request}
    assert collected() =~ "OpenCode surface probe passed"

    runtime_config = JSON.decode!(File.read!(Path.join(workspace, ".opencode/wardwright-runtime.json")))
    assert get_in(runtime_config, ["surface_probe", "status"]) == "passed"
    assert get_in(runtime_config, ["surface_probe", "probe"]) == "opencode_runtime_surface"
    assert get_in(runtime_config, ["surface_probe", "runtime"]) == "omp"
    assert get_in(runtime_config, ["surface_probe", "target"]) == "opencode"
    assert get_in(runtime_config, ["surface_probe", "output_sha256"]) =~ ~r/^[0-9a-f]{64}$/

    results =
      Adapters.doctor(
        find_executable: fake_omp_and_opencode_finder(),
        identity_secret: secret,
        now: DateTime.add(now, 240, :second),
        workspace_root: workspace
      )

    opencode = Enum.find(results, &(&1.target == "opencode"))
    assert opencode.state == "verified_with_probe"
    assert opencode.fidelity == "surface_verified"
    assert opencode.surface_probe == "passed"
    assert opencode.next_actions == ["OpenCode surface and underlying runtime probe are verified"]
  end

  test "probe opencode refuses lower-fidelity native runtime without invoking the surface runner" do
    workspace = tmp_workspace("wardwright-opencode-native-probe-refusal")
    test_pid = self()

    on_exit(fn -> File.rm_rf!(workspace) end)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "opencode-native"
    })

    collector = collector()

    assert 1 =
             Adapters.run(["probe", "opencode"], collector,
               find_executable: fake_opencode_finder(),
               opencode_surface_probe_runner: fn request ->
                 send(test_pid, {:unexpected_surface_probe, request})
                 {:ok, "wardwright_surface_probe=passed\n"}
               end,
               workspace_root: workspace
             )

    assert collected() =~ "OpenCode-native is lower-fidelity"
    refute_receive {:unexpected_surface_probe, _request}
  end

  test "probe opencode failure reports a digest instead of raw OpenCode output" do
    workspace = tmp_workspace("wardwright-opencode-surface-probe-failure")
    secret = String.duplicate("opencode-failure-secret", 3)
    now = ~U[2026-05-23 22:45:00Z]

    on_exit(fn -> File.rm_rf!(workspace) end)

    setup_verified_omp_runtime(workspace, secret, now)

    write_opencode_runtime_config(workspace, %{
      "runtime" => "omp-opencode-bridge"
    })

    collector = collector()

    assert 1 =
             Adapters.run(["probe", "opencode"], collector,
               find_executable: fake_omp_and_opencode_finder(),
               identity_secret: secret,
               now: DateTime.add(now, 180, :second),
               opencode_surface_probe_runner: fn _request ->
                 {:error, :probe_failed, %{output: "raw OpenCode probe transcript", status: 1}}
               end,
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "OpenCode surface probe failed"
    assert output =~ ~r/output_sha256: [0-9a-f]{64}/
    refute output =~ "raw OpenCode probe transcript"
  end

  test "install omp writes only project-local Wardwright adapter files" do
    workspace = tmp_workspace("wardwright-omp-install")
    collector = collector()

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector,
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Installed OMP adapter files"

    expected_paths = Enum.map(OmpPack.expected_files(), & &1.path)

    assert Enum.sort(expected_paths) ==
             workspace
             |> Path.join(".omp")
             |> all_relative_files()
             |> Enum.map(&Path.join(".omp", &1))
             |> Enum.sort()

    assert File.read!(Path.join(workspace, ".omp/rules/wardwright-read-before-edit.md")) =~
             "Wardwright read-before-edit replay guard"
  end

  test "doctor reports installed OMP files as unverified until pairing or probe evidence exists" do
    workspace = tmp_workspace("wardwright-omp-doctor-installed")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    results =
      Adapters.doctor(
        find_executable: fake_omp_finder(),
        workspace_root: workspace
      )

    omp = Enum.find(results, &(&1.target == "omp"))
    assert omp.state == "installed_unverified"
    assert omp.install_plan == "pair_or_probe"
    assert ".omp/wardwright-adapter-manifest.json" in omp.installed_paths
    assert omp.next_actions == ["run `wardwright adapters pair omp` or `wardwright adapters probe omp`"]
  end

  test "doctor detects modified OMP adapter files as drifted" do
    workspace = tmp_workspace("wardwright-omp-doctor-drifted")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    rule_path = Path.join(workspace, ".omp/rules/wardwright-read-before-edit.md")
    File.write!(rule_path, "local project edit\n")

    results =
      Adapters.doctor(
        find_executable: fake_omp_finder(),
        workspace_root: workspace
      )

    omp = Enum.find(results, &(&1.target == "omp"))
    assert omp.state == "drifted"
    assert omp.install_plan == "repair_required"

    assert omp.next_actions == [
             "review local edits, then run `wardwright adapters install omp --repair` if replacement is intentional"
           ]
  end

  test "install omp refuses to overwrite edited files unless repair is explicit" do
    workspace = tmp_workspace("wardwright-omp-repair")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    rule_path = Path.join(workspace, ".omp/rules/wardwright-read-before-edit.md")
    File.write!(rule_path, "local project edit\n")

    collector = collector()

    assert 1 =
             Adapters.run(["install", "omp"], collector,
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    assert File.read!(rule_path) == "local project edit\n"
    assert collected() =~ "rerun with `--repair`"

    assert 0 =
             Adapters.run(["install", "omp", "--repair"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    assert File.read!(rule_path) =~ "Wardwright read-before-edit replay guard"
  end

  test "uninstall omp removes Wardwright-owned files but leaves edited files in place" do
    workspace = tmp_workspace("wardwright-omp-uninstall")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    rule_path = Path.join(workspace, ".omp/rules/wardwright-read-before-edit.md")
    File.write!(rule_path, "local project edit\n")

    collector = collector()

    assert 0 =
             Adapters.run(["uninstall", "omp"], collector, workspace_root: workspace)

    output = collected()
    assert output =~ "Removed Wardwright-owned OMP adapter files"
    assert output =~ ".omp/extensions/wardwright-state-fidelity.ts"
    assert output =~ "Skipped edited or unknown files"
    assert output =~ ".omp/rules/wardwright-read-before-edit.md"

    assert File.read!(rule_path) == "local project edit\n"
    refute File.exists?(Path.join(workspace, ".omp/extensions/wardwright-state-fidelity.ts"))
    refute File.exists?(Path.join(workspace, ".omp/wardwright-adapter-manifest.json"))
  end

  test "pair omp requires a gateway token and does not mark installed files verified implicitly" do
    workspace = tmp_workspace("wardwright-omp-pair-token")
    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    collector = collector()

    assert 2 =
             Adapters.run(["pair", "omp"], collector,
               find_executable: fake_omp_finder(),
               gateway_token: "",
               workspace_root: workspace
             )

    assert collected() =~ "set WARDWRIGHT_ADMIN_TOKEN"

    config = JSON.decode!(File.read!(Path.join(workspace, OmpPack.config_path())))
    assert config["paired"] == false
    assert config["gateway_identity"] == nil
  end

  test "pair omp writes a gateway identity and doctor reports verified only when it validates for this workspace" do
    workspace = tmp_workspace("wardwright-omp-pair")
    secret = String.duplicate("pair-secret", 4)
    now = ~U[2026-05-23 20:00:00Z]

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    pair_request_fun = fn "http://127.0.0.1:8787", "gateway-token", payload ->
      assert payload["workspace_fingerprint"] == Identity.workspace_fingerprint(workspace)
      Identity.issue(payload, secret: secret, now: now)
    end

    collector = collector()

    assert 0 =
             Adapters.run(["pair", "omp"], collector,
               find_executable: fake_omp_finder(),
               gateway_token: "gateway-token",
               identity_secret: secret,
               now: now,
               pair_request_fun: pair_request_fun,
               workspace_root: workspace
             )

    output = collected()
    assert output =~ "Paired OMP adapter with Wardwright gateway"
    assert output =~ ".omp/wardwright-adapter.json"
    refute output =~ "gateway-token"

    config = JSON.decode!(File.read!(Path.join(workspace, OmpPack.config_path())))
    assert config["paired"] == true
    assert get_in(config, ["gateway_identity", "adapter_id"]) == "wardwright-omp"
    assert is_binary(get_in(config, ["gateway_identity", "token"]))

    results =
      Adapters.doctor(
        find_executable: fake_omp_finder(),
        identity_secret: secret,
        now: DateTime.add(now, 60, :second),
        workspace_root: workspace
      )

    omp = Enum.find(results, &(&1.target == "omp"))
    assert omp.state == "verified"
    assert omp.install_plan == "probe_for_stronger_verification"
    assert omp.next_actions == ["run `wardwright adapters probe omp` for stronger replay affordances"]
  end

  test "probe omp runs against the installed rule and paired adapter identity before marking probe verified" do
    workspace = tmp_workspace("wardwright-omp-probe")
    secret = String.duplicate("probe-secret", 4)
    now = ~U[2026-05-23 21:00:00Z]
    test_pid = self()

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    pair_request_fun = fn "http://127.0.0.1:8787", "gateway-token", payload ->
      Identity.issue(payload, secret: secret, now: now)
    end

    assert 0 =
             Adapters.run(["pair", "omp"], collector(),
               find_executable: fake_omp_finder(),
               gateway_token: "gateway-token",
               identity_secret: secret,
               now: now,
               pair_request_fun: pair_request_fun,
               workspace_root: workspace
             )

    probe_runner = fn request ->
      send(test_pid, {:probe_request, request})

      assert request.omp_bin == "/tmp/fake-bin/omp"
      assert File.read!(request.rule_path) =~ "Wardwright read-before-edit replay guard"

      config = JSON.decode!(File.read!(request.config_path))
      assert config["paired"] == true
      assert get_in(config, ["gateway_identity", "adapter_id"]) == "wardwright-omp"

      {:ok, "PASS edit: expected trigger\nPASS read: expected not trigger\n"}
    end

    collector = collector()

    assert 0 =
             Adapters.run(["probe", "omp"], collector,
               find_executable: fake_omp_finder(),
               identity_secret: secret,
               now: DateTime.add(now, 60, :second),
               probe_runner: probe_runner,
               workspace_root: workspace
             )

    assert_receive {:probe_request, request}
    output = collected()
    assert output =~ "OMP runtime probe passed"
    assert output =~ "omp_ttsr_runtime_equivalence"
    refute output =~ get_in(JSON.decode!(File.read!(request.config_path)), ["gateway_identity", "token"])

    config = JSON.decode!(File.read!(Path.join(workspace, OmpPack.config_path())))
    assert get_in(config, ["runtime_probe", "status"]) == "passed"
    assert get_in(config, ["runtime_probe", "probe"]) == "omp_ttsr_runtime_equivalence"
    assert get_in(config, ["runtime_probe", "output_sha256"]) =~ ~r/^[0-9a-f]{64}$/
    refute inspect(config["runtime_probe"]) =~ get_in(config, ["gateway_identity", "token"])

    results =
      Adapters.doctor(
        find_executable: fake_omp_finder(),
        identity_secret: secret,
        now: DateTime.add(now, 120, :second),
        workspace_root: workspace
      )

    omp = Enum.find(results, &(&1.target == "omp"))
    assert omp.state == "verified_with_probe"
    assert omp.install_plan == "already_verified_with_probe"
    assert omp.next_actions == ["adapter identity and runtime probe are verified"]
  end

  test "probe omp refuses to run before the installed adapter is paired" do
    workspace = tmp_workspace("wardwright-omp-probe-unpaired")
    test_pid = self()

    on_exit(fn -> File.rm_rf!(workspace) end)

    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    collector = collector()

    assert 1 =
             Adapters.run(["probe", "omp"], collector,
               find_executable: fake_omp_finder(),
               probe_runner: fn request ->
                 send(test_pid, {:unexpected_probe, request})
                 {:ok, "PASS\n"}
               end,
               workspace_root: workspace
             )

    assert collected() =~ "run `wardwright adapters pair omp` first"
    refute_receive {:unexpected_probe, _request}
  end

  test "doctor human output explains unsupported detected runtime without overclaiming install support" do
    collector = collector()

    assert 0 =
             Adapters.run(["doctor"], collector,
               find_executable: fn
                 "opencode" -> "/tmp/fake-bin/opencode"
                 _binary -> nil
               end
             )

    output = collected()
    assert output =~ "OpenCode: detected"
    assert output =~ "runtime: unknown via default"
    assert output =~ "adapter: none"
    assert output =~ "status: unsupported_runtime"
    assert output =~ "runtime detection is incomplete"
  end

  test "CLI routes adapter subcommands through the adapter runner" do
    collector = collector()

    assert {:halt, 0} =
             Wardwright.CLI.run(["adapters", "doctor"], collector, fn _path, _write_fun -> 0 end, fn args, write_fun ->
               write_fun.("adapter args: #{Enum.join(args, " ")}")
               0
             end)

    assert collected() =~ "adapter args: doctor"
  end

  defp collector do
    owner = self()

    fn line ->
      send(owner, {:cli_output, line})
    end
  end

  defp collected do
    collect_messages([])
  end

  defp collect_messages(lines) do
    receive do
      {:cli_output, line} -> collect_messages([line | lines])
    after
      0 -> lines |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp fake_omp_finder do
    fn
      "omp" -> "/tmp/fake-bin/omp"
      _binary -> nil
    end
  end

  defp fake_opencode_finder do
    fn
      "opencode" -> "/tmp/fake-bin/opencode"
      _binary -> nil
    end
  end

  defp fake_pi_finder do
    fn
      "pi" -> "/tmp/fake-bin/pi"
      _binary -> nil
    end
  end

  defp fake_claude_finder do
    fn
      "claude" -> "/tmp/fake-bin/claude"
      _binary -> nil
    end
  end

  defp fake_openclaw_finder do
    fn
      "openclaw" -> "/tmp/fake-bin/openclaw"
      _binary -> nil
    end
  end

  defp fake_omp_and_opencode_finder do
    fn
      "omp" -> "/tmp/fake-bin/omp"
      "opencode" -> "/tmp/fake-bin/opencode"
      _binary -> nil
    end
  end

  defp setup_verified_omp_runtime(workspace, secret, now) do
    assert 0 =
             Adapters.run(["install", "omp"], collector(),
               find_executable: fake_omp_finder(),
               workspace_root: workspace
             )

    pair_request_fun = fn "http://127.0.0.1:8787", "gateway-token", payload ->
      Identity.issue(payload, secret: secret, now: now)
    end

    assert 0 =
             Adapters.run(["pair", "omp"], collector(),
               find_executable: fake_omp_finder(),
               gateway_token: "gateway-token",
               identity_secret: secret,
               now: now,
               pair_request_fun: pair_request_fun,
               workspace_root: workspace
             )

    assert 0 =
             Adapters.run(["probe", "omp"], collector(),
               find_executable: fake_omp_finder(),
               identity_secret: secret,
               now: DateTime.add(now, 60, :second),
               probe_runner: fn _request ->
                 {:ok, "PASS edit: expected trigger\nPASS read: expected not trigger\n"}
               end,
               workspace_root: workspace
             )
  end

  defp write_opencode_runtime_config(workspace, payload) do
    path = Path.join(workspace, ".opencode/wardwright-runtime.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(payload))
  end

  defp write_openclaw_runtime_config(workspace, payload) do
    path = Path.join(workspace, ".openclaw/wardwright-runtime.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(payload))
  end

  defp tmp_workspace(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp all_relative_files(path) do
    path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, path))
  end
end
