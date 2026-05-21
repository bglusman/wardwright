defmodule WardwrightWeb.CounterfactualReplay do
  @moduledoc """
  Counterfactual replay runtime for debugger acceptance tests.

  This module intentionally starts with a scripted runner. It exercises the
  Wardwright gateway and receipt path, then records a replayable transcript that
  can be forked and continued without adding live-model drift to the default
  contract.
  """

  import Plug.Conn
  import Plug.Test

  @schema "wardwright.counterfactual_replay.v0"
  @event_file "events.jsonl"
  @metadata_file "metadata.json"
  @outcome_file "outcome.json"

  def transcript_store_health do
    dir = store_dir()
    write_health = ensure_store_dir(dir)

    {:ok,
     %{
       "capabilities" => %{
         "concurrent_sessions" => true,
         "concurrent_writers" => false,
         "durable" => true,
         "serialized_global_writer" => false,
         "serialized_session_writer" => true,
         "writer_coordination" => "beam_per_session"
       },
       "contract_version" => @schema,
       "default_enabled" => false,
       "kind" => "append_only_files",
       "path" => dir,
       "read_health" => read_health(dir),
       "write_health" => write_health
     }}
  end

  def run_recorded_session(scenario) when is_map(scenario) do
    session_id = session_id("session")
    model_id = scenario["model_id"] || "counterfactual-read-before-edit"
    version = scenario["model_version"] || "acceptance-v0"
    :ok = prepare_session(session_id, scenario, %{"role" => "original", "source_session_id" => session_id})

    {:ok, receipt_id} = call_gateway(scenario, model_id, version, session_id)
    events = original_events(scenario, model_id, version, session_id, receipt_id)
    :ok = append_events(session_id, events)

    outcome = %{
      "failure" => %{"class" => original_failure_class(scenario)},
      "gateway" => %{"path" => "/v1/chat/completions", "receipt_ids" => [receipt_id]},
      "recording_enabled" => true,
      "session_id" => session_id,
      "status" => "failed"
    }

    :ok = write_json(session_id, @outcome_file, outcome)
    {:ok, outcome}
  end

  def run_recorded_session(_scenario), do: {:error, "scenario must be a JSON object"}

  def transcript(session_id) when is_binary(session_id) do
    with {:ok, events} <- read_events(session_id),
         {:ok, storage} <- transcript_store_health() do
      {:ok,
       %{
         "events" => events,
         "recording_scope" => :wardwright@counterfactual_contract.recording_scope("full_session", true, length(events)),
         "session_id" => session_id,
         "storage" => %{"kind" => storage["kind"], "path" => storage["path"]}
       }}
    end
  end

  def transcript(_session_id), do: {:error, "session_id is required"}

  def record_gateway_receipt(receipt) when is_map(receipt) do
    safely_record_gateway_receipt(fn -> do_record_gateway_receipt(receipt) end)
  end

  def record_gateway_receipt(_receipt), do: {:error, "receipt must be a JSON object"}

  defp do_record_gateway_receipt(receipt) do
    with {:full_session, true} <- {:full_session, full_session_receipt?(receipt)},
         {:session_id, session_id} when is_binary(session_id) and session_id != "" <-
           {:session_id, receipt_session_id(receipt)},
         {:owner, true} <- {:owner, gateway_session_owner?(session_id)} do
      with_session_write_lock(session_id, fn ->
        :ok = prepare_gateway_session(session_id, receipt)

        with {:ok, existing_events} <- read_events(session_id),
             false <- receipt_already_recorded?(existing_events, receipt),
             :ok <-
               append_events_unlocked(session_id, gateway_receipt_events(session_id, receipt, length(existing_events))),
             :ok <- write_json(session_id, @outcome_file, gateway_outcome(session_id, receipt)) do
          {:ok, %{"recorded" => true, "session_id" => session_id}}
        else
          true -> {:ok, %{"reason" => "receipt already recorded", "recorded" => false, "session_id" => session_id}}
          {:error, reason} -> {:error, reason}
        end
      end)
    else
      {:full_session, false} -> {:ok, %{"reason" => "receipt is not full-session VCR", "recorded" => false}}
      {:session_id, _} -> {:ok, %{"reason" => "receipt has no session_id or run_id", "recorded" => false}}
      {:owner, false} -> {:ok, %{"reason" => "session is owned by another transcript recorder", "recorded" => false}}
    end
  end

  defp safely_record_gateway_receipt(fun) do
    fun.()
  rescue
    error ->
      {:error, "counterfactual transcript recording failed: #{Exception.message(error)}"}
  catch
    kind, reason ->
      {:error, "counterfactual transcript recording failed: #{kind}: #{inspect(reason)}"}
  end

  def replay_until(session_id, cursor) when is_binary(session_id) and is_binary(cursor) do
    with {:ok, events} <- read_events(session_id),
         {:ok, replayed_events} <- events_before_cursor(events, cursor) do
      {:ok,
       %{
         "events" => replayed_events,
         "next_event_cursor" => cursor,
         "provider_called" => false,
         "session_id" => session_id
       }}
    end
  end

  def replay_until(_session_id, _cursor), do: {:error, "session_id and cursor are required"}

  def fork(opts) when is_map(opts) do
    source_session_id = opts["source_session_id"]
    cursor = opts["fork_cursor"]

    with true <- is_binary(source_session_id) and is_binary(cursor),
         {:ok, metadata} <- read_json(source_session_id, @metadata_file),
         {:ok, source_events} <- read_events(source_session_id),
         {:ok, replayed_events} <- events_before_cursor(source_events, cursor) do
      fork_session_id = session_id("fork")
      scenario = metadata["scenario"] || %{}

      :ok =
        prepare_session(fork_session_id, scenario, %{
          "fork_cursor" => cursor,
          "policy_overlay" => opts["policy_overlay"] || %{},
          "role" => "fork",
          "source_session_id" => source_session_id
        })

      :ok =
        append_events(
          fork_session_id,
          replayed_events ++ [fork_event(fork_session_id, source_session_id, cursor, opts)]
        )

      {:ok, %{"fork_session_id" => fork_session_id, "source_session_id" => source_session_id}}
    else
      false -> {:error, "source_session_id and fork_cursor are required"}
      {:error, reason} -> {:error, reason}
    end
  end

  def fork(_opts), do: {:error, "fork options must be a JSON object"}

  def continue(fork_session_id, opts) when is_binary(fork_session_id) and is_map(opts) do
    with {:ok, metadata} <- read_json(fork_session_id, @metadata_file) do
      scenario = metadata["scenario"] || %{}

      case opts["runner"] || "scripted_agent" do
        runner when runner in ["scripted_agent", "deterministic"] ->
          continue_scripted(fork_session_id, scenario)

        runner when runner in ["wardwright_model", "live_model"] ->
          continue_with_wardwright_model(fork_session_id, scenario, metadata, opts)

        runner ->
          {:error, "unsupported continuation runner #{inspect(runner)}"}
      end
    end
  end

  def continue(_fork_session_id, _opts), do: {:error, "fork_session_id is required"}

  def compare(original_session_id, fork_session_id)
      when is_binary(original_session_id) and is_binary(fork_session_id) do
    with {:ok, original} <- read_json(original_session_id, @outcome_file),
         {:ok, forked} <- read_json(fork_session_id, @outcome_file),
         {:ok, fork_metadata} <- read_json(fork_session_id, @metadata_file) do
      original_failure = get_in(original, ["failure", "class"]) || ""
      fork_failure = get_in(forked, ["failure", "class"]) || ""

      {:ok,
       %{
         "accepted" =>
           :wardwright@counterfactual_contract.accepted_outcome(
             original["status"],
             forked["status"],
             original_failure,
             fork_failure
           ),
         "fork" => %{"failure_class" => fork_failure, "status" => forked["status"]},
         "original" => %{"failure_class" => original_failure, "status" => original["status"]},
         "policy_delta" => %{
           "applied_rule_ids" => applied_rule_ids(fork_metadata["policy_overlay"])
         }
       }}
    end
  end

  def compare(_original_session_id, _fork_session_id), do: {:error, "session ids are required"}

  defp call_gateway(scenario, model_id, version, session_id) do
    config = gateway_config(model_id, version)
    {:ok, _config} = Wardwright.put_model_config(config)

    request = %{
      "messages" => [%{"content" => scenario["task"] || "Run the counterfactual scenario.", "role" => "user"}],
      "metadata" => %{"run_id" => session_id, "session_id" => session_id},
      "model" => model_id
    }

    with {:ok, receipt_id, _body, _receipt} <-
           call_gateway_request(request, "counterfactual-acceptance", nil) do
      {:ok, receipt_id}
    end
  end

  defp call_gateway_request(request, agent_id, model_api_key) do
    body = JSON.encode!(request)

    conn =
      :post
      |> conn("/v1/chat/completions", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-wardwright-agent-id", agent_id)
      |> put_model_api_key(model_api_key)
      |> Wardwright.Router.call(Wardwright.Router.init([]))

    body = decode_response_body(conn.resp_body)

    case {conn.status, get_resp_header(conn, "x-wardwright-receipt-id")} do
      {status, [receipt_id | _]} when status in 200..299 ->
        {:ok, receipt_id, body, Wardwright.ReceiptStore.get(receipt_id)}

      {status, [receipt_id | _]} ->
        {:error, "live continuation gateway call failed with HTTP #{status} for receipt #{receipt_id}"}

      {status, _} ->
        {:error, "live continuation gateway call failed with HTTP #{status}: #{gateway_error_message(body)}"}
    end
  end

  defp put_model_api_key(conn, nil), do: conn
  defp put_model_api_key(conn, ""), do: conn
  defp put_model_api_key(conn, api_key), do: put_req_header(conn, "x-wardwright-model-api-key", api_key)

  defp decode_response_body(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"raw" => body}
    end
  end

  defp gateway_error_message(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp gateway_error_message(%{"raw" => raw}) when is_binary(raw), do: raw
  defp gateway_error_message(body), do: inspect(body)

  defp continue_scripted(fork_session_id, scenario) do
    events = fork_continuation_events(scenario, fork_session_id)
    :ok = append_events(fork_session_id, events)

    outcome = %{
      "artifacts" => fork_artifacts(scenario),
      "failure" => %{"class" => ""},
      "runner" => %{"kind" => "scripted_agent"},
      "session_id" => fork_session_id,
      "status" => "passed",
      "tests" => %{"status" => "passed"}
    }

    :ok = write_json(fork_session_id, @outcome_file, outcome)
    {:ok, outcome}
  end

  defp continue_with_wardwright_model(fork_session_id, scenario, metadata, opts) do
    model_id = opts["model_id"] |> blank_to_nil()
    api_key = opts["model_api_key"] |> blank_to_nil()

    with {:model_id, model_id} when is_binary(model_id) <- {:model_id, model_id},
         {:ok, _config} <- Wardwright.model_config(model_id),
         {:ok, fork_events} <- read_events(fork_session_id),
         request = live_continuation_request(model_id, fork_session_id, scenario, metadata, fork_events),
         {:ok, receipt_id, body, receipt} <-
           call_gateway_request(request, "counterfactual-live-continuation", api_key) do
      content = assistant_content(body)
      called_provider = provider_called?(receipt)
      {status, failure_class, tests_status} = classify_live_continuation(content, receipt)

      events =
        live_continuation_events(
          fork_session_id,
          model_id,
          request,
          receipt_id,
          receipt,
          content,
          status
        )

      :ok = append_events(fork_session_id, events)

      outcome = %{
        "failure" => %{"class" => failure_class},
        "gateway" => %{"path" => "/v1/chat/completions", "receipt_ids" => [receipt_id]},
        "provider_called" => called_provider,
        "response" => %{"content" => content},
        "runner" => %{"kind" => "wardwright_model", "model_id" => model_id},
        "session_id" => fork_session_id,
        "status" => status,
        "tests" => %{"status" => tests_status}
      }

      :ok = write_json(fork_session_id, @outcome_file, outcome)
      {:ok, outcome}
    else
      {:model_id, _} -> {:error, "live continuation requires a Wardwright model id"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp live_continuation_request(model_id, fork_session_id, scenario, metadata, fork_events) do
    %{
      "messages" => [
        %{
          "content" =>
            "You are continuing a forked Wardwright agent session from recorded transcript evidence. " <>
              "Use the policy overlay as the new control contract and explain the next safe action.",
          "role" => "system"
        },
        %{
          "content" =>
            JSON.encode!(%{
              "fork_cursor" => metadata["fork_cursor"],
              "policy_overlay" => metadata["policy_overlay"],
              "task" => scenario["task"],
              "transcript_before_continuation" => transcript_summary(fork_events),
              "workspace_files" => workspace_files(scenario)
            }),
          "role" => "user"
        }
      ],
      "metadata" => %{
        "counterfactual_continuation" => true,
        "run_id" => fork_session_id,
        "session_id" => fork_session_id
      },
      "model" => model_id
    }
  end

  defp live_continuation_events(fork_session_id, model_id, request, receipt_id, receipt, content, status) do
    [
      event(fork_session_id, 101, "model.continuation.request", %{
        "message_count" => length(request["messages"] || []),
        "model_id" => model_id,
        "runner" => "wardwright_model"
      }),
      event(fork_session_id, 102, "receipt.finalized", %{
        "gateway" => %{"path" => "/v1/chat/completions"},
        "provider_called" => provider_called?(receipt),
        "receipt_id" => receipt_id,
        "status" => get_in(receipt || %{}, ["final", "status"]) || "unknown"
      }),
      event(fork_session_id, 103, "model.continuation.response", %{
        "content_preview" => content_preview(content),
        "status" => status
      })
    ]
  end

  defp gateway_receipt_events(session_id, receipt, existing_event_count) do
    base_sequence = existing_event_count + 1

    [
      gateway_event(session_id, base_sequence, 1, "gateway.request", receipt, %{
        "gateway" => %{"path" => "/v1/chat/completions", "surface" => "openai_compatible_gateway"},
        "message_count" => get_in(receipt, ["request", "message_count"]),
        "model_id" => receipt["model_id"],
        "recording_enabled" => true
      }),
      gateway_event(session_id, base_sequence + 1, 2, "route.selected", receipt, %{
        "estimated_prompt_tokens" => get_in(receipt, ["decision", "estimated_prompt_tokens"]),
        "route_id" => get_in(receipt, ["decision", "route_id"]),
        "route_type" => get_in(receipt, ["decision", "route_type"]),
        "selected_model" => get_in(receipt, ["decision", "selected_model"]),
        "selected_provider" => get_in(receipt, ["decision", "selected_provider"])
      }),
      gateway_event(session_id, base_sequence + 2, 3, "model.response", receipt, %{
        "content_preview" => content_preview(get_in(receipt, ["vcr", "full_session", "response", "content"])),
        "fork_point" => true,
        "provider_called" => get_in(receipt, ["vcr", "provider", "called_provider"]),
        "status" => get_in(receipt, ["final", "status"])
      }),
      gateway_event(session_id, base_sequence + 3, 4, "receipt.finalized", receipt, %{
        "gateway" => %{"path" => "/v1/chat/completions"},
        "provider_called" => get_in(receipt, ["vcr", "provider", "called_provider"]),
        "receipt_id" => receipt["receipt_id"],
        "status" => get_in(receipt, ["final", "status"])
      })
    ]
    |> Enum.map(&drop_nil_values/1)
  end

  defp gateway_event(session_id, sequence, receipt_event_index, type, receipt, fields) do
    receipt_id = receipt["receipt_id"] || "receipt"

    fields
    |> Map.merge(%{
      "cursor" => "#{session_id}:#{receipt_id}:#{receipt_event_index}",
      "receipt_id" => receipt_id,
      "schema" => @schema,
      "sequence" => sequence,
      "session_id" => session_id,
      "type" => type
    })
  end

  defp assistant_content(%{"choices" => [choice | _]}) when is_map(choice) do
    case get_in(choice, ["message", "content"]) do
      content when is_binary(content) and content != "" -> content
      _ -> choice |> get_in(["message"]) |> JSON.encode!()
    end
  end

  defp assistant_content(_body), do: ""

  defp provider_called?(%{"attempts" => [attempt | _]}) when is_map(attempt), do: attempt["called_provider"] == true

  defp provider_called?(_receipt), do: false

  defp classify_live_continuation(content, receipt) do
    final_status = get_in(receipt || %{}, ["final", "status"]) || "unknown"
    normalized = content |> to_string() |> String.downcase()

    cond do
      final_status not in ["completed", "completed_after_guard"] ->
        {"failed", "provider_or_policy_failure", "failed"}

      String.contains?(normalized, "feature_enabled") and String.contains?(normalized, "pass") ->
        {"passed", "", "passed"}

      String.contains?(normalized, "confidence") and String.contains?(normalized, "answer") ->
        {"passed", "", "passed"}

      true ->
        {"continued_live", "unverified_live_continuation", "unknown"}
    end
  end

  defp content_preview(content) when is_binary(content), do: String.slice(content, 0, 240)

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp workspace_files(%{"workspace" => workspace}) when is_map(workspace), do: Map.keys(workspace)
  defp workspace_files(_scenario), do: []

  defp transcript_summary(events) when is_list(events) do
    Enum.map(events, fn event ->
      %{
        "cursor" => event["cursor"],
        "sequence" => event["sequence"],
        "tool" => get_in(event, ["tool", "name"]),
        "type" => event["type"]
      }
      |> put_if_present("args", get_in(event, ["tool", "args"]))
      |> put_if_present("result", compact_tool_result(get_in(event, ["tool", "result"])))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end

  defp compact_tool_result(result) when is_map(result) do
    result
    |> Map.take(["failure_class", "files", "status"])
    |> case do
      empty when empty == %{} -> nil
      compact -> compact
    end
  end

  defp compact_tool_result(_result), do: nil

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp gateway_config(model_id, version) do
    Wardwright.default_config()
    |> Map.put("model_id", model_id)
    |> Map.put("version", version)
    |> Map.put("vcr", %{"mode" => "full_session"})
    |> Map.put("targets", [
      %{
        "canned_outputs" => ["counterfactual transcript recorded"],
        "context_window" => 256,
        "model" => Wardwright.local_model(),
        "provider_kind" => "canned_sequence"
      },
      %{
        "canned_outputs" => ["counterfactual transcript recorded"],
        "context_window" => Wardwright.managed_context_window(),
        "model" => Wardwright.managed_model(),
        "provider_kind" => "canned_sequence"
      }
    ])
  end

  defp original_events(scenario, model_id, version, session_id, receipt_id) do
    case scenario["debugger_example_id"] do
      "output-contract" -> output_contract_original_events(scenario, model_id, version, session_id, receipt_id)
      _ -> read_before_edit_original_events(scenario, model_id, version, session_id, receipt_id)
    end
  end

  defp read_before_edit_original_events(scenario, model_id, version, session_id, receipt_id) do
    [
      event(session_id, 1, "session.started", %{"model_id" => model_id, "version" => version}),
      event(session_id, 2, "gateway.request", %{
        "gateway" => scenario["entrypoint"] || %{"path" => "/v1/chat/completions"},
        "recording_enabled" => true
      }),
      event(session_id, 3, "tool.call", tool_call("list_files", %{})),
      event(
        session_id,
        4,
        "tool.result",
        tool_result("list_files", %{"files" => Map.keys(scenario["workspace"] || %{})})
      ),
      event(
        session_id,
        5,
        "tool.call",
        tool_call("edit_file", %{"patch" => "feature_enabled=true", "path" => "app.txt"})
        |> Map.put("fork_point", true)
      ),
      event(session_id, 6, "tool.result", tool_result("edit_file", %{"status" => "applied"})),
      event(session_id, 7, "tool.call", tool_call("run_tests", %{})),
      event(
        session_id,
        8,
        "tool.result",
        tool_result("run_tests", %{"failure_class" => "read_before_edit_violation", "status" => "failed"})
      ),
      event(session_id, 9, "receipt.finalized", %{
        "gateway" => %{"path" => "/v1/chat/completions"},
        "receipt_id" => receipt_id,
        "status" => "failed"
      })
    ]
  end

  defp output_contract_original_events(_scenario, model_id, version, session_id, receipt_id) do
    [
      event(session_id, 1, "session.started", %{"model_id" => model_id, "version" => version}),
      event(session_id, 2, "gateway.request", %{
        "gateway" => %{"path" => "/v1/chat/completions", "surface" => "openai_compatible_gateway"},
        "recording_enabled" => true
      }),
      event(session_id, 3, "model.response", %{
        "content_preview" => "Probably no results, but try again later.",
        "fork_point" => true,
        "status" => "completed"
      }),
      event(session_id, 4, "policy.decision", %{
        "failure_class" => "output_contract_violation",
        "rule_id" => "result-json-contract",
        "status" => "failed"
      }),
      event(session_id, 5, "receipt.finalized", %{
        "gateway" => %{"path" => "/v1/chat/completions"},
        "receipt_id" => receipt_id,
        "status" => "failed"
      })
    ]
  end

  defp fork_event(fork_session_id, source_session_id, cursor, opts) do
    event(fork_session_id, 100, "session.forked", %{
      "fork_cursor" => cursor,
      "policy_overlay" => opts["policy_overlay"] || %{},
      "source_session_id" => source_session_id
    })
  end

  defp fork_continuation_events(scenario, session_id) do
    case scenario["debugger_example_id"] do
      "output-contract" -> output_contract_fork_continuation_events(session_id)
      _ -> read_before_edit_fork_continuation_events(scenario, session_id)
    end
  end

  defp read_before_edit_fork_continuation_events(scenario, session_id) do
    [
      event(session_id, 101, "tool.call", tool_call("read_file", %{"path" => "settings.json"})),
      event(
        session_id,
        102,
        "tool.result",
        tool_result("read_file", %{"content" => get_in(scenario, ["workspace", "settings.json"])})
      ),
      event(
        session_id,
        103,
        "tool.call",
        tool_call("edit_file", %{"patch" => ~s({"feature_enabled": true}), "path" => "settings.json"})
      ),
      event(session_id, 104, "tool.result", tool_result("edit_file", %{"status" => "applied"})),
      event(session_id, 105, "tool.call", tool_call("run_tests", %{})),
      event(session_id, 106, "tool.result", tool_result("run_tests", %{"status" => "passed"}))
    ]
  end

  defp output_contract_fork_continuation_events(session_id) do
    [
      event(session_id, 101, "model.continuation.response", %{
        "content_preview" => ~s({"answer":"No matching records were found.","confidence":0.91}),
        "status" => "passed"
      }),
      event(session_id, 102, "policy.decision", %{
        "rule_id" => "result-json-contract",
        "status" => "passed"
      })
    ]
  end

  defp original_failure_class(scenario) do
    get_in(scenario, ["expected", "failure_class"]) || "read_before_edit_violation"
  end

  defp fork_artifacts(%{"debugger_example_id" => "output-contract"}) do
    %{"response.json" => ~s({"answer":"No matching records were found.","confidence":0.91})}
  end

  defp fork_artifacts(_scenario), do: %{"settings.json" => ~s({"feature_enabled": true})}

  defp tool_call(name, args), do: %{"tool" => %{"args" => args, "name" => name}}
  defp tool_result(name, result), do: %{"tool" => %{"name" => name, "result" => result}}

  defp event(session_id, sequence, type, fields) do
    fields
    |> Map.merge(%{
      "cursor" => cursor(session_id, sequence),
      "schema" => @schema,
      "sequence" => sequence,
      "session_id" => session_id,
      "type" => type
    })
  end

  defp applied_rule_ids(%{"id" => id}) when is_binary(id) and id != "", do: [id]
  defp applied_rule_ids(_overlay), do: []

  defp events_before_cursor(events, cursor) do
    case Enum.split_while(events, &(&1["cursor"] != cursor)) do
      {_before, []} -> {:error, "unknown transcript cursor #{inspect(cursor)}"}
      {before, [_cursor_event | _after]} -> {:ok, before}
    end
  end

  defp prepare_session(session_id, scenario, metadata) do
    dir = session_dir(session_id)
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, @event_file), "")
    write_json(session_id, @metadata_file, Map.put(metadata, "scenario", scenario))
  end

  defp prepare_gateway_session(session_id, receipt) do
    dir = session_dir(session_id)
    events_path = Path.join(dir, @event_file)

    if !File.exists?(events_path) do
      File.mkdir_p!(dir)
      File.write!(events_path, "")
      File.chmod(events_path, 0o600)

      write_json(session_id, @metadata_file, %{
        "role" => "gateway",
        "scenario" => gateway_scenario(receipt),
        "source_session_id" => session_id
      })
    end

    :ok
  end

  defp append_events(session_id, events) do
    with_session_write_lock(session_id, fn -> append_events_unlocked(session_id, events) end)
  end

  defp append_events_unlocked(session_id, events) do
    path = Path.join(session_dir(session_id), @event_file)
    File.mkdir_p!(Path.dirname(path))

    payload =
      events
      |> Enum.map_join(&(JSON.encode!(&1) <> "\n"))

    File.write!(path, payload, [:append])
    File.chmod(path, 0o600)
    :ok
  end

  defp with_session_write_lock(session_id, fun) do
    :global.trans({{__MODULE__, :session_write, safe_id(session_id)}, self()}, fun)
  end

  defp read_events(session_id) do
    path = Path.join(session_dir(session_id), @event_file)

    case File.read(path) do
      {:ok, content} ->
        {:ok, decode_event_lines(content, session_id)}

      {:error, :enoent} ->
        {:error, "unknown transcript session #{inspect(session_id)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp decode_event_lines(content, session_id) do
    content
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_number}, events ->
      case JSON.decode(line) do
        {:ok, event} when is_map(event) ->
          [event | events]

        {:ok, _not_event} ->
          warn_malformed_event_line(session_id, line_number, "decoded JSON was not an object")
          events

        {:error, reason} ->
          warn_malformed_event_line(
            session_id,
            line_number,
            Wardwright.Json.decode_error_message(reason)
          )

          events
      end
    end)
    |> Enum.reverse()
  end

  defp warn_malformed_event_line(session_id, line_number, reason) do
    require Logger

    Logger.warning(
      "Skipping malformed counterfactual transcript event session=#{inspect(session_id)} line=#{line_number} reason=#{reason}"
    )
  end

  defp write_json(session_id, file, value) do
    path = Path.join(session_dir(session_id), file)
    tmp_path = "#{path}.#{System.unique_integer([:positive])}.tmp"
    File.mkdir_p!(Path.dirname(path))
    File.write!(tmp_path, JSON.encode!(value))
    File.chmod(tmp_path, 0o600)
    File.rename!(tmp_path, path)
    :ok
  end

  defp read_json(session_id, file) do
    path = Path.join(session_dir(session_id), file)

    with {:ok, content} <- File.read(path),
         {:ok, value} when is_map(value) <- JSON.decode(content) do
      {:ok, value}
    else
      {:error, :enoent} -> {:error, "unknown transcript session #{inspect(session_id)}"}
      {:error, reason} -> {:error, inspect(reason)}
      _ -> {:error, "invalid transcript metadata"}
    end
  end

  defp cursor(session_id, sequence), do: "#{session_id}:#{sequence}"
  defp session_id(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  defp session_dir(session_id), do: Path.join(store_dir(), safe_id(session_id))

  defp store_dir do
    case Application.get_env(:wardwright, :counterfactual_transcript_store_dir, :default) do
      nil -> default_store_dir()
      :default -> default_store_dir()
      path -> path
    end
  end

  defp default_store_dir do
    System.get_env("WARDWRIGHT_TRANSCRIPT_STORE_DIR") || Wardwright.Paths.data_path("transcripts")
  end

  defp ensure_store_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> "ok"
      {:error, reason} -> inspect(reason)
    end
  end

  defp read_health(dir) do
    case File.stat(dir) do
      {:ok, %File.Stat{type: :directory}} -> "ok"
      {:ok, _stat} -> "not_directory"
      {:error, reason} -> inspect(reason)
    end
  end

  defp safe_id(id), do: Base.url_encode64(id, padding: false)

  defp full_session_receipt?(receipt) do
    get_in(receipt, ["vcr", "mode"]) == "full_session" and
      is_map(get_in(receipt, ["vcr", "full_session"]))
  end

  defp gateway_session_owner?(session_id) do
    case read_json(session_id, @metadata_file) do
      {:ok, %{"role" => "gateway"}} -> true
      {:ok, %{"role" => role}} when is_binary(role) -> false
      {:ok, _metadata} -> true
      {:error, _reason} -> true
    end
  end

  defp receipt_session_id(receipt) do
    get_in(receipt, ["caller", "session_id", "value"]) ||
      get_in(receipt, ["caller", "run_id", "value"]) ||
      receipt["run_id"] ||
      get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "session_id"]) ||
      get_in(receipt, ["vcr", "full_session", "request", "body", "metadata", "run_id"])
  end

  defp receipt_already_recorded?(events, receipt) do
    receipt_id = receipt["receipt_id"]

    Enum.any?(events, fn event ->
      is_binary(receipt_id) and event["receipt_id"] == receipt_id
    end)
  end

  defp gateway_outcome(session_id, receipt) do
    status = get_in(receipt, ["final", "status"]) || "unknown"

    %{
      "failure" => %{"class" => gateway_failure_class(status)},
      "gateway" => %{"path" => "/v1/chat/completions", "receipt_ids" => [receipt["receipt_id"]]},
      "provider_called" => get_in(receipt, ["vcr", "provider", "called_provider"]) == true,
      "recording_enabled" => true,
      "session_id" => session_id,
      "status" => gateway_outcome_status(status)
    }
  end

  defp gateway_failure_class("completed"), do: ""
  defp gateway_failure_class("completed_after_guard"), do: ""
  defp gateway_failure_class(status) when is_binary(status), do: status
  defp gateway_failure_class(_status), do: "unknown"

  defp gateway_outcome_status("completed"), do: "passed"
  defp gateway_outcome_status("completed_after_guard"), do: "passed"
  defp gateway_outcome_status(_status), do: "failed"

  defp gateway_scenario(receipt) do
    request = get_in(receipt, ["vcr", "full_session", "request", "body"]) || %{}

    %{
      "contract_version" => @schema,
      "debugger_example_id" => "gateway-full-session",
      "entrypoint" => %{
        "path" => "/v1/chat/completions",
        "surface" => "openai_compatible_gateway"
      },
      "model_id" => receipt["model_id"],
      "model_version" => receipt["model_version"],
      "task" => request_task(request),
      "vcr" => %{"mode" => "full_session"},
      "workspace" => %{}
    }
  end

  defp request_task(%{"messages" => messages}) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"content" => content, "role" => "user"} when is_binary(content) -> content
      _ -> nil
    end)
    |> case do
      nil -> "Continue the recorded Wardwright session."
      content -> String.slice(content, 0, 500)
    end
  end

  defp request_task(_request), do: "Continue the recorded Wardwright session."

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
