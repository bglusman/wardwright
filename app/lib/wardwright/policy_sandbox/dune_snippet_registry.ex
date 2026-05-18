defmodule Wardwright.PolicySandbox.DuneSnippetRegistry do
  @moduledoc """
  Built-in Dune policy snippets for the code-shaped authoring spike.

  The registry is deliberately small. Its job is to make Dune snippets
  inspectable, runnable, and comparable with today's structured policy
  primitives without making Dune the only policy representation.
  """

  alias Wardwright.PolicySandbox.Dune, as: DuneSandbox

  @schema "wardwright.dune_snippet_registry.v1"

  @snippets [
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

  def evaluate(params) when is_map(params) do
    with {:ok, snippet} <- snippet_for(params) do
      input = Map.get(params, "input", Map.get(snippet, "example_input", %{}))
      opts = evaluation_opts(Map.get(params, "limits", %{}))

      result =
        snippet
        |> Map.fetch!("source")
        |> DuneSandbox.eval_snippet(input, opts)

      {:ok,
       %{
         "schema" => "wardwright.dune_snippet_evaluation.v1",
         "snippet" => public_snippet(snippet),
         "input" => input,
         "result" => result,
         "review_notes" => review_notes(snippet, result)
       }}
    end
  end

  def evaluate(_params), do: {:error, "Dune snippet evaluation body must be an object."}

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
