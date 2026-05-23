defmodule Wardwright.CLIAdaptersTest do
  use ExUnit.Case, async: true

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
end
