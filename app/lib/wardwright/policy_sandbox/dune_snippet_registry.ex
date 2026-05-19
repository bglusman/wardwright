defmodule Wardwright.PolicySandbox.DuneSnippetRegistry do
  @moduledoc """
  Built-in Dune policy snippets for the code-shaped authoring spike.

  The registry is deliberately small. Its job is to make Dune snippets
  inspectable, runnable, and comparable with today's structured policy
  primitives without making Dune the only policy representation.
  """

  alias Wardwright.PolicySandbox.Dune, as: DuneSandbox

  @schema "wardwright.dune_snippet_registry.v1"
  @default_dune_session_key "default"
  @default_dune_ttl_ms 300_000
  @max_dune_ttl_ms 3_600_000
  @user_id_pattern ~r/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/

  @snippets [
    %{
      "description" =>
        "Compatibility implementation for legacy engine: primitive rules that match request text and emit policy actions.",
      "example_input" => %{
        "request_text" => "please deny me",
        "rules" => [%{"action" => "block", "contains" => "deny me", "id" => "legacy-deny"}]
      },
      "id" => "primitive.request-contains-actions",
      "input_shape" => %{
        "request_text" => "string",
        "rules" => "list[{id?: string, contains: string, action?: string}]"
      },
      "phase" => "request.review",
      "replaces_primitives" => ["engine.primitive", "contains_match"],
      "source" => """
      text = String.downcase(input["request_text"] || "")
      rules = input["rules"] || []

      actions =
        Enum.reduce(rules, [], fn rule, acc ->
          raw_contains = rule["contains"]
          contains = if(is_binary(raw_contains), do: String.downcase(raw_contains), else: "")

          if contains != "" and String.contains?(text, contains) do
            [
              %{
                "rule_id" => rule["id"] || "primitive-rule",
                "action" => rule["action"] || "annotate",
                "matched" => true
              }
              | acc
            ]
          else
            acc
          end
        end)
        |> Enum.reverse()

      %{
        "action" => if(Enum.any?(actions, fn action -> action["action"] == "block" end), do: "block", else: "allow"),
        "actions" => actions,
        "reason" => "legacy primitive contains rules evaluated by Dune",
        "trace" => [
          %{"rule" => "legacy_primitive_contains", "matched_count" => Enum.count(actions)}
        ]
      }
      """,
      "title" => "Request contains actions"
    },
    %{
      "description" =>
        "Evaluate one request/route governance rule with contains or regex matching and emit a normalized action intent.",
      "example_input" => %{
        "request_text" => "please return json for the caller",
        "rule" => %{
          "action" => "inject_reminder_and_retry",
          "contains" => "return json",
          "id" => "json-reminder",
          "kind" => "request_transform",
          "reminder" => "Return only valid JSON."
        }
      },
      "id" => "primitive.request-rule-action",
      "input_shape" => %{
        "request_text" => "string",
        "rule" => "{id?: string, kind: string, contains?: string, regex?: string, action?: string}"
      },
      "phase" => "request.review",
      "replaces_primitives" => [
        "request_guard",
        "request_transform",
        "receipt_annotation",
        "route_gate",
        "contains_match",
        "regex_match"
      ],
      "source" => """
      text = String.downcase(input["request_text"] || "")
      rule = input["rule"] || %{}

      raw_contains = rule["contains"]
      contains =
        cond do
          is_binary(raw_contains) -> String.downcase(String.trim(raw_contains))
          is_integer(raw_contains) -> Integer.to_string(raw_contains)
          is_float(raw_contains) -> Float.to_string(raw_contains)
          true -> ""
        end

      contains_matched = contains != "" and String.contains?(text, contains)

      regex = rule["regex"]
      regex_matched =
        if is_binary(regex) and regex != "" do
          case Regex.compile(regex) do
            {:ok, compiled} -> Regex.match?(compiled, text)
            {:error, _reason} -> false
          end
        else
          false
        end

      matched = contains_matched or regex_matched

      if matched do
        action = rule["action"] || "annotate"

        %{
          "action" => action,
          "actions" => [
            %{
              "rule_id" => rule["id"] || "policy",
              "kind" => rule["kind"] || "policy_engine",
              "action" => action,
              "matched" => true,
              "message" => rule["message"] || "request policy matched",
              "severity" => rule["severity"] || "info",
              "allowed_targets" => rule["allowed_targets"],
              "target_model" => rule["target_model"] || rule["model"],
              "allow_fallback" => rule["allow_fallback"],
              "reminder" => rule["reminder"],
              "idempotency_key" => rule["idempotency_key"],
              "match" => %{
                "contains" => contains_matched,
                "regex" => regex_matched
              }
            }
          ],
          "reason" => "request rule matched by Dune",
          "trace" => [
            %{"rule" => "request_contains", "result" => contains_matched},
            %{"rule" => "request_regex", "result" => regex_matched}
          ]
        }
      else
        %{
          "action" => "allow",
          "actions" => [],
          "reason" => "request rule did not match",
          "trace" => [
            %{"rule" => "request_contains", "result" => false},
            %{"rule" => "request_regex", "result" => false}
          ]
        }
      end
      """,
      "title" => "Request rule action"
    },
    %{
      "description" =>
        "Restrict routing to local targets when the request carries private context and cloud routing was not explicitly approved.",
      "example_input" => %{
        "available_targets" => ["local/qwen", "managed/kimi"],
        "cloud_approved" => false,
        "private_context" => true
      },
      "id" => "route.private-context-local-only",
      "input_shape" => %{
        "available_targets" => "list[string]",
        "cloud_approved" => "boolean",
        "private_context" => "boolean"
      },
      "phase" => "route",
      "replaces_primitives" => ["route_guard", "private_context_gate"],
      "source" => """
      private_context = input["private_context"] == true
      cloud_approved = input["cloud_approved"] == true
      available_targets = input["available_targets"] || []

      if private_context and not cloud_approved do
        %{
          "action" => "restrict_routes",
          "allowed_targets" => Enum.filter(available_targets, fn target ->
            String.starts_with?(target, "local/")
          end),
          "reason" => "private_context_requires_local_route",
          "trace" => [
            %{"rule" => "private_context", "result" => true},
            %{"rule" => "cloud_approved", "result" => false}
          ]
        }
      else
        %{
          "action" => "allow_routes",
          "allowed_targets" => available_targets,
          "reason" => "no_private_route_restriction",
          "trace" => [
            %{"rule" => "private_context", "result" => private_context},
            %{"rule" => "cloud_approved", "result" => cloud_approved}
          ]
        }
      end
      """,
      "title" => "Private context route gate"
    },
    %{
      "description" =>
        "Escalate from redaction to review when related secret-like matches exceed a session-local threshold.",
      "example_input" => %{"current_match" => true, "related_secret_matches" => 2, "threshold" => 3},
      "id" => "history.related-secret-ladder",
      "input_shape" => %{"current_match" => "boolean", "related_secret_matches" => "integer", "threshold" => "integer"},
      "phase" => "response.streaming",
      "replaces_primitives" => ["regex_match", "history_threshold", "state_transition"],
      "source" => """
      current_match = input["current_match"] == true
      related = input["related_secret_matches"] || 0
      threshold = input["threshold"] || 3
      total = if current_match, do: related + 1, else: related

      cond do
        total >= threshold ->
          %{
            "action" => "transition_state",
            "to_state" => "review_required",
            "reason" => "related_secret_threshold_reached",
            "trace" => [%{"rule" => "related_secret_count", "value" => total, "threshold" => threshold}]
          }

        current_match ->
          %{
            "action" => "rewrite",
            "replacement" => "[redacted]",
            "reason" => "secret_like_span_redacted",
            "trace" => [%{"rule" => "current_secret_match", "result" => true}]
          }

        true ->
          %{
            "action" => "allow",
            "reason" => "no_secret_match",
            "trace" => [%{"rule" => "current_secret_match", "result" => false}]
          }
      end
      """,
      "title" => "Related secret history ladder"
    },
    %{
      "description" =>
        "Allow shell writes only after a recent browser or docs lookup in the same session, otherwise require review.",
      "example_input" => %{"recent_tools" => ["browser.open", "browser.screenshot"], "tool_name" => "shell.exec"},
      "id" => "tool.browser-before-shell",
      "input_shape" => %{"recent_tools" => "list[string]", "tool_name" => "string"},
      "phase" => "tool",
      "replaces_primitives" => ["tool_sequence", "history_window", "review_gate"],
      "source" => """
      tool_name = input["tool_name"] || ""
      recent_tools = input["recent_tools"] || []
      browser_seen = Enum.any?(recent_tools, fn name -> String.starts_with?(name, "browser.") end)
      shell_write = String.starts_with?(tool_name, "shell.")

      cond do
        shell_write and browser_seen ->
          %{
            "action" => "allow_tool",
            "reason" => "browser_context_seen_before_shell",
            "trace" => [%{"rule" => "browser_before_shell", "result" => true}]
          }

        shell_write ->
          %{
            "action" => "require_review",
            "reason" => "shell_without_recent_browser_context",
            "trace" => [%{"rule" => "browser_before_shell", "result" => false}]
          }

        true ->
          %{
            "action" => "allow_tool",
            "reason" => "non_shell_tool",
            "trace" => [%{"rule" => "shell_write", "result" => false}]
          }
      end
      """,
      "title" => "Browser before shell"
    }
  ]

  def list do
    %{
      "data" => Enum.map(all_snippets(), &public_snippet/1),
      "schema" => @schema
    }
  end

  def get(id) when is_binary(id) do
    case Enum.find(all_snippets(), &(&1["id"] == id)) do
      nil -> {:error, "Dune snippet not found: #{id}"}
      snippet -> {:ok, snippet}
    end
  end

  def save(params) when is_map(params) do
    with {:ok, snippet} <- user_snippet(params),
         :ok <- ensure_no_builtin_collision(snippet["id"]),
         :ok <- File.mkdir_p(workspace_dir()),
         :ok <- write_user_snippet(snippet) do
      {:ok,
       %{
         "schema" => "wardwright.dune_snippet_write.v1",
         "snippet" => public_snippet(snippet),
         "storage" => %{
           "endpoint" => workspace_dir(),
           "kind" => "workspace"
         }
       }}
    end
  end

  def save(_params), do: {:error, "Dune snippet body must be an object."}

  def delete(id) when is_binary(id) do
    id = String.trim(id)

    with :ok <- valid_user_id(id),
         :ok <- ensure_no_builtin_collision(id) do
      path = user_snippet_path(id)

      case File.rm(path) do
        :ok ->
          {:ok,
           %{
             "deleted" => true,
             "id" => id,
             "schema" => "wardwright.dune_snippet_delete.v1"
           }}

        {:error, :enoent} ->
          {:error, "Dune snippet not found: #{id}"}

        {:error, reason} ->
          {:error, "Could not delete Dune snippet #{id}: #{format_file_error(reason)}"}
      end
    end
  end

  def delete(_id), do: {:error, "Dune snippet id must be a string."}

  def source!(id) when is_binary(id) do
    case get(id) do
      {:ok, snippet} -> Map.fetch!(snippet, "source")
      {:error, message} -> raise ArgumentError, message
    end
  end

  def evaluate(params) when is_map(params) do
    with {:ok, snippet} <- snippet_for(params) do
      input = Map.get(params, "input", Map.get(snippet, "example_input", %{}))
      opts = evaluation_opts(Map.get(params, "limits", %{}))

      with {:ok, {result, session_metadata}} <- evaluate_snippet(snippet, input, params, opts) do
        {:ok,
         %{
           "input" => input,
           "result" => result,
           "review_notes" => review_notes(snippet, result),
           "schema" => "wardwright.dune_snippet_evaluation.v1",
           "snippet" => public_snippet(snippet)
         }
         |> put_session_metadata(session_metadata)}
      end
    end
  end

  def evaluate(_params), do: {:error, "Dune snippet evaluation body must be an object."}

  defp all_snippets do
    built_in_snippets() ++ user_snippets()
  end

  defp built_in_snippets do
    Enum.map(@snippets, &Map.put(&1, "origin", "built_in"))
  end

  defp user_snippets do
    workspace_dir()
    |> File.ls()
    |> case do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.flat_map(fn entry ->
          workspace_dir()
          |> Path.join(entry)
          |> read_user_snippet()
        end)
        |> Enum.reject(fn snippet -> builtin_id?(snippet["id"]) end)

      {:error, :enoent} ->
        []

      {:error, _reason} ->
        []
    end
  end

  defp user_snippet(params) do
    id = params |> Map.get("id", Map.get(params, "snippet_id")) |> string_value()
    source = params |> Map.get("source") |> string_value()

    with :ok <- valid_user_id(id),
         :ok <- require_source(source) do
      {:ok,
       %{
         "description" => optional_string(params, "description", "User supplied snippet."),
         "example_input" => map_value(Map.get(params, "example_input", Map.get(params, "input"))),
         "id" => id,
         "input_shape" => map_value(Map.get(params, "input_shape")),
         "origin" => "workspace",
         "phase" => optional_string(params, "phase", "unknown"),
         "replaces_primitives" => list_value(Map.get(params, "replaces_primitives")),
         "source" => source,
         "title" => optional_string(params, "title", id)
       }}
    end
  end

  defp valid_user_id(id) when is_binary(id) do
    if Regex.match?(@user_id_pattern, id) do
      :ok
    else
      {:error,
       "Dune snippet id must start with a letter or number and contain only letters, numbers, dots, underscores, colons, or hyphens."}
    end
  end

  defp valid_user_id(_id), do: {:error, "Dune snippet id must be a non-empty string."}

  defp require_source(source) when is_binary(source) and source != "", do: :ok
  defp require_source(_source), do: {:error, "Dune snippet source must be a non-empty string."}

  defp ensure_no_builtin_collision(id) do
    if builtin_id?(id) do
      {:error, "Built-in Dune snippet ids are read-only: #{id}"}
    else
      :ok
    end
  end

  defp builtin_id?(id), do: Enum.any?(@snippets, &(&1["id"] == id))

  defp write_user_snippet(snippet) do
    path = user_snippet_path(snippet["id"])
    tmp_path = "#{path}.tmp"
    body = Jason.encode!(snippet, pretty: true)

    with :ok <- File.write(tmp_path, body),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, reason} -> {:error, "Could not write Dune snippet: #{format_file_error(reason)}"}
    end
  end

  defp read_user_snippet(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, snippet} <- user_snippet(decoded) do
      [Map.put(snippet, "origin", "workspace")]
    else
      _error -> []
    end
  end

  defp user_snippet_path(id) do
    Path.join(workspace_dir(), "#{Base.url_encode64(id, padding: false)}.json")
  end

  defp workspace_dir do
    Application.get_env(:wardwright, :dune_snippet_workspace_dir, default_workspace_dir())
  end

  defp default_workspace_dir do
    Path.join(System.user_home!(), ".wardwright/dune-snippets")
  end

  defp evaluate_snippet(snippet, input, params, opts) do
    source = Map.fetch!(snippet, "source")

    case Map.get(params, "session") do
      session when is_map(session) ->
        with {:ok, runtime} <- runtime_session(session) do
          Wardwright.Runtime.eval_dune_snippet(
            runtime.model_id,
            runtime.version,
            runtime.session_id,
            source,
            input,
            Map.take(runtime, [:key, :ttl_ms, :reset?]),
            opts
          )
        end

      _session ->
        {:ok, {DuneSandbox.eval_snippet(source, input, opts), nil}}
    end
  end

  defp runtime_session(session) do
    model_id = session |> Map.get("model_id", Map.get(session, :model_id)) |> string_value()
    session_id = session |> Map.get("session_id", Map.get(session, :session_id)) |> string_value()

    key =
      session
      |> Map.get("key", Map.get(session, :key, @default_dune_session_key))
      |> string_value()

    version =
      session
      |> Map.get("version", Map.get(session, :version, Wardwright.current_config()["version"]))
      |> string_value()

    with {:ok, ttl_ms} <- session_ttl_ms(session) do
      cond do
        model_id in [nil, ""] ->
          {:error, "session.model_id is required for stateful Dune snippet evaluation."}

        session_id in [nil, ""] ->
          {:error, "session.session_id is required for stateful Dune snippet evaluation."}

        version in [nil, ""] ->
          {:error, "session.version is required for stateful Dune snippet evaluation."}

        key in [nil, ""] ->
          {:error, "session.key must be a non-empty string when provided."}

        true ->
          {:ok,
           %{
             key: key,
             model_id: model_id,
             reset?: truthy?(Map.get(session, "reset", Map.get(session, :reset, false))),
             session_id: session_id,
             ttl_ms: ttl_ms,
             version: version
           }}
      end
    end
  end

  defp put_session_metadata(result, nil), do: result

  defp put_session_metadata(result, metadata) do
    Map.put(result, "session", %{
      "key" => metadata.key,
      "model_id" => metadata.model_id,
      "reused" => metadata.reused?,
      "session_id" => metadata.session_id,
      "status" => metadata.status,
      "ttl_ms" => metadata.ttl_ms,
      "version" => metadata.version
    })
  end

  defp snippet_for(%{"source" => source} = params) when is_binary(source) do
    id = Map.get(params, "snippet_id", "ad_hoc.dune")

    {:ok,
     %{
       "description" => Map.get(params, "description", "User supplied snippet."),
       "example_input" => Map.get(params, "input", %{}),
       "id" => id,
       "input_shape" => Map.get(params, "input_shape", %{}),
       "phase" => Map.get(params, "phase", "unknown"),
       "replaces_primitives" => Map.get(params, "replaces_primitives", []),
       "source" => source,
       "title" => Map.get(params, "title", "Ad hoc Dune snippet")
     }}
  end

  defp snippet_for(params) do
    params
    |> Map.get("snippet_id", Map.get(params, "id"))
    |> case do
      id when is_binary(id) and id != "" -> get(id)
      _ -> {:error, "Provide snippet_id for a registry snippet or source for an ad hoc snippet."}
    end
  end

  defp evaluation_opts(limits) when is_map(limits) do
    []
    |> put_positive_integer(:timeout, Map.get(limits, "timeout_ms"))
    |> put_positive_integer(:max_reductions, Map.get(limits, "max_reductions"))
    |> put_positive_integer(:max_heap_size, Map.get(limits, "max_heap_size"))
  end

  defp evaluation_opts(_limits), do: []

  defp put_positive_integer(opts, key, value) when is_integer(value) and value > 0, do: Keyword.put(opts, key, value)

  defp put_positive_integer(opts, _key, _value), do: opts

  defp string_value(value) when is_binary(value), do: String.trim(value)
  defp string_value(_value), do: nil

  defp optional_string(params, key, default) do
    params
    |> Map.get(key, default)
    |> string_value()
    |> case do
      nil -> default
      "" -> default
      value -> value
    end
  end

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []

  defp map_value(value) when is_map(value), do: value
  defp map_value(_value), do: %{}

  defp session_ttl_ms(session) do
    if Map.has_key?(session, "ttl_ms") or Map.has_key?(session, :ttl_ms) do
      session
      |> Map.get("ttl_ms", Map.get(session, :ttl_ms))
      |> parse_ttl_ms()
    else
      {:ok, @default_dune_ttl_ms}
    end
  end

  defp parse_ttl_ms(value) when is_integer(value) and value > 0 do
    bounded_ttl_ms(value)
  end

  defp parse_ttl_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> bounded_ttl_ms(integer)
      _other -> {:error, "session.ttl_ms must be a positive integer when provided."}
    end
  end

  defp parse_ttl_ms(_value), do: {:error, "session.ttl_ms must be a positive integer when provided."}

  defp bounded_ttl_ms(value) when value <= @max_dune_ttl_ms, do: {:ok, value}

  defp bounded_ttl_ms(_value), do: {:error, "session.ttl_ms must be less than or equal to #{@max_dune_ttl_ms}."}

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp public_snippet(snippet) do
    Map.take(snippet, [
      "id",
      "title",
      "phase",
      "description",
      "replaces_primitives",
      "input_shape",
      "example_input",
      "source",
      "origin"
    ])
  end

  defp format_file_error(reason), do: reason |> :file.format_error() |> List.to_string()

  defp review_notes(_snippet, %{"policy_status" => "ok"}) do
    [
      "Snippet returned a normalized policy-shaped action.",
      "Run the same snippet against representative scenarios before using it in an artifact."
    ]
  end

  defp review_notes(_snippet, %{"policy_result" => %{"reason" => reason}}) do
    [
      "Snippet did not return a usable policy action and should fail closed.",
      "Reason: #{reason}"
    ]
  end

  defp review_notes(_snippet, _result) do
    ["Snippet result needs review before it can be used in policy evaluation."]
  end
end
