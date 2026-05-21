defmodule WardwrightWeb.CounterfactualReplayAcceptanceTest do
  use Wardwright.RouterCase

  @moduletag :counterfactual_replay_acceptance

  @replay_module WardwrightWeb.CounterfactualReplay
  @required_runtime_api [
    transcript_store_health: 0,
    run_recorded_session: 1,
    transcript: 1,
    replay_until: 2,
    fork: 1,
    continue: 2,
    compare: 2
  ]

  test "replays a failed tool-use session, forks before the bad edit, applies policy, and continues live" do
    assert :wardwright@counterfactual_contract.api_contract_version() ==
             "wardwright.counterfactual_replay.v0"

    assert :wardwright@counterfactual_contract.recording_scope("full_session", true, 4) ==
             "replayable_session"

    assert missing_runtime_api() == [],
           """
           Counterfactual replay runtime API is not implemented yet.

           The acceptance contract expects Wardwright to:
           - record an entire multi-turn agent session, not only one request receipt
           - expose the ordered transcript with event cursors
           - replay up to a cursor without calling a provider
           - fork from that cursor with a policy overlay
           - continue the fork with a live or deterministic agent/model runner
           - compare original and forked outcomes with behavior-level evidence

           Missing runtime API:
           #{Enum.map_join(missing_runtime_api(), "\n", &"           - #{&1}")}
           """

    scenario = read_before_edit_scenario()

    assert {:ok, storage} = apply(@replay_module, :transcript_store_health, [])
    assert storage["kind"] == "append_only_files"
    assert storage["capabilities"]["durable"] == true
    assert storage["capabilities"]["concurrent_writers"] == true
    assert storage["capabilities"]["serialized_global_writer"] == false
    assert storage["default_enabled"] == false
    assert is_binary(storage["path"])
    assert storage["read_health"] == "ok"
    assert storage["write_health"] == "ok"

    assert {:ok, original} = apply(@replay_module, :run_recorded_session, [scenario])
    assert original["status"] == "failed"
    assert get_in(original, ["failure", "class"]) == "read_before_edit_violation"
    assert original["recording_enabled"] == true
    assert get_in(original, ["gateway", "path"]) == "/v1/chat/completions"

    assert [receipt_id | _] = get_in(original, ["gateway", "receipt_ids"])
    assert is_binary(receipt_id)

    session_id = original["session_id"]
    assert is_binary(session_id)

    assert {:ok, transcript} = apply(@replay_module, :transcript, [session_id])
    assert transcript["recording_scope"] == "replayable_session"
    assert transcript["storage"]["kind"] == "append_only_files"
    assert length(transcript["events"]) >= 6

    assert Enum.any?(transcript["events"], fn event ->
             event["type"] == "receipt.finalized" and
               event["receipt_id"] == receipt_id and
               get_in(event, ["gateway", "path"]) == "/v1/chat/completions"
           end)

    bad_edit =
      Enum.find(transcript["events"], fn event ->
        event["type"] == "tool.call" and
          get_in(event, ["tool", "name"]) == "edit_file" and
          get_in(event, ["tool", "args", "path"]) == "app.txt"
      end)

    assert bad_edit, "original transcript should include the unsafe edit that caused the failure"

    fork_cursor = bad_edit["cursor"]
    assert is_binary(fork_cursor)

    assert {:ok, replay} = apply(@replay_module, :replay_until, [session_id, fork_cursor])
    assert replay["provider_called"] == false
    assert replay["next_event_cursor"] == fork_cursor
    assert {:error, unknown_cursor_message} = apply(@replay_module, :replay_until, [session_id, "missing-cursor"])
    assert unknown_cursor_message =~ "unknown transcript cursor"

    assert {:ok, fork} =
             apply(@replay_module, :fork, [
               %{
                 "fork_cursor" => fork_cursor,
                 "policy_overlay" => %{
                   "allowed_tools_until_read" => ["list_files", "read_file"],
                   "id" => "read-before-edit",
                   "phase" => "tool.planning",
                   "requires_prior_read_for" => ["edit_file"]
                 },
                 "source_session_id" => session_id
               }
             ])

    assert fork["source_session_id"] == session_id
    assert fork["fork_session_id"] != session_id

    assert {:ok, fixed} =
             apply(@replay_module, :continue, [
               fork["fork_session_id"],
               %{"runner" => "scripted_agent", "script_id" => "read-settings-then-edit"}
             ])

    assert fixed["status"] == "passed"
    assert get_in(fixed, ["failure", "class"]) in [nil, ""]
    assert get_in(fixed, ["artifacts", "settings.json"]) =~ ~s("feature_enabled": true)
    assert get_in(fixed, ["tests", "status"]) == "passed"

    assert {:ok, comparison} = apply(@replay_module, :compare, [session_id, fork["fork_session_id"]])

    assert comparison["accepted"] == true
    assert comparison["original"]["status"] == "failed"
    assert comparison["fork"]["status"] == "passed"
    assert comparison["policy_delta"]["applied_rule_ids"] == ["read-before-edit"]

    assert :wardwright@counterfactual_contract.accepted_outcome(
             comparison["original"]["status"],
             comparison["fork"]["status"],
             get_in(comparison, ["original", "failure_class"]) || "",
             get_in(comparison, ["fork", "failure_class"]) || ""
           )
  end

  defp missing_runtime_api do
    @required_runtime_api
    |> Enum.reject(fn {function, arity} ->
      Code.ensure_loaded?(@replay_module) and function_exported?(@replay_module, function, arity)
    end)
    |> Enum.map(fn {function, arity} -> "#{inspect(@replay_module)}.#{function}/#{arity}" end)
  end

  defp read_before_edit_scenario do
    %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "entrypoint" => %{
        "path" => "/v1/chat/completions",
        "surface" => "openai_compatible_gateway"
      },
      "expected" => %{
        "failure_class" => "read_before_edit_violation",
        "fork_status" => "passed",
        "original_status" => "failed"
      },
      "fork_runner" => %{
        "kind" => "scripted_agent",
        "steps" => [
          %{"args" => %{}, "tool" => "list_files"},
          %{"args" => %{"path" => "settings.json"}, "tool" => "read_file"},
          %{"args" => %{"patch" => ~s({"feature_enabled": true}), "path" => "settings.json"}, "tool" => "edit_file"},
          %{"args" => %{}, "tool" => "run_tests"}
        ]
      },
      "model_id" => "counterfactual-read-before-edit",
      "model_version" => "acceptance-v0",
      "original_runner" => %{
        "kind" => "scripted_agent",
        "steps" => [
          %{"args" => %{}, "tool" => "list_files"},
          %{"args" => %{"patch" => "feature_enabled=true", "path" => "app.txt"}, "tool" => "edit_file"},
          %{"args" => %{}, "tool" => "run_tests"}
        ]
      },
      "task" => "Enable the feature flag. Read the relevant file before editing.",
      "tools" => [
        %{"mutates" => false, "name" => "list_files"},
        %{"mutates" => false, "name" => "read_file"},
        %{"mutates" => true, "name" => "edit_file"},
        %{"mutates" => false, "name" => "run_tests"}
      ],
      "vcr" => %{"mode" => "full_session"},
      "workspace" => %{
        "README.md" => "Change the feature flag described in settings.json.",
        "app.txt" => "Tempting wrong file; editing this should not satisfy the task.",
        "settings.json" => ~s({"feature_enabled": false})
      }
    }
  end
end
