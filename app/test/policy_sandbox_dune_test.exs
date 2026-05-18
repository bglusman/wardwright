defmodule Wardwright.PolicySandbox.DuneTest do
  use ExUnit.Case, async: true

  alias Wardwright.PolicySandbox.Dune, as: DuneSandbox
  alias Wardwright.PolicySandbox.DuneSnippetRegistry

  test "evaluates a deterministic policy-shaped result" do
    result =
      DuneSandbox.eval_string("""
      private_risk = true
      cloud_approved = false

      if private_risk and not cloud_approved do
        %{"action" => "restrict_routes", "allowed_targets" => ["local"]}
      else
        %{"action" => "allow_routes", "allowed_targets" => ["local", "cloud"]}
      end
      """)

    assert %{
             "status" => "ok",
             "value" => %{"action" => "restrict_routes", "allowed_targets" => ["local"]},
             "stdio" => ""
           } = result
  end

  test "parses without atom leaks and exposes a reviewable AST string" do
    result = DuneSandbox.parse_string("rule_name = :private_route_gate")

    assert result["status"] == "ok"
    assert result["inspected"] =~ "private_route_gate"
    assert inspect(result["value"]) =~ "__Dune_atom_"
  end

  test "forbidden host APIs fail closed with restricted errors" do
    for source <- [
          "File.cwd!()",
          "System.get_env()",
          "spawn(fn -> :ok end)",
          "send(self(), :leak)"
        ] do
      assert %{"status" => "error", "reason" => reason, "message" => message} =
               DuneSandbox.eval_string(source)

      assert reason in ["restricted", "module_restricted"]
      assert message =~ "restricted"
    end
  end

  test "reduction limit stops CPU-heavy policy work" do
    result =
      DuneSandbox.eval_string(
        """
        Enum.reduce(1..100_000, 0, fn i, acc ->
          Integer.gcd(i, acc + i)
        end)
        """,
        max_heap_size: 1_000_000,
        max_reductions: 2_000,
        timeout: 1_000
      )

    assert %{"status" => "error", "reason" => "reductions"} = result
  end

  test "memory limit stops large allocations" do
    result =
      DuneSandbox.eval_string(
        "List.duplicate(\"policy-event\", 100_000)",
        max_heap_size: 4_000,
        timeout: 1_000
      )

    assert %{"status" => "error", "reason" => "memory"} = result
  end

  test "wall clock timeout stops allowed slow code" do
    result =
      DuneSandbox.eval_string(
        """
        Enum.reduce(1..1_000_000, 0, fn i, acc ->
          Integer.gcd(i, acc + i)
        end)
        """,
        max_reductions: 10_000_000,
        timeout: 1
      )

    assert %{"status" => "error", "reason" => reason} = result
    assert reason in ["timeout", "reductions"]
  end

  test "registry snippets are inspectable and evaluate against example inputs" do
    registry = DuneSnippetRegistry.list()

    assert registry["schema"] == "wardwright.dune_snippet_registry.v1"
    assert Enum.count(registry["data"]) >= 4

    assert %{
             "id" => "history.related-secret-ladder",
             "source" => source,
             "example_input" => example_input
           } =
             Enum.find(registry["data"], &(&1["id"] == "history.related-secret-ladder"))

    assert source =~ "transition_state"

    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "snippet_id" => "history.related-secret-ladder",
               "input" => example_input
             })

    assert evaluation["schema"] == "wardwright.dune_snippet_evaluation.v1"

    assert get_in(evaluation, ["result", "policy_status"]) == "ok",
           "expected registry snippet to evaluate successfully, got: #{inspect(evaluation["result"], limit: :infinity)}"

    assert get_in(evaluation, ["result", "policy_result", "action"]) == "transition_state"
    assert get_in(evaluation, ["result", "policy_result", "to_state"]) == "review_required"
  end

  test "legacy primitive contains behavior is backed by the registry snippet" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "snippet_id" => "primitive.request-contains-actions",
               "input" => %{
                 "request_text" => "please deny me but keep notes",
                 "rules" => [
                   %{"id" => "legacy-deny", "contains" => "deny me", "action" => "block"},
                   %{"id" => "legacy-miss", "contains" => "not present", "action" => "annotate"},
                   %{"id" => "legacy-malformed", "contains" => 123, "action" => "block"}
                 ]
               }
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "block"

    assert [
             %{
               "rule_id" => "legacy-deny",
               "action" => "block",
               "matched" => true
             }
           ] = get_in(evaluation, ["result", "policy_result", "actions"])
  end

  test "request rule snippet preserves action metadata for host-side effects" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "snippet_id" => "primitive.request-rule-action",
               "input" => %{
                 "request_text" => "Please return JSON for downstream automation.",
                 "rule" => %{
                   "id" => "json-reminder",
                   "kind" => "request_transform",
                   "regex" => "return\\s+json",
                   "action" => "inject_reminder_and_retry",
                   "message" => "request needs JSON guidance",
                   "reminder" => "Return only valid JSON.",
                   "severity" => "warning"
                 }
               }
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"

    assert get_in(evaluation, ["result", "policy_result", "action"]) ==
             "inject_reminder_and_retry"

    assert [
             %{
               "rule_id" => "json-reminder",
               "kind" => "request_transform",
               "action" => "inject_reminder_and_retry",
               "matched" => true,
               "reminder" => "Return only valid JSON.",
               "severity" => "warning",
               "match" => %{"contains" => false, "regex" => true}
             }
           ] = get_in(evaluation, ["result", "policy_result", "actions"])
  end

  test "request rule snippet treats invalid regexes as non-matches" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "snippet_id" => "primitive.request-rule-action",
               "input" => %{
                 "request_text" => "please block",
                 "rule" => %{
                   "id" => "bad-regex",
                   "kind" => "request_guard",
                   "regex" => "[",
                   "action" => "block"
                 }
               }
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "allow"
    assert get_in(evaluation, ["result", "policy_result", "actions"]) == []
  end

  test "request rule snippet preserves metadata-compatible contains matching" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "snippet_id" => "primitive.request-rule-action",
               "input" => %{
                 "request_text" => "Find account 4938 before routing.",
                 "rule" => %{
                   "id" => "numeric-account",
                   "kind" => "request_guard",
                   "contains" => 4938,
                   "action" => "block"
                 }
               }
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "block"

    assert [%{"rule_id" => "numeric-account", "match" => %{"contains" => true}}] =
             get_in(evaluation, ["result", "policy_result", "actions"])
  end

  test "ad hoc snippets can be tested and malformed results fail closed" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               if input["approved"] do
                 %{"action" => "allow", "reason" => "approved"}
               else
                 %{"action" => "require_review", "reason" => "missing approval"}
               end
               """,
               "input" => %{"approved" => false}
             })

    assert get_in(evaluation, ["result", "policy_result", "action"]) == "require_review"

    assert {:ok, malformed} =
             DuneSnippetRegistry.evaluate(%{
               "source" => "\"not a policy result\"",
               "input" => %{}
             })

    assert get_in(malformed, ["result", "policy_status"]) == "error"
    assert get_in(malformed, ["result", "policy_result", "action"]) == "block"
    assert get_in(malformed, ["result", "policy_result", "reason"]) == "invalid_result"
  end

  test "stateful Dune snippet sessions preserve explicit policy-local bindings" do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    model_id = "test-model"
    version = "test-version"

    assert {:ok, first} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               events = [input["event"]]

               %{
                 "action" => "allow",
                 "count" => Enum.count(events),
                 "events" => events
               }
               """,
               "input" => %{"event" => "first"},
               "session" => %{
                 "model_id" => model_id,
                 "version" => version,
                 "session_id" => session_id,
                 "ttl_ms" => 60_000
               }
             })

    assert first["session"] == %{
             "model_id" => model_id,
             "version" => version,
             "session_id" => session_id,
             "key" => "default",
             "status" => "new",
             "reused" => false,
             "ttl_ms" => 60_000
           }

    assert get_in(first, ["result", "policy_result", "count"]) == 1

    assert {:ok, second} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               events = [input["event"] | events]

               %{
                 "action" => "allow",
                 "count" => Enum.count(events),
                 "events" => Enum.reverse(events)
               }
               """,
               "input" => %{"event" => "second"},
               "session" => %{
                 "model_id" => model_id,
                 "version" => version,
                 "session_id" => session_id,
                 "ttl_ms" => 60_000
               }
             })

    assert second["session"]["status"] == "reused"
    assert get_in(second, ["result", "policy_result", "count"]) == 2
    assert get_in(second, ["result", "policy_result", "events"]) == ["first", "second"]

    assert {:ok, reset} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               events = [input["event"]]
               %{"action" => "allow", "count" => Enum.count(events), "events" => events}
               """,
               "input" => %{"event" => "reset"},
               "session" => %{
                 "model_id" => model_id,
                 "version" => version,
                 "session_id" => session_id,
                 "reset" => true
               }
             })

    assert reset["session"]["status"] == "reset"
    assert get_in(reset, ["result", "policy_result", "count"]) == 1
    assert get_in(reset, ["result", "policy_result", "events"]) == ["reset"]

    assert {:ok, keyed_first} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               events = [input["event"]]
               %{"action" => "allow", "count" => Enum.count(events), "events" => events}
               """,
               "input" => %{"event" => "tool-a-first"},
               "session" => %{
                 "model_id" => model_id,
                 "version" => version,
                 "session_id" => session_id,
                 "key" => "tool-a"
               }
             })

    assert keyed_first["session"]["status"] == "new"
    assert get_in(keyed_first, ["result", "policy_result", "events"]) == ["tool-a-first"]

    assert {:ok, keyed_second} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               events = [input["event"] | events]
               %{"action" => "allow", "count" => Enum.count(events), "events" => Enum.reverse(events)}
               """,
               "input" => %{"event" => "tool-a-second"},
               "session" => %{
                 "model_id" => model_id,
                 "version" => version,
                 "session_id" => session_id,
                 "key" => "tool-a"
               }
             })

    assert keyed_second["session"]["status"] == "reused"

    assert get_in(keyed_second, ["result", "policy_result", "events"]) == [
             "tool-a-first",
             "tool-a-second"
           ]

    assert {:ok, default_after_keyed} =
             DuneSnippetRegistry.evaluate(%{
               "source" => """
               events = [input["event"] | events]
               %{"action" => "allow", "count" => Enum.count(events), "events" => Enum.reverse(events)}
               """,
               "input" => %{"event" => "default-after-keyed"},
               "session" => %{
                 "model_id" => model_id,
                 "version" => version,
                 "session_id" => session_id
               }
             })

    assert default_after_keyed["session"]["key"] == "default"
    assert default_after_keyed["session"]["status"] == "reused"

    assert get_in(default_after_keyed, ["result", "policy_result", "events"]) == [
             "reset",
             "default-after-keyed"
           ]
  end

  test "stateful Dune snippet sessions reject malformed ttl configuration" do
    base_session = %{
      "model_id" => "test-model",
      "version" => "test-version",
      "session_id" => "test-session-#{System.unique_integer([:positive])}"
    }

    assert {:error, "session.ttl_ms must be a positive integer when provided."} =
             DuneSnippetRegistry.evaluate(%{
               "source" => "%{\"action\" => \"allow\"}",
               "session" => Map.put(base_session, "ttl_ms", "five minutes")
             })

    assert {:error, "session.ttl_ms must be a positive integer when provided."} =
             DuneSnippetRegistry.evaluate(%{
               "source" => "%{\"action\" => \"allow\"}",
               "session" => Map.put(base_session, "ttl_ms", 0)
             })

    assert {:error, "session.ttl_ms must be less than or equal to 3600000."} =
             DuneSnippetRegistry.evaluate(%{
               "source" => "%{\"action\" => \"allow\"}",
               "session" => Map.put(base_session, "ttl_ms", 3_600_001)
             })
  end
end
