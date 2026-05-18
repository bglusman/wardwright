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
    assert Enum.count(registry["data"]) >= 3

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
    assert get_in(evaluation, ["result", "policy_status"]) == "ok"
    assert get_in(evaluation, ["result", "policy_result", "action"]) == "transition_state"
    assert get_in(evaluation, ["result", "policy_result", "to_state"]) == "review_required"
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
end
