defmodule Wardwright.CLIAdaptersTest do
  use ExUnit.Case, async: true

  alias Wardwright.AgentAdapters.Identity
  alias Wardwright.AgentAdapters.OmpPack
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
    assert opencode.runtime_source == "hint"
    assert opencode.adapter_id == "wardwright-omp"
    assert opencode.coverage == "covered_through_runtime"
    assert opencode.fidelity == "runtime_verified"
    assert opencode.state == "installable"
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
