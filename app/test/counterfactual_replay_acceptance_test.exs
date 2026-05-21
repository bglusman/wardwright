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
    assert storage["capabilities"]["concurrent_sessions"] == true
    assert storage["capabilities"]["concurrent_writers"] == false
    assert storage["capabilities"]["serialized_global_writer"] == false
    assert storage["capabilities"]["serialized_session_writer"] == true
    assert storage["capabilities"]["writer_coordination"] == "beam_per_session"
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

    put_live_continuation_model_config()

    assert {:ok, live_fork} =
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

    assert {:ok, live_fixed} =
             apply(@replay_module, :continue, [
               live_fork["fork_session_id"],
               %{"model_id" => "counterfactual-live-acceptance", "runner" => "wardwright_model"}
             ])

    assert live_fixed["status"] == "passed"
    assert live_fixed["provider_called"] == true
    assert get_in(live_fixed, ["runner", "kind"]) == "wardwright_model"
    assert [live_receipt_id | _] = get_in(live_fixed, ["gateway", "receipt_ids"])
    assert is_binary(live_receipt_id)
    live_receipt = Wardwright.ReceiptStore.get(live_receipt_id)

    live_messages = get_in(live_receipt, ["vcr", "full_session", "request", "body", "messages"])

    assert Enum.any?(live_messages, fn message ->
             message["role"] == "user" and
               message["content"] =~ "session_trace_before_continuation" and
               message["content"] =~ "edit_file"
           end)

    assert Enum.any?(live_messages, fn message ->
             case message do
               %{
                 "role" => "assistant",
                 "tool_calls" => [
                   %{"function" => %{"arguments" => "{}", "name" => "list_files"}, "id" => call_id}
                 ]
               } ->
                 is_binary(call_id)

               _ ->
                 false
             end
           end)

    assert Enum.any?(live_messages, fn message ->
             message["role"] == "tool" and
               message["name"] == "list_files" and
               message["content"] =~ "settings.json" and
               is_binary(message["tool_call_id"])
           end)

    assert live_receipt
           |> get_in(["vcr", "full_session", "request", "body", "tools"])
           |> Enum.any?(fn tool ->
             get_in(tool, ["function", "name"]) == "read_file"
           end)

    assert {:ok, live_transcript} = apply(@replay_module, :transcript, [live_fork["fork_session_id"]])

    assert Enum.any?(live_transcript["events"], fn event ->
             event["type"] == "model.continuation.response" and
               event["status"] == "passed"
           end)
  end

  test "replays a malformed output session without assuming a tool-call failure" do
    scenario = output_contract_scenario()

    assert {:ok, original} = apply(@replay_module, :run_recorded_session, [scenario])
    assert original["status"] == "failed"
    assert get_in(original, ["failure", "class"]) == "output_contract_violation"

    session_id = original["session_id"]
    assert {:ok, transcript} = apply(@replay_module, :transcript, [session_id])

    response_event =
      Enum.find(transcript["events"], fn event ->
        event["type"] == "model.response" and event["fork_point"] == true
      end)

    assert response_event, "output-contract transcript should fork before response validation"
    refute Enum.any?(transcript["events"], &(get_in(&1, ["tool", "name"]) == "edit_file"))

    fork_cursor = response_event["cursor"]
    assert {:ok, replay} = apply(@replay_module, :replay_until, [session_id, fork_cursor])
    assert replay["provider_called"] == false

    assert {:ok, fork} =
             apply(@replay_module, :fork, [
               %{
                 "fork_cursor" => fork_cursor,
                 "policy_overlay" => %{
                   "id" => "result-json-contract",
                   "output_contract" => %{
                     "format" => "json_object",
                     "required_keys" => ["answer", "confidence"]
                   },
                   "phase" => "response.validation"
                 },
                 "source_session_id" => session_id
               }
             ])

    assert {:ok, fixed} =
             apply(@replay_module, :continue, [
               fork["fork_session_id"],
               %{"runner" => "scripted_agent", "script_id" => "valid-json-response"}
             ])

    assert fixed["status"] == "passed"
    assert get_in(fixed, ["artifacts", "response.json"]) =~ "confidence"

    assert {:ok, comparison} = apply(@replay_module, :compare, [session_id, fork["fork_session_id"]])
    assert comparison["accepted"] == true
    assert comparison["policy_delta"]["applied_rule_ids"] == ["result-json-contract"]
  end

  test "live continuation groups consecutive tool calls into valid native chat history" do
    store_dir = Path.join(System.tmp_dir!(), "wardwright-native-trace-#{System.unique_integer([:positive])}")
    original_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)
    fork_session_id = "native-history-fork-#{System.unique_integer([:positive])}"

    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, store_dir)

    on_exit(fn ->
      restore_env(:counterfactual_transcript_store_dir, original_store_dir)
      File.rm_rf!(store_dir)
    end)

    put_live_continuation_model_config()

    write_transcript_file!(store_dir, fork_session_id, "metadata.json", %{
      "fork_cursor" => "#{fork_session_id}:edit",
      "policy_overlay" => %{"id" => "read-before-edit"},
      "role" => "fork",
      "scenario" => read_before_edit_scenario(),
      "source_session_id" => "source-session"
    })

    write_events_file!(store_dir, fork_session_id, [
      event(fork_session_id, 1, "tool.call", tool_call("list_files", %{})),
      event(fork_session_id, 2, "tool.call", tool_call("read_file", %{"path" => "settings.json"})),
      event(fork_session_id, 3, "tool.result", tool_result("list_files", %{"files" => ["settings.json"]})),
      event(fork_session_id, 4, "tool.result", tool_result("read_file", %{"status" => "ok"}))
    ])

    assert {:ok, fixed} =
             apply(@replay_module, :continue, [
               fork_session_id,
               %{"model_id" => "counterfactual-live-acceptance", "runner" => "wardwright_model"}
             ])

    assert [receipt_id | _] = get_in(fixed, ["gateway", "receipt_ids"])
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    messages = get_in(receipt, ["vcr", "full_session", "request", "body", "messages"])

    assert Enum.any?(messages, fn message ->
             case message do
               %{"role" => "assistant", "tool_calls" => [list_call, read_call]} ->
                 get_in(list_call, ["function", "name"]) == "list_files" and
                   get_in(read_call, ["function", "name"]) == "read_file"

               _ ->
                 false
             end
           end)

    assert Enum.count(messages, &(&1["role"] == "tool")) == 2
  end

  test "malformed transcript event lines are skipped instead of invalidating the session" do
    store_dir = Path.join(System.tmp_dir!(), "wardwright-corrupt-transcript-#{System.unique_integer([:positive])}")
    original_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)

    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, store_dir)

    on_exit(fn ->
      restore_env(:counterfactual_transcript_store_dir, original_store_dir)
      File.rm_rf!(store_dir)
    end)

    assert {:ok, original} = apply(@replay_module, :run_recorded_session, [read_before_edit_scenario()])
    session_id = original["session_id"]

    assert {:ok, transcript_before} = apply(@replay_module, :transcript, [session_id])
    event_count = length(transcript_before["events"])

    events_path =
      Path.join([
        store_dir,
        Base.url_encode64(session_id, padding: false),
        "events.jsonl"
      ])

    File.write!(events_path, ~s({"type":\n), [:append])

    assert {:ok, transcript_after} = apply(@replay_module, :transcript, [session_id])
    assert length(transcript_after["events"]) == event_count
    assert Enum.all?(transcript_after["events"], &is_map/1)
  end

  test "gateway receipt recording serializes writers per transcript session" do
    store_dir = Path.join(System.tmp_dir!(), "wardwright-concurrent-transcript-#{System.unique_integer([:positive])}")
    original_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)
    session_id = "concurrent-gateway-session-#{System.unique_integer([:positive])}"
    receipt_count = 16

    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, store_dir)

    on_exit(fn ->
      restore_env(:counterfactual_transcript_store_dir, original_store_dir)
      File.rm_rf!(store_dir)
    end)

    results =
      1..receipt_count
      |> Task.async_stream(
        fn receipt_index ->
          apply(@replay_module, :record_gateway_receipt, [gateway_receipt(session_id, receipt_index)])
        end,
        max_concurrency: 8,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn
             {:ok, {:ok, %{"recorded" => true, "session_id" => ^session_id}}} -> true
             _other -> false
           end)

    assert {:ok, transcript} = apply(@replay_module, :transcript, [session_id])
    assert length(transcript["events"]) == receipt_count * 4
    assert Enum.map(transcript["events"], & &1["sequence"]) == Enum.to_list(1..(receipt_count * 4))

    finalized_receipt_ids =
      transcript["events"]
      |> Enum.filter(&(&1["type"] == "receipt.finalized"))
      |> Enum.map(& &1["receipt_id"])
      |> Enum.sort()

    assert finalized_receipt_ids ==
             1..receipt_count
             |> Enum.map(&"receipt-concurrent-#{&1}")
             |> Enum.sort()
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

  defp output_contract_scenario do
    %{
      "contract_version" => :wardwright@counterfactual_contract.api_contract_version(),
      "debugger_example_id" => "output-contract",
      "entrypoint" => %{
        "path" => "/v1/chat/completions",
        "surface" => "openai_compatible_gateway"
      },
      "expected" => %{
        "failure_class" => "output_contract_violation",
        "fork_status" => "passed",
        "original_status" => "failed"
      },
      "fork_runner" => %{"script_id" => "valid-json-response"},
      "model_id" => "counterfactual-output-contract",
      "model_version" => "acceptance-v0",
      "task" => "Answer the search request as JSON with answer and confidence fields.",
      "vcr" => %{"mode" => "full_session"},
      "workspace" => %{}
    }
  end

  defp put_live_continuation_model_config do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "counterfactual-live-acceptance")
      |> Map.put("version", "acceptance-live-v0")
      |> Map.put("vcr", %{"mode" => "full_session"})
      |> Map.put("requires_api_key", false)
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})
      |> Map.put("targets", [
        %{
          "canned_outputs" => [
            "Read settings.json before editing; feature_enabled is true and tests passed."
          ],
          "context_window" => 8192,
          "model" => "canned/counterfactual-live-acceptance",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("dispatchers", [
        %{
          "id" => "dispatcher.counterfactual-live-acceptance",
          "models" => ["canned/counterfactual-live-acceptance"]
        }
      ])
      |> Map.put("route_root", "dispatcher.counterfactual-live-acceptance")

    {:ok, _config} = Wardwright.put_model_config(config)
  end

  defp gateway_receipt(session_id, receipt_index) do
    receipt_id = "receipt-concurrent-#{receipt_index}"

    %{
      "caller" => %{
        "run_id" => %{"source" => "metadata", "value" => "run-#{session_id}"},
        "session_id" => %{"source" => "metadata", "value" => session_id}
      },
      "decision" => %{
        "estimated_prompt_tokens" => 12,
        "route_id" => "dispatcher.concurrent",
        "route_type" => "dispatcher",
        "selected_model" => "canned/concurrent",
        "selected_provider" => "canned_sequence"
      },
      "final" => %{"status" => "completed"},
      "model_id" => "counterfactual-concurrent",
      "model_version" => "acceptance-v0",
      "receipt_id" => receipt_id,
      "request" => %{"message_count" => 1},
      "vcr" => %{
        "full_session" => %{
          "request" => %{
            "body" => %{
              "messages" => [
                %{"content" => "record concurrent receipt #{receipt_index}", "role" => "user"}
              ],
              "metadata" => %{"run_id" => "run-#{session_id}", "session_id" => session_id},
              "model" => "counterfactual-concurrent"
            }
          },
          "response" => %{"content" => "Concurrent response #{receipt_index}"}
        },
        "mode" => "full_session",
        "provider" => %{"called_provider" => true}
      }
    }
  end

  defp write_transcript_file!(store_dir, session_id, file_name, value) do
    session_dir = Path.join(store_dir, Base.url_encode64(session_id, padding: false))
    File.mkdir_p!(session_dir)
    File.write!(Path.join(session_dir, file_name), JSON.encode!(value))
  end

  defp write_events_file!(store_dir, session_id, events) do
    session_dir = Path.join(store_dir, Base.url_encode64(session_id, padding: false))
    File.mkdir_p!(session_dir)
    File.write!(Path.join(session_dir, "events.jsonl"), Enum.map_join(events, "\n", &JSON.encode!/1) <> "\n")
  end

  defp event(session_id, sequence, type, fields) do
    Map.merge(fields, %{
      "cursor" => "#{session_id}:#{sequence}",
      "schema" => :wardwright@counterfactual_contract.api_contract_version(),
      "sequence" => sequence,
      "session_id" => session_id,
      "type" => type
    })
  end

  defp tool_call(name, args), do: %{"tool" => %{"args" => args, "name" => name}}
  defp tool_result(name, result), do: %{"tool" => %{"name" => name, "result" => result}}

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)
end
