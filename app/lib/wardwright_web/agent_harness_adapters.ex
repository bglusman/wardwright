defmodule WardwrightWeb.AgentHarnessAdapters do
  @moduledoc """
  Best-effort exports from Wardwright session traces into external agent harnesses.

  The adapter contract is deliberately conservative. A harness can accept a
  trace export without preserving the hidden state that made the original agent
  run behave the way it did.
  """

  @contract_version "wardwright.harness_adapter.v0"
  @opencode_version "1.15.4"

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
      adapter("pi", "Pi / oh-my-pi", installed?("pi") or installed?("oh-my-pi"), %{
        "model_context_replay" => true,
        "native_session_fork" => false,
        "native_session_import" => false,
        "native_session_resume" => false,
        "native_tool_results" => false,
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
        "opencode" -> {:ok, opencode_export(session_id, transcript, events, adapter, opts)}
        "claude" -> {:ok, handoff_export(session_id, transcript, events, adapter, opts)}
        "codex" -> {:ok, handoff_export(session_id, transcript, events, adapter, opts)}
        "pi" -> {:ok, handoff_export(session_id, transcript, events, adapter, opts)}
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

  defp adapter(id, label, installed, capabilities) do
    native_session_import = capabilities["native_session_import"] == true
    native_session_fork = capabilities["native_session_fork"] == true
    native_session_resume = capabilities["native_session_resume"] == true
    native_tool_results = capabilities["native_tool_results"] == true
    workspace_snapshot = capabilities["workspace_snapshot"] == true
    private_agent_state = capabilities["private_agent_state"] == true

    %{
      "capabilities" => capabilities,
      "contract_version" => @contract_version,
      "equivalent_agent_resume" =>
        :wardwright@harness_adapter.can_claim_equivalent_agent_resume(
          native_session_import,
          native_session_resume,
          native_tool_results,
          workspace_snapshot,
          private_agent_state
        ),
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
      "missing_fidelity" =>
        :wardwright@harness_adapter.missing_fidelity(
          native_session_import,
          native_session_fork,
          native_tool_results,
          workspace_snapshot,
          private_agent_state
        ),
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
        "tokens" => %{"cache" => %{"read" => 0, "write" => 0}, "input" => 0, "output" => 0, "reasoning" => 0},
        "version" => @opencode_version
      },
      "messages" => [
        opencode_user_message(export_id, user_message_id, session_id, transcript, events, now),
        opencode_assistant_message(export_id, assistant_message_id, user_message_id, session_id, events, now, cwd)
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
        "tokens" => %{"cache" => %{"read" => 0, "write" => 0}, "input" => 0, "output" => 0, "reasoning" => 0}
      },
      "parts" => [
        %{
          "id" => opencode_id("prt", session_id, 2),
          "messageID" => message_id,
          "sessionID" => export_id,
          "type" => "step-start"
        },
        text_part(export_id, message_id, opencode_id("prt", session_id, 3), trace_markdown(events)),
        %{
          "cost" => 0,
          "id" => opencode_id("prt", session_id, 4),
          "messageID" => message_id,
          "reason" => "stop",
          "sessionID" => export_id,
          "tokens" => %{"cache" => %{"read" => 0, "write" => 0}, "input" => 0, "output" => 0, "reasoning" => 0},
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
      "warnings" => adapter_warnings(adapter)
    }
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
      "pi < wardwright-handoff-prompt.md",
      "oh-my-pi < wardwright-handoff-prompt.md"
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
          write_json_artifact(dir, opencode_file_name(session_id), export["artifact"])

        "prompt_handoff" ->
          write_prompt_handoff_files(dir, get_in(export, ["artifact", "files"]) || [])

        _format ->
          {:error, "unsupported harness export artifact format"}
      end
    end
  end

  defp write_json_artifact(dir, file_name, artifact) do
    path = Path.join(dir, file_name)

    with :ok <- File.write(path, JSON.encode!(artifact)),
         :ok <- chmod_private_file(path) do
      {:ok, [path]}
    end
  rescue
    _error -> {:error, "could not encode harness export artifact"}
  end

  defp write_prompt_handoff_files(dir, files) when is_list(files) do
    files
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, paths} ->
      path = Path.join(dir, Path.basename(file["path"] || "wardwright-handoff.txt"))

      case write_private_file(path, file["content"] || "") do
        :ok -> {:cont, {:ok, [path | paths]}}
        {:error, reason} -> {:halt, {:error, "could not write harness export file: #{:file.format_error(reason)}"}}
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

  defp saved_export_commands(%{"adapter" => %{"id" => "claude"}}, [_trace_path, prompt_path])
       when is_binary(prompt_path) do
    [
      "claude --print --input-format text --output-format stream-json < #{shell_quote(prompt_path)}",
      "claude --resume <existing-claude-session-id> --fork-session"
    ]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "codex"}}, [_trace_path, prompt_path])
       when is_binary(prompt_path) do
    [
      "codex exec --json - < #{shell_quote(prompt_path)}",
      "codex fork <existing-codex-session-id> \"Continue from the Wardwright handoff prompt.\""
    ]
  end

  defp saved_export_commands(%{"adapter" => %{"id" => "pi"}}, [_trace_path, prompt_path]) when is_binary(prompt_path) do
    [
      "pi < #{shell_quote(prompt_path)}",
      "oh-my-pi < #{shell_quote(prompt_path)}"
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
      missing_warning(missing)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp missing_warning([]), do: nil

  defp missing_warning(missing) do
    "Missing fidelity: #{Enum.join(missing, ", ")}."
  end

  defp safe_json(value) do
    JSON.encode!(value)
  rescue
    _ -> inspect(value)
  end

  defp opencode_session_id(session_id), do: "ses_ww" <> short_hash(session_id)

  defp opencode_file_name(session_id), do: "wardwright-#{safe_file_id(session_id)}.opencode.json"

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
