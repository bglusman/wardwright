defmodule WardwrightWeb.AgentHarnessAdaptersTest do
  use Wardwright.RouterCase

  import Bitwise

  alias WardwrightWeb.AgentHarnessAdapters

  setup do
    store_dir =
      Path.join(
        System.tmp_dir!(),
        "wardwright-harness-adapters-#{System.unique_integer([:positive])}"
      )

    previous_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)

    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, store_dir)

    on_exit(fn ->
      File.rm_rf(store_dir)
      restore_env(:counterfactual_transcript_store_dir, previous_store_dir)
    end)

    :ok
  end

  test "adapter list makes fidelity limits explicit" do
    adapters = AgentHarnessAdapters.list()

    assert Enum.map(adapters, & &1["id"]) == [
             "opencode",
             "opencode-plugin",
             "claude",
             "codex",
             "pi",
             "oh-my-pi"
           ]

    opencode = Enum.find(adapters, &(&1["id"] == "opencode"))
    assert opencode["fidelity"] == "session_import_best_effort"
    assert opencode["equivalent_agent_resume"] == false
    assert opencode["resume_claim_status"] == "unverified_best_effort_handoff"
    assert get_in(opencode, ["state_fidelity_verification", "required"]) == true

    assert "inspect the harness session store/export for preserved tool results and hidden state" in get_in(
             opencode,
             ["state_fidelity_verification", "steps"]
           )

    assert "native_tool_results" in opencode["missing_fidelity"]
    assert opencode["capabilities"]["native_session_import"]

    pi = Enum.find(adapters, &(&1["id"] == "pi"))
    assert pi["fidelity"] == "session_import_best_effort"
    assert pi["capabilities"]["native_tool_results"]
    assert pi["resume_claim_status"] == "unverified_best_effort_handoff"
    assert "workspace_snapshot" in pi["missing_fidelity"]
    refute "native_tool_results" in pi["missing_fidelity"]

    claude = Enum.find(adapters, &(&1["id"] == "claude"))
    assert claude["fidelity"] == "prompt_handoff"
    refute claude["capabilities"]["native_session_import"]
  end

  test "opencode export preserves trace evidence without claiming equivalent hidden agent state" do
    session_id = recorded_session_id!()

    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "opencode")

    assert export["artifact_format"] == "opencode_session_json"
    assert export["adapter"]["fidelity"] == "session_import_best_effort"
    assert export["adapter"]["equivalent_agent_resume"] == false
    assert export["adapter"]["resume_claim_status"] == "unverified_best_effort_handoff"
    assert get_in(export, ["adapter", "state_fidelity_verification", "required"]) == true
    assert [import_command, run_command] = export["commands"]
    assert import_command =~ "opencode import 'wardwright-"
    assert run_command =~ "--fork"

    artifact = export["artifact"]
    assert artifact["info"]["id"] =~ "ses_ww"
    assert artifact["info"]["version"] == "1.15.4"
    assert length(artifact["messages"]) == 2
    assert get_in(artifact, ["messages", Access.at(0), "info", "summary"]) == %{"diffs" => []}

    refute get_in(artifact, ["messages", Access.at(1), "parts", Access.at(0)])
           |> Map.has_key?("snapshot")

    trace_text =
      artifact["messages"]
      |> List.last()
      |> Map.fetch!("parts")
      |> Enum.find(&(&1["type"] == "text"))
      |> Map.fetch!("text")

    assert trace_text =~ "tool.call"
    assert trace_text =~ "edit_file"
    assert trace_text =~ "read_before_edit_violation"
    assert export["fidelity_notice"] =~ "best-effort"

    assert Enum.any?(
             export["warnings"],
             &String.contains?(&1, "State fidelity verification is still required")
           )

    assert get_in(export, ["state_fidelity_probe", "schema"]) ==
             "wardwright.harness_state_fidelity_probe.v0"

    assert get_in(export, ["state_fidelity_probe", "adapter_id"]) == "opencode"
    assert get_in(export, ["state_fidelity_probe", "event_count"]) > 0
    assert get_in(export, ["state_fidelity_probe", "tool_result_count"]) > 0
    assert get_in(export, ["state_fidelity_probe", "trace_fingerprint"]) =~ ~r/^[0-9a-f]{64}$/

    assert Enum.any?(
             get_in(export, ["state_fidelity_probe", "tool_result_fingerprints"]),
             &(&1["tool_name"] == "edit_file" and &1["fingerprint"] =~ ~r/^[0-9a-f]{64}$/)
           )
  end

  test "opencode export can be saved as a human-usable import artifact" do
    session_id = recorded_session_id!()

    export_dir =
      Path.join(
        System.tmp_dir!(),
        "wardwright-harness-export-#{System.unique_integer([:positive])}"
      )

    assert {:ok, export} =
             AgentHarnessAdapters.write_export(session_id, "opencode", %{
               "export_dir" => export_dir
             })

    assert [path, probe_path] = export["saved_files"]

    assert Path.basename(path) ==
             "wardwright-#{Base.url_encode64(session_id, padding: false)}.opencode.json"

    assert Path.basename(probe_path) == "wardwright-state-fidelity-probe.json"
    assert hd(export["commands"]) == "opencode import '#{path}'"

    saved = JSON.decode!(File.read!(path))
    assert saved["info"]["id"] == export["artifact"]["info"]["id"]
    assert get_in(saved, ["messages", Access.at(0), "info", "summary"]) == %{"diffs" => []}
    assert JSON.decode!(File.read!(probe_path)) == export["state_fidelity_probe"]
    assert private_mode?(path, 0o600)
    assert private_mode?(probe_path, 0o600)
    assert private_mode?(Path.dirname(path), 0o700)

    File.rm_rf!(export_dir)
  end

  test "pi export writes a native session jsonl with tool result evidence" do
    session_id = recorded_session_id!()

    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "pi")

    assert export["artifact_format"] == "pi_session_jsonl"
    assert export["adapter"]["fidelity"] == "session_import_best_effort"
    assert export["adapter"]["equivalent_agent_resume"] == false
    assert export["adapter"]["capabilities"]["native_tool_results"] == true
    assert hd(export["commands"]) =~ "npx --yes @earendil-works/pi-coding-agent@0.75.5 --session"

    lines =
      export["artifact"]["content"]
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert %{"cwd" => _cwd, "type" => "session", "version" => 3} = hd(lines)
    assert Enum.any?(lines, &(&1["type"] == "session_info"))

    tool_result =
      Enum.find(lines, fn
        %{"message" => %{"role" => "toolResult", "toolName" => "edit_file"}, "type" => "message"} ->
          true

        _entry ->
          false
      end)

    assert get_in(tool_result, ["message", "toolName"]) == "edit_file"
    assert get_in(tool_result, ["message", "details", "fingerprint"]) =~ ~r/^[0-9a-f]{64}$/
    assert get_in(tool_result, ["message", "details", "cursor"]) =~ session_id
  end

  test "pi export can be saved as a resumable session file" do
    session_id = recorded_session_id!()

    export_dir =
      Path.join(
        System.tmp_dir!(),
        "wardwright-harness-export-#{System.unique_integer([:positive])}"
      )

    assert {:ok, export} =
             AgentHarnessAdapters.write_export(session_id, "pi", %{"export_dir" => export_dir})

    assert [session_path, probe_path] = export["saved_files"]

    assert Path.basename(session_path) ==
             "wardwright-#{Base.url_encode64(session_id, padding: false)}.pi.jsonl"

    assert Path.basename(probe_path) == "wardwright-state-fidelity-probe.json"
    assert hd(export["commands"]) =~ "--session '#{session_path}'"
    assert File.read!(session_path) =~ ~s("role":"toolResult")
    assert private_mode?(session_path, 0o600)
    assert private_mode?(probe_path, 0o600)

    File.rm_rf!(export_dir)
  end

  test "oh-my-pi export includes pi session, TTSR rule, and verification extension" do
    session_id = recorded_session_id!()

    export_dir =
      Path.join(
        System.tmp_dir!(),
        "wardwright-harness-export-#{System.unique_integer([:positive])}"
      )

    assert {:ok, export} =
             AgentHarnessAdapters.write_export(session_id, "oh-my-pi", %{
               "export_dir" => export_dir
             })

    assert [session_path, rule_path, extension_path, probe_path] = export["saved_files"]
    assert Path.basename(session_path) =~ ".pi.jsonl"
    assert Path.basename(rule_path) == "wardwright-read-before-edit.md"
    assert Path.basename(extension_path) == "wardwright-state-fidelity.ts"
    assert Path.basename(probe_path) == "wardwright-state-fidelity-probe.json"
    assert hd(export["commands"]) =~ ".omp/rules"
    assert Enum.at(export["commands"], 1) =~ "--session"
    assert File.read!(rule_path) =~ "interruptMode: \"always\""
    assert File.read!(rule_path) =~ ~S|- "."|
    assert File.read!(rule_path) =~ ~S|- "tool:edit_file(*)"|
    assert File.read!(extension_path) =~ "wardwright_verify_state_fidelity"
    assert File.read!(extension_path) =~ "Error verifying Wardwright fidelity"
    assert private_mode?(session_path, 0o600)
    assert private_mode?(rule_path, 0o600)
    assert private_mode?(extension_path, 0o600)

    File.rm_rf!(export_dir)
  end

  test "oh-my-pi commands use oh-my-pi when omp is unavailable" do
    session_id = recorded_session_id!()
    original_path = System.get_env("PATH") || ""
    bin_dir = Path.join(System.tmp_dir!(), "wardwright-oh-my-pi-bin-#{System.unique_integer([:positive])}")

    File.mkdir_p!(bin_dir)
    fake_oh_my_pi = Path.join(bin_dir, "oh-my-pi")
    File.write!(fake_oh_my_pi, "#!/bin/sh\nexit 0\n")
    File.chmod!(fake_oh_my_pi, 0o755)
    System.put_env("PATH", bin_dir)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      File.rm_rf(bin_dir)
    end)

    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "oh-my-pi")

    assert Enum.at(export["commands"], 1) =~ "oh-my-pi --session"
    assert Enum.at(export["commands"], 2) =~ "oh-my-pi --fork"
    refute Enum.any?(export["commands"], &String.contains?(&1, "omp --session"))
  end

  test "opencode plugin export keeps import best-effort and adds plugin hook scaffold" do
    session_id = recorded_session_id!()

    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "opencode-plugin")

    assert export["artifact_format"] == "opencode_plugin_bundle"
    assert export["adapter"]["fidelity"] == "session_import_best_effort"
    assert export["adapter"]["equivalent_agent_resume"] == false
    assert [session, plugin] = export["artifact"]["files"]
    assert session["path"] =~ ".opencode.json"
    assert plugin["path"] == "wardwright-state-fidelity.ts"
    assert plugin["content"] =~ "experimental.session.compacting"
    assert hd(export["commands"]) =~ ".opencode/plugins"
  end

  test "state fidelity verification compares probe evidence without claiming equivalent resume" do
    session_id = recorded_session_id!()
    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "opencode")
    probe = export["state_fidelity_probe"]

    assert verification =
             AgentHarnessAdapters.verify_state_fidelity(probe, %{
               "read_before_edit_cursor_identified" => true,
               "tool_result_fingerprints" => probe["tool_result_fingerprints"],
               "trace_fingerprint" => probe["trace_fingerprint"]
             })

    assert verification["schema"] == "wardwright.harness_state_fidelity_verification.v0"
    assert verification["passed"] == true
    assert verification["status"] == "probe_matched"
    assert verification["equivalent_agent_resume_claim_allowed"] == false

    failed =
      AgentHarnessAdapters.verify_state_fidelity(probe, %{
        "read_before_edit_cursor_identified" => false,
        "tool_result_fingerprints" => [],
        "trace_fingerprint" => "not-the-exported-trace"
      })

    assert failed["passed"] == false
    assert failed["status"] == "probe_mismatch"

    assert Enum.any?(
             failed["checks"],
             &(&1["name"] == "tool_result_fingerprints" and &1["missing"] != [])
           )

    assert Enum.any?(
             failed["checks"],
             &(&1["name"] == "read_before_edit_cursor_identified" and &1["passed"] == false)
           )

    [first_fingerprint | _rest] = probe["tool_result_fingerprints"]

    duplicate_probe =
      Map.put(probe, "tool_result_fingerprints", [first_fingerprint, first_fingerprint])

    duplicate_failed =
      AgentHarnessAdapters.verify_state_fidelity(duplicate_probe, %{
        "read_before_edit_cursor_identified" => true,
        "tool_result_fingerprints" => [first_fingerprint],
        "trace_fingerprint" => probe["trace_fingerprint"]
      })

    assert duplicate_failed["passed"] == false

    assert Enum.any?(
             duplicate_failed["checks"],
             &(&1["name"] == "tool_result_fingerprints" and length(&1["missing"]) == 1)
           )
  end

  test "prompt handoff exports save private files and show path-aware commands" do
    session_id = recorded_session_id!()

    export_dir =
      Path.join(
        System.tmp_dir!(),
        "wardwright-harness-export-#{System.unique_integer([:positive])}"
      )

    assert {:ok, export} =
             AgentHarnessAdapters.write_export(session_id, "claude", %{"export_dir" => export_dir})

    assert [trace_path, prompt_path, probe_path] = export["saved_files"]
    assert Path.basename(trace_path) == "wardwright-trace.md"
    assert Path.basename(prompt_path) == "wardwright-handoff-prompt.md"
    assert Path.basename(probe_path) == "wardwright-state-fidelity-probe.json"
    assert hd(export["commands"]) =~ prompt_path
    assert hd(export["commands"]) =~ "claude --print"
    assert File.read!(prompt_path) =~ "best-effort handoff"
    assert private_mode?(trace_path, 0o600)
    assert private_mode?(prompt_path, 0o600)
    assert private_mode?(probe_path, 0o600)
    assert private_mode?(Path.dirname(prompt_path), 0o700)

    File.rm_rf!(export_dir)
  end

  test "exports do not silently truncate long tool evidence" do
    session_id = long_payload_session_id!()

    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "opencode")

    trace_text =
      export["artifact"]["messages"]
      |> List.last()
      |> Map.fetch!("parts")
      |> Enum.find(&(&1["type"] == "text"))
      |> Map.fetch!("text")

    assert trace_text =~ String.duplicate("x", 1_200)
  end

  test "claude and codex exports are prompt handoffs, not fake native imports" do
    session_id = recorded_session_id!()

    for adapter_id <- ["claude", "codex"] do
      assert {:ok, export} = AgentHarnessAdapters.export(session_id, adapter_id)

      assert export["artifact_format"] == "prompt_handoff"
      assert export["adapter"]["fidelity"] == "prompt_handoff"
      assert export["adapter"]["equivalent_agent_resume"] == false
      assert get_in(export, ["artifact", "prompt"]) =~ "best-effort handoff"
      refute export["adapter"]["capabilities"]["native_session_import"]
    end
  end

  test "public API exposes adapters and session export behind protected access" do
    session_id = recorded_session_id!()

    list_conn = call(:get, "/v1/policy-authoring/harness-adapters")
    assert list_conn.status == 200
    assert Enum.any?(JSON.decode!(list_conn.resp_body)["data"], &(&1["id"] == "opencode"))

    export_conn =
      call(:post, "/v1/policy-authoring/harness-adapters/opencode/export", %{
        "session_id" => session_id
      })

    assert export_conn.status == 200

    assert get_in(JSON.decode!(export_conn.resp_body), ["export", "artifact_format"]) ==
             "opencode_session_json"

    bad_conn =
      call(:post, "/v1/policy-authoring/harness-adapters/not-real/export", %{
        "session_id" => session_id
      })

    assert bad_conn.status == 400

    assert get_in(JSON.decode!(bad_conn.resp_body), ["error", "code"]) ==
             "invalid_harness_adapter_export"

    blank_session_conn =
      call(:post, "/v1/policy-authoring/harness-adapters/opencode/export", %{
        "session_id" => "   "
      })

    assert blank_session_conn.status == 400

    assert get_in(JSON.decode!(blank_session_conn.resp_body), ["error", "message"]) ==
             "session_id must be a non-empty string"
  end

  test "public API verifies exported state fidelity probes behind protected access" do
    session_id = recorded_session_id!()
    assert {:ok, export} = AgentHarnessAdapters.export(session_id, "opencode")
    probe = export["state_fidelity_probe"]

    conn =
      call(:post, "/v1/policy-authoring/harness-adapters/state-fidelity/verify", %{
        "observed" => %{
          "read_before_edit_cursor_identified" => true,
          "tool_result_fingerprints" => probe["tool_result_fingerprints"],
          "trace_fingerprint" => probe["trace_fingerprint"]
        },
        "probe" => probe
      })

    assert conn.status == 200
    assert get_in(JSON.decode!(conn.resp_body), ["verification", "passed"]) == true

    bad_conn =
      call(:post, "/v1/policy-authoring/harness-adapters/state-fidelity/verify", %{
        "observed" => %{},
        "probe" => "not-a-probe"
      })

    assert bad_conn.status == 400

    assert get_in(JSON.decode!(bad_conn.resp_body), ["error", "message"]) ==
             "probe must be a JSON object"
  end

  defp recorded_session_id! do
    scenario = %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "debugger_example_id" => "read-before-edit",
      "expected" => %{"failure_class" => "read_before_edit_violation"},
      "model_id" => "counterfactual-harness-test",
      "task" => "Enable the feature flag from settings.json.",
      "tools" => [
        %{"name" => "list_files"},
        %{"name" => "read_file"},
        %{"name" => "edit_file"},
        %{"name" => "run_tests"}
      ],
      "workspace" => %{
        "app.txt" => "feature_enabled=false",
        "settings.json" => ~s({"feature_enabled":false})
      }
    }

    assert {:ok, outcome} = WardwrightWeb.CounterfactualReplay.run_recorded_session(scenario)
    outcome["session_id"]
  end

  defp long_payload_session_id! do
    session_id = "long_payload_#{System.unique_integer([:positive])}"
    store_dir = Application.fetch_env!(:wardwright, :counterfactual_transcript_store_dir)
    session_dir = Path.join(store_dir, Base.url_encode64(session_id, padding: false))
    File.mkdir_p!(session_dir)

    event = %{
      "cursor" => "#{session_id}:1",
      "schema" => "wardwright.counterfactual_replay.v0",
      "sequence" => 1,
      "session_id" => session_id,
      "tool" => %{
        "args" => %{},
        "name" => "read_file",
        "result" => %{"content" => String.duplicate("x", 1_200)}
      },
      "type" => "tool.result"
    }

    File.write!(Path.join(session_dir, "events.jsonl"), JSON.encode!(event) <> "\n")
    session_id
  end

  defp private_mode?(path, expected) do
    {:ok, stat} = File.stat(path)
    (stat.mode &&& 0o777) == expected
  end

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)
end
