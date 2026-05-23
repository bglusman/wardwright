defmodule WardwrightWeb.AgentHarnessAdapters do
  @moduledoc """
  Best-effort exports from Wardwright session traces into external agent harnesses.

  The adapter contract is deliberately conservative. A harness can accept a
  trace export without preserving the hidden state that made the original agent
  run behave the way it did.
  """

  @contract_version "wardwright.harness_adapter.v0"
  @opencode_version "1.15.4"
  @pi_package "@earendil-works/pi-coding-agent@0.75.5"

  def list do
    [
      adapter("opencode", "OpenCode", installed?("opencode"), %{
        "model_context_replay" => true,
        "native_session_fork" => true,
        "native_session_import" => true,
        "native_session_resume" => true,
        "native_tool_results" => false,
        "private_agent_state" => false,
        "workspace_snapshot" => false
      }),
      adapter("opencode-plugin", "OpenCode plugin spike", installed?("opencode"), %{
        "model_context_replay" => true,
        "native_session_fork" => true,
        "native_session_import" => true,
        "native_session_resume" => true,
        "native_tool_results" => false,
        "private_agent_state" => false,
        "workspace_snapshot" => false
      }),
      adapter("claude", "Claude Code", installed?("claude"), %{
        "model_context_replay" => true,
        "native_session_fork" => true,
        "native_session_import" => false,
        "native_session_resume" => true,
        "native_tool_results" => false,
        "private_agent_state" => false,
        "workspace_snapshot" => false
      }),
      adapter("codex", "Codex", installed?("codex"), %{
        "model_context_replay" => true,
        "native_session_fork" => true,
        "native_session_import" => false,
        "native_session_resume" => true,
        "native_tool_results" => false,
        "private_agent_state" => false,
        "workspace_snapshot" => false
      }),
      adapter("pi", "Pi", installed?("pi"), %{
        "model_context_replay" => true,
        "native_session_fork" => true,
        "native_session_import" => true,
        "native_session_resume" => true,
        "native_tool_results" => true,
        "private_agent_state" => false,
        "workspace_snapshot" => false
      }),
      adapter("oh-my-pi", "oh-my-pi / omp", installed?("omp") or installed?("oh-my-pi"), %{
        "model_context_replay" => true,
        "native_session_fork" => true,
        "native_session_import" => true,
        "native_session_resume" => true,
        "native_tool_results" => true,
        "private_agent_state" => false,
        "workspace_snapshot" => false
      })
    ]
  end

  def get(adapter_id) when is_binary(adapter_id) do
    Enum.find(list(), &(&1["id"] == adapter_id))
  end

  def get(_adapter_id), do: nil

  def export(session_id, adapter_id, opts \\ %{})

  def export(session_id, adapter_id, opts) when is_binary(session_id) and is_binary(adapter_id) and is_map(opts) do
    with {:adapter, adapter} when is_map(adapter) <- {:adapter, get(adapter_id)},
         {:ok, transcript} <- WardwrightWeb.CounterfactualReplay.transcript(session_id),
         events when is_list(events) and events != [] <- transcript["events"] do
      case adapter_id do
        "opencode" ->
          {:ok, opencode_export(session_id, transcript, events, adapter, opts)}

        "opencode-plugin" ->
          {:ok, opencode_plugin_export(session_id, transcript, events, adapter, opts)}

        "claude" ->
          {:ok, handoff_export(session_id, transcript, events, adapter, opts)}

        "codex" ->
          {:ok, handoff_export(session_id, transcript, events, adapter, opts)}

        "pi" ->
          {:ok, pi_session_export(session_id, transcript, events, adapter, opts)}

        "oh-my-pi" ->
          {:ok, oh_my_pi_export(session_id, transcript, events, adapter, opts)}
      end
    else
      {:adapter, _} -> {:error, "unknown agent harness adapter #{inspect(adapter_id)}"}
      [] -> {:error, "session trace has no events"}
      nil -> {:error, "session trace has no events"}
      {:error, reason} -> {:error, reason}
    end
  end

  def export(_session_id, _adapter_id, _opts), do: {:error, "session_id and adapter_id are required"}

  def write_export(session_id, adapter_id, opts \\ %{})

  def write_export(session_id, adapter_id, opts)
      when is_binary(session_id) and is_binary(adapter_id) and is_map(opts) do
    with {:ok, export} <- export(session_id, adapter_id, opts),
         {:ok, saved_files} <- write_export_files(session_id, adapter_id, export, opts) do
      {:ok,
       export
       |> Map.put("saved_files", saved_files)
       |> Map.put("commands", saved_export_commands(export, saved_files))}
    end
  end

  def write_export(_session_id, _adapter_id, _opts), do: {:error, "session_id and adapter_id are required"}

  def verify_state_fidelity(probe, observed) when is_map(probe) and is_map(observed) do
    observed_fingerprints =
      cond do
        is_list(observed["tool_result_fingerprints"]) ->
          observed["tool_result_fingerprints"]

        is_list(observed["events"]) ->
          observed["events"]
          |> Enum.filter(&tool_result_event?/1)
          |> Enum.map(fn event ->
            %{
              "cursor" => event["cursor"] || "",
              "fingerprint" => stable_fingerprint(event["tool"] || event),
              "tool_name" => get_in(event, ["tool", "name"]) || "unknown"
            }
          end)

        true ->
          []
      end

    expected_fingerprints = probe["tool_result_fingerprints"] || []
    missing = fingerprint_difference(expected_fingerprints, observed_fingerprints)
    unexpected = fingerprint_difference(observed_fingerprints, expected_fingerprints)
    expected_trace_fingerprint = probe["trace_fingerprint"]
    observed_trace_fingerprint = observed["trace_fingerprint"]

    trace_matches =
      is_binary(expected_trace_fingerprint) and
        expected_trace_fingerprint == observed_trace_fingerprint

    tool_results_match = missing == [] and unexpected == []
    read_before_edit_cursor_identified = observed["read_before_edit_cursor_identified"] == true
    passed = trace_matches and tool_results_match and read_before_edit_cursor_identified

    %{
      "adapter_id" => probe["adapter_id"] || observed["adapter_id"],
      "checks" => [
        %{
          "expected" => expected_trace_fingerprint,
          "name" => "trace_fingerprint",
          "observed" => observed_trace_fingerprint,
          "passed" => trace_matches
        },
        %{
          "expected_count" => length(expected_fingerprints),
          "missing" => missing,
          "name" => "tool_result_fingerprints",
          "observed_count" => length(observed_fingerprints),
          "passed" => tool_results_match,
          "unexpected" => unexpected
        },
        %{
          "name" => "read_before_edit_cursor_identified",
          "observed" => observed["read_before_edit_cursor_identified"] == true,
          "passed" => read_before_edit_cursor_identified
        }
      ],
      "equivalent_agent_resume_claim_allowed" => false,
      "passed" => passed,
      "probe_schema" => probe["schema"],
      "schema" => "wardwright.harness_state_fidelity_verification.v0",
      "session_id" => probe["session_id"],
      "status" => if(passed, do: "probe_matched", else: "probe_mismatch")
    }
  end

  def verify_state_fidelity(_probe, _observed), do: {:error, "probe and observed must be JSON objects"}

  defp adapter(id, label, installed, capabilities) do
    native_session_import = capabilities["native_session_import"] == true
    native_session_fork = capabilities["native_session_fork"] == true
    native_session_resume = capabilities["native_session_resume"] == true
    native_tool_results = capabilities["native_tool_results"] == true
    workspace_snapshot = capabilities["workspace_snapshot"] == true
    private_agent_state = capabilities["private_agent_state"] == true

    equivalent_agent_resume =
      :wardwright@harness_adapter.can_claim_equivalent_agent_resume(
        native_session_import,
        native_session_resume,
        native_tool_results,
        workspace_snapshot,
        private_agent_state
      )

    missing_fidelity =
      :wardwright@harness_adapter.missing_fidelity(
        native_session_import,
        native_session_fork,
        native_tool_results,
        workspace_snapshot,
        private_agent_state
      )

    %{
      "capabilities" => capabilities,
      "contract_version" => @contract_version,
      "equivalent_agent_resume" => equivalent_agent_resume,
      "fidelity" =>
        :wardwright@harness_adapter.fidelity_label(
          native_session_import,
          native_session_fork,
          native_tool_results,
          workspace_snapshot,
          private_agent_state
        ),
      "id" => id,
      "installed" => installed,
      "label" => label,
      "missing_fidelity" => missing_fidelity,
      "resume_claim_status" => :wardwright@harness_adapter.resume_claim_status(equivalent_agent_resume),
      "state_fidelity_verification" => state_fidelity_verification(equivalent_agent_resume, missing_fidelity),
      "status" => :wardwright@harness_adapter.adapter_status(installed, native_session_import)
    }
  end

  defp opencode_export(session_id, transcript, events, adapter, opts) do
    export_id = opencode_session_id(session_id)
    now = System.system_time(:millisecond)
    title = opts["title"] || "Wardwright trace #{session_id}"
    cwd = opts["cwd"] || System.get_env("PWD") || File.cwd!()
    user_message_id = opencode_id("msg", session_id, 1)
    assistant_message_id = opencode_id("msg", session_id, 2)

    artifact = %{
      "info" => %{
        "cost" => 0,
        "directory" => cwd,
        "id" => export_id,
        "permission" => [],
        "projectID" => "wardwright-counterfactual",
        "slug" => "wardwright-" <> short_hash(session_id),
        "summary" => %{"additions" => 0, "deletions" => 0, "files" => 0},
        "time" => %{"created" => now, "updated" => now},
        "title" => title,
        "tokens" => %{
          "cache" => %{"read" => 0, "write" => 0},
          "input" => 0,
          "output" => 0,
          "reasoning" => 0
        },
        "version" => @opencode_version
      },
      "messages" => [
        opencode_user_message(export_id, user_message_id, session_id, transcript, events, now),
        opencode_assistant_message(
          export_id,
          assistant_message_id,
          user_message_id,
          session_id,
          events,
          now,
          cwd
        )
      ]
    }

    %{
      "adapter" => adapter,
      "artifact" => artifact,
      "artifact_format" => "opencode_session_json",
      "commands" => [
        "opencode import #{shell_quote(opencode_file_name(session_id))}",
        "opencode run --session #{export_id} --fork \"Continue from the Wardwright trace cursor you want to investigate.\""
      ],
      "fidelity_notice" => fidelity_notice(adapter),
      "session_id" => session_id,
      "state_fidelity_probe" => state_fidelity_probe(session_id, adapter, events),
      "warnings" => adapter_warnings(adapter)
    }
  end

  defp opencode_user_message(export_id, message_id, session_id, transcript, events, now) do
    %{
      "info" => %{
        "agent" => "build",
        "id" => message_id,
        "model" => %{"modelID" => "wardwright-trace", "providerID" => "wardwright"},
        "role" => "user",
        "sessionID" => export_id,
        "summary" => %{"diffs" => []},
        "time" => %{"created" => now}
      },
      "parts" => [
        text_part(
          export_id,
          message_id,
          opencode_id("prt", session_id, 1),
          "Imported Wardwright session trace.\n\n" <>
            "Session: #{session_id}\n" <>
            "Recording scope: #{transcript["recording_scope"] || "unknown"}\n" <>
            "Events: #{length(events)}\n\n" <>
            "Treat this as recorded evidence, not as native OpenCode internal state."
        )
      ]
    }
  end

  defp opencode_assistant_message(export_id, message_id, parent_id, session_id, events, now, cwd) do
    %{
      "info" => %{
        "agent" => "build",
        "cost" => 0,
        "finish" => "stop",
        "id" => message_id,
        "mode" => "build",
        "modelID" => "wardwright-trace",
        "parentID" => parent_id,
        "path" => %{"cwd" => cwd, "root" => cwd},
        "providerID" => "wardwright",
        "role" => "assistant",
        "sessionID" => export_id,
        "time" => %{"completed" => now, "created" => now},
        "tokens" => %{
          "cache" => %{"read" => 0, "write" => 0},
          "input" => 0,
          "output" => 0,
          "reasoning" => 0
        }
      },
      "parts" => [
        %{
          "id" => opencode_id("prt", session_id, 2),
          "messageID" => message_id,
          "sessionID" => export_id,
          "type" => "step-start"
        },
        text_part(
          export_id,
          message_id,
          opencode_id("prt", session_id, 3),
          trace_markdown(events)
        ),
        %{
          "cost" => 0,
          "id" => opencode_id("prt", session_id, 4),
          "messageID" => message_id,
          "reason" => "stop",
          "sessionID" => export_id,
          "tokens" => %{
            "cache" => %{"read" => 0, "write" => 0},
            "input" => 0,
            "output" => 0,
            "reasoning" => 0
          },
          "type" => "step-finish"
        }
      ]
    }
  end

  defp text_part(session_id, message_id, part_id, content) do
    %{
      "id" => part_id,
      "messageID" => message_id,
      "sessionID" => session_id,
      "text" => content,
      "type" => "text"
    }
  end

  defp handoff_export(session_id, transcript, events, adapter, opts) do
    cwd = opts["cwd"] || System.get_env("PWD") || File.cwd!()
    prompt = handoff_prompt(session_id, transcript, events, adapter)

    %{
      "adapter" => adapter,
      "artifact" => %{
        "files" => [
          %{"content" => trace_markdown(events), "path" => "wardwright-trace.md"},
          %{"content" => prompt, "path" => "wardwright-handoff-prompt.md"}
        ],
        "prompt" => prompt
      },
      "artifact_format" => "prompt_handoff",
      "commands" => handoff_commands(adapter["id"], cwd),
      "fidelity_notice" => fidelity_notice(adapter),
      "session_id" => session_id,
      "state_fidelity_probe" => state_fidelity_probe(session_id, adapter, events),
      "warnings" => adapter_warnings(adapter)
    }
  end

  defp pi_session_export(session_id, transcript, events, adapter, opts) do
    cwd = opts["cwd"] || System.get_env("PWD") || File.cwd!()
    title = opts["title"] || "Wardwright trace #{session_id}"
    file_name = pi_file_name(session_id)

    artifact = %{
      "content" => pi_session_jsonl(session_id, transcript, events, cwd, title),
      "file_name" => file_name,
      "session_id" => pi_session_id(session_id)
    }

    %{
      "adapter" => adapter,
      "artifact" => artifact,
      "artifact_format" => "pi_session_jsonl",
      "commands" => [
        "npx --yes #{@pi_package} --session #{shell_quote(file_name)}",
        "npx --yes #{@pi_package} --fork #{shell_quote(file_name)} \"Continue from the Wardwright trace cursor you want to investigate.\""
      ],
      "fidelity_notice" => fidelity_notice(adapter),
      "session_id" => session_id,
      "state_fidelity_probe" => state_fidelity_probe(session_id, adapter, events),
      "warnings" => adapter_warnings(adapter)
    }
  end

  defp oh_my_pi_export(session_id, transcript, events, adapter, opts) do
    cwd = opts["cwd"] || System.get_env("PWD") || File.cwd!()
    title = opts["title"] || "Wardwright trace #{session_id}"
    session_file = pi_file_name(session_id)
    rule_file = "wardwright-read-before-edit.md"
    extension_file = "wardwright-state-fidelity.ts"

    files = [
      %{
        "content" => pi_session_jsonl(session_id, transcript, events, cwd, title),
        "path" => session_file
      },
      %{"content" => oh_my_pi_ttsr_rule(), "path" => rule_file},
      %{"content" => pi_state_fidelity_extension(), "path" => extension_file}
    ]

    %{
      "adapter" => adapter,
      "artifact" => %{"files" => files, "session_file" => session_file},
      "artifact_format" => "oh_my_pi_replay_bundle",
      "commands" => [
        "mkdir -p .omp/rules .omp/extensions && cp #{shell_quote(rule_file)} .omp/rules/wardwright-read-before-edit.md && cp #{shell_quote(extension_file)} .omp/extensions/wardwright-state-fidelity.ts",
        "omp --session #{shell_quote(session_file)}",
        "omp --fork #{shell_quote(session_file)} \"Continue from the Wardwright trace cursor you want to investigate.\""
      ],
      "fidelity_notice" => fidelity_notice(adapter),
      "session_id" => session_id,
      "state_fidelity_probe" => state_fidelity_probe(session_id, adapter, events),
      "warnings" => adapter_warnings(adapter)
    }
  end

  defp opencode_plugin_export(session_id, transcript, events, adapter, opts) do
    opencode = opencode_export(session_id, transcript, events, adapter, opts)
    session_file = opencode_file_name(session_id)
    plugin_file = "wardwright-state-fidelity.ts"

    files = [
      %{"content" => JSON.encode!(opencode["artifact"]), "path" => session_file},
      %{"content" => opencode_state_fidelity_plugin(), "path" => plugin_file}
    ]

    opencode
    |> Map.put("artifact", %{"files" => files, "session_file" => session_file})
    |> Map.put("artifact_format", "opencode_plugin_bundle")
    |> Map.put("commands", [
      "mkdir -p .opencode/plugins && cp #{shell_quote(plugin_file)} .opencode/plugins/wardwright-state-fidelity.ts",
      "opencode import #{shell_quote(session_file)}",
      "opencode run --session #{opencode["artifact"]["info"]["id"]} --fork \"Continue from the Wardwright trace cursor you want to investigate.\""
    ])
  end

  defp handoff_prompt(session_id, transcript, events, adapter) do
    """
    Continue from this Wardwright session trace as a best-effort handoff.

    Adapter: #{adapter["label"]} (#{adapter["id"]})
    Session: #{session_id}
    Recording scope: #{transcript["recording_scope"] || "unknown"}

    Important fidelity limits:
    #{Enum.map_join(adapter_warnings(adapter), "\n", &"- #{&1}")}

    Use the recorded evidence below to decide the next safe action. Do not treat
    the imported trace as native #{adapter["label"]} memory unless the adapter
    explicitly says equivalent_agent_resume=true.

    #{trace_markdown(events)}
    """
  end

  defp handoff_commands("claude", _cwd) do
    [
      "claude --print --input-format text --output-format stream-json < wardwright-handoff-prompt.md",
      "claude --resume <existing-claude-session-id> --fork-session"
    ]
  end

  defp handoff_commands("codex", cwd) do
    [
      "codex exec --cd #{shell_quote(cwd)} --json - < wardwright-handoff-prompt.md",
      "codex fork <existing-codex-session-id> \"Continue from the Wardwright handoff prompt.\""
    ]
  end

  defp handoff_commands("pi", _cwd) do
    [
      "npx --yes #{@pi_package} -p < wardwright-handoff-prompt.md"
    ]
  end

  defp handoff_commands(_adapter_id, _cwd), do: []

  defp write_export_files(session_id, adapter_id, export, opts) do
    root = opts["export_dir"] || Wardwright.Paths.data_path("harness_exports")
    dir = Path.join([root, safe_file_id(session_id), safe_file_id(adapter_id)])

    with :ok <- File.mkdir_p(dir),
         :ok <- chmod_private_dir(dir) do
      case export["artifact_format"] do
        "opencode_session_json" ->
          with {:ok, artifact_paths} <-
                 write_json_artifact(dir, opencode_file_name(session_id), export["artifact"]),
               {:ok, probe_paths} <- write_probe_artifact(dir, export) do
            {:ok, artifact_paths ++ probe_paths}
          end

        "pi_session_jsonl" ->
          with {:ok, artifact_paths} <-
                 write_text_artifact(
                   dir,
                   get_in(export, ["artifact", "file_name"]),
                   get_in(export, ["artifact", "content"])
                 ),
               {:ok, probe_paths} <- write_probe_artifact(dir, export) do
            {:ok, artifact_paths ++ probe_paths}
          end

        "oh_my_pi_replay_bundle" ->
          with {:ok, artifact_paths} <-
                 write_prompt_handoff_files(dir, get_in(export, ["artifact", "files"]) || []),
               {:ok, probe_paths} <- write_probe_artifact(dir, export) do
            {:ok, artifact_paths ++ probe_paths}
          end

        "opencode_plugin_bundle" ->
          with {:ok, artifact_paths} <-
                 write_prompt_handoff_files(dir, get_in(export, ["artifact", "files"]) || []),
               {:ok, probe_paths} <- write_probe_artifact(dir, export) do
            {:ok, artifact_paths ++ probe_paths}
          end

        "prompt_handoff" ->
          with {:ok, artifact_paths} <-
                 write_prompt_handoff_files(dir, get_in(export, ["artifact", "files"]) || []),
               {:ok, probe_paths} <- write_probe_artifact(dir, export) do
            {:ok, artifact_paths ++ probe_paths}
          end

        _format ->
          {:error, "unsupported harness export artifact format"}
      end
    end
  end

  defp write_text_artifact(dir, file_name, content) when is_binary(file_name) and is_binary(content) do
    path = Path.join(dir, Path.basename(file_name))

    with :ok <- write_private_file(path, content) do
      {:ok, [path]}
    end
  end

  defp write_text_artifact(_dir, _file_name, _content), do: {:error, "text artifact is missing"}

  defp write_json_artifact(dir, file_name, artifact) do
    path = Path.join(dir, file_name)

    with :ok <- File.write(path, JSON.encode!(artifact)),
         :ok <- chmod_private_file(path) do
      {:ok, [path]}
    end
  rescue
    _error -> {:error, "could not encode harness export artifact"}
  end

  defp write_probe_artifact(dir, %{"state_fidelity_probe" => probe}) when is_map(probe) do
    write_json_artifact(dir, "wardwright-state-fidelity-probe.json", probe)
  end

  defp write_probe_artifact(_dir, _export), do: {:ok, []}

  defp write_prompt_handoff_files(dir, files) when is_list(files) do
    files
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, paths} ->
      path = Path.join(dir, Path.basename(file["path"] || "wardwright-handoff.txt"))

      case write_private_file(path, file["content"] || "") do
        :ok ->
          {:cont, {:ok, [path | paths]}}

        {:error, reason} ->
          {:halt, {:error, "could not write harness export file: #{:file.format_error(reason)}"}}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      {:error, message} -> {:error, message}
    end
  end

  defp write_prompt_handoff_files(_dir, _files), do: {:error, "prompt handoff artifact files are missing"}

  defp saved_export_commands(%{"adapter" => %{"id" => "opencode"}} = export, [path | _]) when is_binary(path) do
    ["opencode import #{shell_quote(path)}" | Enum.drop(export["commands"] || [], 1)]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "opencode-plugin"}} = export, [session_path, plugin_path | _])
       when is_binary(session_path) and is_binary(plugin_path) do
    [
      "mkdir -p .opencode/plugins && cp #{shell_quote(plugin_path)} .opencode/plugins/wardwright-state-fidelity.ts",
      "opencode import #{shell_quote(session_path)}"
      | Enum.drop(export["commands"] || [], 2)
    ]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "pi"}}, [path | _]) when is_binary(path) do
    [
      "npx --yes #{@pi_package} --session #{shell_quote(path)}",
      "npx --yes #{@pi_package} --fork #{shell_quote(path)} \"Continue from the Wardwright trace cursor you want to investigate.\""
    ]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "oh-my-pi"}}, [session_path, rule_path, extension_path | _])
       when is_binary(session_path) and is_binary(rule_path) and is_binary(extension_path) do
    [
      "mkdir -p .omp/rules .omp/extensions && cp #{shell_quote(rule_path)} .omp/rules/wardwright-read-before-edit.md && cp #{shell_quote(extension_path)} .omp/extensions/wardwright-state-fidelity.ts",
      "omp --session #{shell_quote(session_path)}",
      "omp --fork #{shell_quote(session_path)} \"Continue from the Wardwright trace cursor you want to investigate.\""
    ]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "claude"}}, [_trace_path, prompt_path | _])
       when is_binary(prompt_path) do
    [
      "claude --print --input-format text --output-format stream-json < #{shell_quote(prompt_path)}",
      "claude --resume <existing-claude-session-id> --fork-session"
    ]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "codex"}}, [_trace_path, prompt_path | _])
       when is_binary(prompt_path) do
    [
      "codex exec --json - < #{shell_quote(prompt_path)}",
      "codex fork <existing-codex-session-id> \"Continue from the Wardwright handoff prompt.\""
    ]
  end

  defp saved_export_commands(export, _saved_files), do: export["commands"] || []

  defp trace_markdown(events) do
    events
    |> Enum.map_join("\n\n", fn event ->
      [
        "## #{event["sequence"] || "?"} #{event["type"] || "event"}",
        "- cursor: #{event["cursor"] || ""}",
        "- summary: #{event_summary(event)}"
      ]
      |> Enum.concat(tool_lines(event))
      |> Enum.join("\n")
    end)
  end

  defp pi_session_jsonl(session_id, transcript, events, cwd, title) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    now_ms = System.system_time(:millisecond)
    session = pi_session_id(session_id)
    root_id = pi_entry_id(session_id, "session-info")

    header = %{
      "cwd" => cwd,
      "id" => session,
      "timestamp" => now,
      "type" => "session",
      "version" => 3
    }

    entries =
      [
        %{
          "id" => root_id,
          "name" => title,
          "parentId" => nil,
          "timestamp" => now,
          "type" => "session_info"
        },
        %{
          "id" => pi_entry_id(session_id, "import-user"),
          "message" => %{
            "content" =>
              "Imported Wardwright session trace #{session_id}. Treat this as recorded evidence, not as hidden Pi agent state.",
            "role" => "user",
            "timestamp" => now_ms
          },
          "parentId" => root_id,
          "timestamp" => now,
          "type" => "message"
        },
        %{
          "id" => pi_entry_id(session_id, "trace-summary"),
          "message" => %{
            "api" => "wardwright",
            "content" => [
              %{
                "text" =>
                  "Recording scope: #{transcript["recording_scope"] || "unknown"}\n\n" <>
                    "Events: #{length(events)}\n\n" <>
                    "The following synthetic tool calls preserve Wardwright trace evidence for Pi fork/resume experiments.",
                "type" => "text"
              }
            ],
            "model" => "wardwright-trace",
            "provider" => "wardwright",
            "role" => "assistant",
            "stopReason" => "stop",
            "timestamp" => now_ms,
            "usage" => zero_usage()
          },
          "parentId" => pi_entry_id(session_id, "import-user"),
          "timestamp" => now,
          "type" => "message"
        }
      ]

    {_parent_id, event_entries} =
      Enum.reduce(
        Enum.with_index(events, 1),
        {pi_entry_id(session_id, "trace-summary"), []},
        fn {event, index}, {parent_id, acc} ->
          {next_parent, entries} =
            pi_event_entries(session_id, event, index, parent_id, now, now_ms)

          {next_parent, acc ++ entries}
        end
      )

    [header | entries ++ event_entries]
    |> Enum.map_join("\n", &JSON.encode!/1)
    |> Kernel.<>("\n")
  end

  defp pi_event_entries(session_id, %{"tool" => %{"name" => tool_name} = tool} = event, index, parent_id, now, now_ms) do
    call_id = pi_entry_id(session_id, "tool-call-#{index}")
    assistant_id = pi_entry_id(session_id, "assistant-#{index}")
    result_id = pi_entry_id(session_id, "tool-result-#{index}")

    assistant = %{
      "id" => assistant_id,
      "message" => %{
        "api" => "wardwright",
        "content" => [
          %{
            "text" => "Wardwright event #{event["sequence"] || index}: #{event_summary(event)}",
            "type" => "text"
          },
          %{
            "arguments" => tool["args"] || %{},
            "id" => call_id,
            "name" => tool_name,
            "type" => "toolCall"
          }
        ],
        "model" => "wardwright-trace",
        "provider" => "wardwright",
        "role" => "assistant",
        "stopReason" => "toolUse",
        "timestamp" => now_ms + index,
        "usage" => zero_usage()
      },
      "parentId" => parent_id,
      "timestamp" => now,
      "type" => "message"
    }

    result = %{
      "id" => result_id,
      "message" => %{
        "content" => [%{"text" => safe_json(tool["result"] || %{}), "type" => "text"}],
        "details" => %{
          "cursor" => event["cursor"] || "",
          "fingerprint" => stable_fingerprint(tool),
          "wardwright_event_type" => event["type"] || "event"
        },
        "isError" => event["status"] == "error",
        "role" => "toolResult",
        "timestamp" => now_ms + index,
        "toolCallId" => call_id,
        "toolName" => tool_name
      },
      "parentId" => assistant_id,
      "timestamp" => now,
      "type" => "message"
    }

    {result_id, [assistant, result]}
  end

  defp pi_event_entries(session_id, event, index, parent_id, now, now_ms) do
    entry_id = pi_entry_id(session_id, "event-#{index}")

    entry = %{
      "content" => "Wardwright event #{event["sequence"] || index}: #{event_summary(event)}",
      "customType" => "wardwright-trace-event",
      "details" => %{"cursor" => event["cursor"] || "", "event" => event},
      "display" => true,
      "id" => entry_id,
      "parentId" => parent_id,
      "timestamp" => now,
      "type" => "custom_message"
    }

    _ = now_ms
    {entry_id, [entry]}
  end

  defp zero_usage do
    %{
      "cacheRead" => 0,
      "cacheWrite" => 0,
      "cost" => %{"cacheRead" => 0, "cacheWrite" => 0, "input" => 0, "output" => 0, "total" => 0},
      "input" => 0,
      "output" => 0,
      "totalTokens" => 0
    }
  end

  defp oh_my_pi_ttsr_rule do
    """
    ---
    description: Wardwright read-before-edit replay guard
    condition:
      - "edit_file"
      - "write_file"
      - "patch"
    scope:
      - "text"
      - "tool:edit(*)"
      - "tool:write(*)"
    interruptMode: "always"
    ---

    If a continuation is about to edit or write a file from an imported
    Wardwright trace, require explicit read evidence for the same path first.
    Treat missing read evidence as a replay finding, not as permission to keep
    editing.
    """
  end

  defp pi_state_fidelity_extension do
    """
    import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
    import { createHash } from "node:crypto";
    import { readFileSync } from "node:fs";

    function digest(value: unknown): string {
      return createHash("sha256").update(JSON.stringify(value)).digest("hex");
    }

    export default function wardwrightStateFidelity(pi: ExtensionAPI) {
      const z = pi.zod;

      pi.registerTool({
        name: "wardwright_verify_state_fidelity",
        label: "Verify Wardwright fidelity",
        description: "Compare an exported Wardwright probe with observed Pi replay state.",
        parameters: z.object({
          probePath: z.string(),
          observed: z.any(),
        }),
        async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
          const probe = JSON.parse(readFileSync(params.probePath, "utf8"));
          const observed = params.observed ?? {};
          return {
            content: [{ type: "text", text: JSON.stringify({
              schema: "wardwright.pi_state_fidelity_verification_spike.v0",
              adapter_id: probe.adapter_id,
              trace_fingerprint_matches: probe.trace_fingerprint === observed.trace_fingerprint,
              observed_digest: digest(observed),
              equivalent_agent_resume_claim_allowed: false,
            }) }],
            details: {},
          };
        },
      });
    }
    """
  end

  defp opencode_state_fidelity_plugin do
    """
    import type { Plugin } from "@opencode-ai/plugin";

    export const WardwrightStateFidelity: Plugin = async () => {
      return {
        "experimental.session.compacting": async (_input, output) => {
          output.context.push(`Wardwright imported traces are evidence handoffs. Do not claim equivalent native resume unless state_fidelity_probe verification passes and workspace/private harness state are separately proven.`);
        },
        "tool.execute.after": async (input, output) => {
          if (input.tool === "edit" || input.tool === "write") {
            output.metadata = {
              ...(output.metadata ?? {}),
              wardwright_replay_note: "write-class action observed during Wardwright replay spike",
            };
          }
        },
      };
    };
    """
  end

  defp tool_lines(%{"tool" => %{"name" => name} = tool}) do
    [
      "- tool: #{name}",
      "- args: #{safe_json(tool["args"] || %{})}",
      "- result: #{safe_json(tool["result"] || %{})}"
    ]
  end

  defp tool_lines(_event), do: []

  defp event_summary(%{"content_preview" => preview}) when is_binary(preview), do: preview

  defp event_summary(%{"failure_class" => failure_class}) when is_binary(failure_class), do: failure_class

  defp event_summary(%{"status" => status}) when is_binary(status), do: status

  defp event_summary(%{"receipt_id" => receipt_id}) when is_binary(receipt_id), do: "receipt #{receipt_id}"

  defp event_summary(_event), do: "recorded trace event"

  defp fidelity_notice(adapter) do
    case adapter["equivalent_agent_resume"] do
      true ->
        "This adapter claims equivalent native agent resume for the represented trace."

      _ ->
        "This adapter does not preserve full hidden agent state. Treat the export as a best-effort replay/handoff."
    end
  end

  defp adapter_warnings(adapter) do
    missing = adapter["missing_fidelity"] || []

    [
      if(adapter["installed"] != true, do: "#{adapter["label"]} was not detected on PATH."),
      missing_warning(missing),
      verification_warning(adapter)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp missing_warning([]), do: nil

  defp missing_warning(missing) do
    "Missing fidelity: #{Enum.join(missing, ", ")}."
  end

  defp verification_warning(%{"equivalent_agent_resume" => true}), do: nil

  defp verification_warning(%{"state_fidelity_verification" => %{"required" => true}}) do
    "State fidelity verification is still required before treating this as equivalent agent resume."
  end

  defp verification_warning(_adapter), do: nil

  defp state_fidelity_verification(true, _missing_fidelity) do
    %{
      "required" => false,
      "status" => "verified_equivalent_resume",
      "steps" => []
    }
  end

  defp state_fidelity_verification(false, missing_fidelity) do
    %{
      "missing_fidelity" => missing_fidelity,
      "required" => true,
      "status" => "unverified_best_effort_handoff",
      "steps" => [
        "import the saved Wardwright artifact into the target harness",
        "resume or fork through the harness native session controls",
        "inspect the harness session store/export for preserved tool results and hidden state",
        "run a behavior-level continuation and compare it with the Wardwright trace"
      ]
    }
  end

  defp state_fidelity_probe(session_id, adapter, events) do
    tool_result_fingerprints =
      events
      |> Enum.filter(&tool_result_event?/1)
      |> Enum.map(fn event ->
        %{
          "cursor" => event["cursor"] || "",
          "fingerprint" => stable_fingerprint(event["tool"] || event),
          "tool_name" => get_in(event, ["tool", "name"]) || "unknown"
        }
      end)

    %{
      "adapter_id" => adapter["id"],
      "event_count" => length(events),
      "pass_conditions" => [
        "imported harness session exposes the same trace_fingerprint",
        "imported harness session preserves every tool_result_fingerprint",
        "forked continuation can identify the same read-before-edit cursor before taking write-class action"
      ],
      "schema" => "wardwright.harness_state_fidelity_probe.v0",
      "session_id" => session_id,
      "tool_result_count" => length(tool_result_fingerprints),
      "tool_result_fingerprints" => tool_result_fingerprints,
      "trace_fingerprint" => stable_fingerprint(events)
    }
  end

  defp tool_result_event?(%{"tool" => %{"result" => _result}}), do: true
  defp tool_result_event?(_event), do: false

  defp fingerprint_difference(left, right) do
    right_counts = fingerprint_counts(right)

    {missing, _remaining_counts} =
      Enum.reduce(left, {[], right_counts}, fn item, {missing, counts} ->
        fingerprint = item["fingerprint"]

        if is_binary(fingerprint) and Map.get(counts, fingerprint, 0) > 0 do
          {missing, Map.update!(counts, fingerprint, &(&1 - 1))}
        else
          {[item | missing], counts}
        end
      end)

    Enum.reverse(missing)
  end

  defp fingerprint_counts(items) do
    Enum.reduce(items, %{}, fn item, counts ->
      case item["fingerprint"] do
        fingerprint when is_binary(fingerprint) -> Map.update(counts, fingerprint, 1, &(&1 + 1))
        _fingerprint -> counts
      end
    end)
  end

  defp safe_json(value) do
    JSON.encode!(value)
  rescue
    _ -> inspect(value)
  end

  defp stable_fingerprint(value) do
    value
    |> safe_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp opencode_session_id(session_id), do: "ses_ww" <> short_hash(session_id)

  defp pi_session_id(session_id), do: "ww-" <> short_hash(session_id)

  defp opencode_file_name(session_id), do: "wardwright-#{safe_file_id(session_id)}.opencode.json"

  defp pi_file_name(session_id), do: "wardwright-#{safe_file_id(session_id)}.pi.jsonl"

  defp pi_entry_id(session_id, label), do: short_hash("pi:#{session_id}:#{label}") |> String.slice(0, 8)

  defp opencode_id(prefix, session_id, sequence) do
    "#{prefix}_ww#{short_hash("#{session_id}:#{sequence}")}"
  end

  defp short_hash(value) do
    :crypto.hash(:sha256, to_string(value))
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 24)
  end

  defp installed?(command) do
    System.find_executable(command) != nil
  end

  defp safe_file_id(value) do
    value
    |> to_string()
    |> Base.url_encode64(padding: false)
  end

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end

  defp write_private_file(path, content) do
    with :ok <- File.write(path, content) do
      chmod_private_file(path)
    end
  end

  defp chmod_private_dir(path) do
    case File.chmod(path, 0o700) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp chmod_private_file(path) do
    case File.chmod(path, 0o600) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
