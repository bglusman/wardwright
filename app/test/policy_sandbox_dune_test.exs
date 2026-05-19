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
             "stdio" => "",
             "value" => %{"action" => "restrict_routes", "allowed_targets" => ["local"]}
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
      assert %{"message" => message, "reason" => reason, "status" => "error"} =
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

    assert %{"reason" => "reductions", "status" => "error"} = result
  end

  test "memory limit stops large allocations" do
    result =
      DuneSandbox.eval_string(
        "List.duplicate(\"policy-event\", 100_000)",
        max_heap_size: 4_000,
        timeout: 1_000
      )

    assert %{"reason" => "memory", "status" => "error"} = result
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

    assert %{"reason" => reason, "status" => "error"} = result
    assert reason in ["timeout", "reductions"]
  end

  test "registry snippets are inspectable and evaluate against example inputs" do
    registry = DuneSnippetRegistry.list()

    assert registry["schema"] == "wardwright.dune_snippet_registry.v1"
    assert Enum.count(registry["data"]) >= 4

    assert %{
             "example_input" => example_input,
             "id" => "history.related-secret-ladder",
             "source" => source
           } =
             Enum.find(registry["data"], &(&1["id"] == "history.related-secret-ladder"))

    assert source =~ "transition_state"

    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "input" => example_input,
               "snippet_id" => "history.related-secret-ladder"
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
               "input" => %{
                 "request_text" => "please deny me but keep notes",
                 "rules" => [
                   %{"action" => "block", "contains" => "deny me", "id" => "legacy-deny"},
                   %{"action" => "annotate", "contains" => "not present", "id" => "legacy-miss"},
                   %{"action" => "block", "contains" => 123, "id" => "legacy-malformed"}
                 ]
               },
               "snippet_id" => "primitive.request-contains-actions"
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "block"

    assert [
             %{
               "action" => "block",
               "matched" => true,
               "rule_id" => "legacy-deny"
             }
           ] = get_in(evaluation, ["result", "policy_result", "actions"])
  end

  test "request rule snippet preserves action metadata for host-side effects" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{
                 "request_text" => "Please return JSON for downstream automation.",
                 "rule" => %{
                   "action" => "inject_reminder_and_retry",
                   "id" => "json-reminder",
                   "kind" => "request_transform",
                   "message" => "request needs JSON guidance",
                   "regex" => "return\\s+json",
                   "reminder" => "Return only valid JSON.",
                   "severity" => "warning"
                 }
               },
               "snippet_id" => "primitive.request-rule-action"
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"

    assert get_in(evaluation, ["result", "policy_result", "action"]) ==
             "inject_reminder_and_retry"

    assert [
             %{
               "action" => "inject_reminder_and_retry",
               "kind" => "request_transform",
               "match" => %{"contains" => false, "regex" => true},
               "matched" => true,
               "reminder" => "Return only valid JSON.",
               "rule_id" => "json-reminder",
               "severity" => "warning"
             }
           ] = get_in(evaluation, ["result", "policy_result", "actions"])
  end

  test "request rule snippet treats invalid regexes as non-matches" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{
                 "request_text" => "please block",
                 "rule" => %{"action" => "block", "id" => "bad-regex", "kind" => "request_guard", "regex" => "["}
               },
               "snippet_id" => "primitive.request-rule-action"
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "allow"
    assert get_in(evaluation, ["result", "policy_result", "actions"]) == []
  end

  test "request rule snippet preserves metadata-compatible contains matching" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{
                 "request_text" => "Find account 4938 before routing.",
                 "rule" => %{
                   "action" => "block",
                   "contains" => 4938,
                   "id" => "numeric-account",
                   "kind" => "request_guard"
                 }
               },
               "snippet_id" => "primitive.request-rule-action"
             })

    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "block"

    assert [%{"match" => %{"contains" => true}, "rule_id" => "numeric-account"}] =
             get_in(evaluation, ["result", "policy_result", "actions"])
  end

  test "ad hoc snippets can be tested and malformed results fail closed" do
    assert {:ok, evaluation} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{"approved" => false},
               "source" => """
               if input["approved"] do
                 %{"action" => "allow", "reason" => "approved"}
               else
                 %{"action" => "require_review", "reason" => "missing approval"}
               end
               """
             })

    assert get_in(evaluation, ["result", "policy_result", "action"]) == "require_review"

    assert {:ok, malformed} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{},
               "source" => "\"not a policy result\""
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
               "input" => %{"event" => "first"},
               "session" => %{
                 "model_id" => model_id,
                 "session_id" => session_id,
                 "ttl_ms" => 60_000,
                 "version" => version
               },
               "source" => """
               events = [input["event"]]

               %{
                 "action" => "allow",
                 "count" => Enum.count(events),
                 "events" => events
               }
               """
             })

    assert first["session"] == %{
             "key" => "default",
             "model_id" => model_id,
             "reused" => false,
             "session_id" => session_id,
             "status" => "new",
             "ttl_ms" => 60_000,
             "version" => version
           }

    assert get_in(first, ["result", "policy_result", "count"]) == 1

    assert {:ok, second} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{"event" => "second"},
               "session" => %{
                 "model_id" => model_id,
                 "session_id" => session_id,
                 "ttl_ms" => 60_000,
                 "version" => version
               },
               "source" => """
               events = [input["event"] | events]

               %{
                 "action" => "allow",
                 "count" => Enum.count(events),
                 "events" => Enum.reverse(events)
               }
               """
             })

    assert second["session"]["status"] == "reused"
    assert get_in(second, ["result", "policy_result", "count"]) == 2
    assert get_in(second, ["result", "policy_result", "events"]) == ["first", "second"]

    assert {:ok, reset} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{"event" => "reset"},
               "session" => %{"model_id" => model_id, "reset" => true, "session_id" => session_id, "version" => version},
               "source" => """
               events = [input["event"]]
               %{"action" => "allow", "count" => Enum.count(events), "events" => events}
               """
             })

    assert reset["session"]["status"] == "reset"
    assert get_in(reset, ["result", "policy_result", "count"]) == 1
    assert get_in(reset, ["result", "policy_result", "events"]) == ["reset"]

    assert {:ok, keyed_first} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{"event" => "tool-a-first"},
               "session" => %{
                 "key" => "tool-a",
                 "model_id" => model_id,
                 "session_id" => session_id,
                 "version" => version
               },
               "source" => """
               events = [input["event"]]
               %{"action" => "allow", "count" => Enum.count(events), "events" => events}
               """
             })

    assert keyed_first["session"]["status"] == "new"
    assert get_in(keyed_first, ["result", "policy_result", "events"]) == ["tool-a-first"]

    assert {:ok, keyed_second} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{"event" => "tool-a-second"},
               "session" => %{
                 "key" => "tool-a",
                 "model_id" => model_id,
                 "session_id" => session_id,
                 "version" => version
               },
               "source" => """
               events = [input["event"] | events]
               %{"action" => "allow", "count" => Enum.count(events), "events" => Enum.reverse(events)}
               """
             })

    assert keyed_second["session"]["status"] == "reused"

    assert get_in(keyed_second, ["result", "policy_result", "events"]) == [
             "tool-a-first",
             "tool-a-second"
           ]

    assert {:ok, default_after_keyed} =
             DuneSnippetRegistry.evaluate(%{
               "input" => %{"event" => "default-after-keyed"},
               "session" => %{"model_id" => model_id, "session_id" => session_id, "version" => version},
               "source" => """
               events = [input["event"] | events]
               %{"action" => "allow", "count" => Enum.count(events), "events" => Enum.reverse(events)}
               """
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
      "session_id" => "test-session-#{System.unique_integer([:positive])}",
      "version" => "test-version"
    }

    assert {:error, "session.ttl_ms must be a positive integer when provided."} =
             DuneSnippetRegistry.evaluate(%{
               "session" => Map.put(base_session, "ttl_ms", "five minutes"),
               "source" => ~s(%{"action" => "allow"})
             })

    assert {:error, "session.ttl_ms must be a positive integer when provided."} =
             DuneSnippetRegistry.evaluate(%{
               "session" => Map.put(base_session, "ttl_ms", 0),
               "source" => ~s(%{"action" => "allow"})
             })

    assert {:error, "session.ttl_ms must be less than or equal to 3600000."} =
             DuneSnippetRegistry.evaluate(%{
               "session" => Map.put(base_session, "ttl_ms", 3_600_001),
               "source" => ~s(%{"action" => "allow"})
             })
  end
end
