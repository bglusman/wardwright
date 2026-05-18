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

  @snippets [
    %{
      "id" => "primitive.request-contains-actions",
      "title" => "Request contains actions",
      "phase" => "request.review",
      "description" =>
        "Compatibility implementation for legacy engine: primitive rules that match request text and emit policy actions.",
      "replaces_primitives" => ["engine.primitive", "contains_match"],
      "input_shape" => %{
        "request_text" => "string",
        "rules" => "list[{id?: string, contains: string, action?: string}]"
      },
      "example_input" => %{
        "request_text" => "please deny me",
        "rules" => [
          %{"id" => "legacy-deny", "contains" => "deny me", "action" => "block"}
        ]
      },
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
      """
    },
    %{
      "id" => "route.private-context-local-only",
      "title" => "Private context route gate",
      "phase" => "route",
      "description" =>
        "Restrict routing to local targets when the request carries private context and cloud routing was not explicitly approved.",
      "replaces_primitives" => ["route_guard", "private_context_gate"],
      "input_shape" => %{
        "private_context" => "boolean",
        "cloud_approved" => "boolean",
        "available_targets" => "list[string]"
      },
      "example_input" => %{
        "private_context" => true,
        "cloud_approved" => false,
        "available_targets" => ["local/qwen", "managed/kimi"]
      },
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
      """
    },
    %{
      "id" => "history.related-secret-ladder",
      "title" => "Related secret history ladder",
      "phase" => "response.streaming",
      "description" =>
        "Escalate from redaction to review when related secret-like matches exceed a session-local threshold.",
      "replaces_primitives" => ["regex_match", "history_threshold", "state_transition"],
      "input_shape" => %{
        "current_match" => "boolean",
        "related_secret_matches" => "integer",
        "threshold" => "integer"
      },
      "example_input" => %{
        "current_match" => true,
        "related_secret_matches" => 2,
        "threshold" => 3
      },
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
      """
    },
    %{
      "id" => "tool.browser-before-shell",
      "title" => "Browser before shell",
      "phase" => "tool",
      "description" =>
        "Allow shell writes only after a recent browser or docs lookup in the same session, otherwise require review.",
      "replaces_primitives" => ["tool_sequence", "history_window", "review_gate"],
      "input_shape" => %{
        "tool_name" => "string",
        "recent_tools" => "list[string]"
      },
      "example_input" => %{
        "tool_name" => "shell.exec",
        "recent_tools" => ["browser.open", "browser.screenshot"]
      },
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
      """
    }
  ]

  def list do
    %{
      "schema" => @schema,
      "data" => Enum.map(@snippets, &public_snippet/1)
    }
  end

  def get(id) when is_binary(id) do
    case Enum.find(@snippets, &(&1["id"] == id)) do
      nil -> {:error, "Dune snippet not found: #{id}"}
      snippet -> {:ok, snippet}
    end
  end

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
           "schema" => "wardwright.dune_snippet_evaluation.v1",
           "snippet" => public_snippet(snippet),
           "input" => input,
           "result" => result,
           "review_notes" => review_notes(snippet, result)
         }
         |> put_session_metadata(session_metadata)}
      end
    end
  end

  def evaluate(_params), do: {:error, "Dune snippet evaluation body must be an object."}

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

    ttl_ms =
      session
      |> Map.get("ttl_ms", Map.get(session, :ttl_ms, @default_dune_ttl_ms))
      |> positive_integer(@default_dune_ttl_ms)

    cond do
      model_id in [nil, ""] ->
        {:error, "session.model_id is required for stateful Dune snippet evaluation."}

      session_id in [nil, ""] ->
        {:error, "session.session_id is required for stateful Dune snippet evaluation."}

      version in [nil, ""] ->
        {:error, "session.version is required for stateful Dune snippet evaluation."}

      key in [nil, ""] ->
        {:error, "session.key must be a non-empty string when provided."}

      ttl_ms > @max_dune_ttl_ms ->
        {:error, "session.ttl_ms must be less than or equal to #{@max_dune_ttl_ms}."}

      true ->
        {:ok,
         %{
           model_id: model_id,
           version: version,
           session_id: session_id,
           key: key,
           ttl_ms: ttl_ms,
           reset?: truthy?(Map.get(session, "reset", Map.get(session, :reset, false)))
         }}
    end
  end

  defp put_session_metadata(result, nil), do: result

  defp put_session_metadata(result, metadata) do
    Map.put(result, "session", %{
      "model_id" => metadata.model_id,
      "version" => metadata.version,
      "session_id" => metadata.session_id,
      "key" => metadata.key,
      "status" => metadata.status,
      "reused" => metadata.reused?,
      "ttl_ms" => metadata.ttl_ms
    })
  end

  defp snippet_for(%{"source" => source} = params) when is_binary(source) do
    id = Map.get(params, "snippet_id", "ad_hoc.dune")

    {:ok,
     %{
       "id" => id,
       "title" => Map.get(params, "title", "Ad hoc Dune snippet"),
       "phase" => Map.get(params, "phase", "unknown"),
       "description" => Map.get(params, "description", "User supplied snippet."),
       "replaces_primitives" => Map.get(params, "replaces_primitives", []),
       "input_shape" => Map.get(params, "input_shape", %{}),
       "example_input" => Map.get(params, "input", %{}),
       "source" => source
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

  defp put_positive_integer(opts, key, value) when is_integer(value) and value > 0,
    do: Keyword.put(opts, key, value)

  defp put_positive_integer(opts, _key, _value), do: opts

  defp string_value(value) when is_binary(value), do: String.trim(value)
  defp string_value(_value), do: nil

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp positive_integer(_value, default), do: default

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
      "source"
    ])
  end

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
