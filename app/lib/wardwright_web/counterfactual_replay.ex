defmodule WardwrightWeb.CounterfactualReplay do
  @moduledoc """
  Deterministic counterfactual replay runtime for debugger acceptance tests.

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
         "concurrent_writers" => true,
         "durable" => true,
         "serialized_global_writer" => false
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
      "failure" => %{"class" => "read_before_edit_violation"},
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

  def continue(fork_session_id, _opts) when is_binary(fork_session_id) do
    with {:ok, metadata} <- read_json(fork_session_id, @metadata_file) do
      scenario = metadata["scenario"] || %{}
      events = fork_continuation_events(scenario, fork_session_id)
      :ok = append_events(fork_session_id, events)

      outcome = %{
        "artifacts" => %{"settings.json" => ~s({"feature_enabled": true})},
        "failure" => %{"class" => ""},
        "session_id" => fork_session_id,
        "status" => "passed",
        "tests" => %{"status" => "passed"}
      }

      :ok = write_json(fork_session_id, @outcome_file, outcome)
      {:ok, outcome}
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

    body =
      %{
        "messages" => [%{"content" => scenario["task"] || "Run the counterfactual scenario.", "role" => "user"}],
        "metadata" => %{"run_id" => session_id, "session_id" => session_id},
        "model" => model_id
      }
      |> Jason.encode!()

    conn =
      :post
      |> conn("/v1/chat/completions", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-wardwright-agent-id", "counterfactual-acceptance")
      |> Wardwright.Router.call(Wardwright.Router.init([]))

    case get_resp_header(conn, "x-wardwright-receipt-id") do
      [receipt_id | _] -> {:ok, receipt_id}
      _ -> {:error, "gateway call did not produce a receipt"}
    end
  end

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

  defp fork_event(fork_session_id, source_session_id, cursor, opts) do
    event(fork_session_id, 100, "session.forked", %{
      "fork_cursor" => cursor,
      "policy_overlay" => opts["policy_overlay"] || %{},
      "source_session_id" => source_session_id
    })
  end

  defp fork_continuation_events(scenario, session_id) do
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

  defp append_events(session_id, events) do
    path = Path.join(session_dir(session_id), @event_file)
    File.mkdir_p!(Path.dirname(path))

    payload =
      events
      |> Enum.map_join(&(Jason.encode!(&1) <> "\n"))

    File.write!(path, payload, [:append])
    File.chmod(path, 0o600)
    :ok
  end

  defp read_events(session_id) do
    path = Path.join(session_dir(session_id), @event_file)

    case File.read(path) do
      {:ok, content} ->
        events =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        {:ok, events}

      {:error, :enoent} ->
        {:error, "unknown transcript session #{inspect(session_id)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp write_json(session_id, file, value) do
    path = Path.join(session_dir(session_id), file)
    tmp_path = "#{path}.#{System.unique_integer([:positive])}.tmp"
    File.mkdir_p!(Path.dirname(path))
    File.write!(tmp_path, Jason.encode!(value))
    File.chmod(tmp_path, 0o600)
    File.rename!(tmp_path, path)
    :ok
  end

  defp read_json(session_id, file) do
    path = Path.join(session_dir(session_id), file)

    with {:ok, content} <- File.read(path),
         {:ok, value} when is_map(value) <- Jason.decode(content) do
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
end
