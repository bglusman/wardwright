defmodule Wardwright.GleamStateMachineCoreTest do
  use ExUnit.Case, async: true

  @transitions [
    {"draft", "submit", "reviewing", "state_transition", "submit-for-review"},
    {"reviewing", "approve", "approved", "state_transition", "approve-release"},
    {"reviewing", "request_changes", "draft", "state_transition", "request-changes"}
  ]

  test "simulates policy-declared state transitions in event order" do
    assert {"ok", "approved", steps} =
             :wardwright@state_machine_core.simulate("draft", @transitions, [
               "submit",
               "approve"
             ])

    assert steps == [
             {"draft", "submit", "reviewing", "state_transition", "submit-for-review", true},
             {"reviewing", "approve", "approved", "state_transition", "approve-release", true}
           ]
  end

  test "records unmatched events without changing the active state" do
    assert {"ok", "reviewing", steps} =
             :wardwright@state_machine_core.simulate("draft", @transitions, [
               "submit",
               "archive"
             ])

    assert steps == [
             {"draft", "submit", "reviewing", "state_transition", "submit-for-review", true},
             {"reviewing", "archive", "reviewing", "no_op", "", false}
           ]
  end

  test "rejects transition tables that cannot describe a deterministic machine" do
    assert {"ok", 3} =
             :wardwright@state_machine_core.transition_table_status("draft", @transitions)

    assert {"empty_transition_table", 0} =
             :wardwright@state_machine_core.transition_table_status("draft", [])

    assert {"blank_initial_state", "", []} =
             :wardwright@state_machine_core.simulate("", @transitions, ["submit"])

    assert {"empty_transition_field:rule_id", 0} =
             :wardwright@state_machine_core.transition_table_status("draft", [
               {"draft", "submit", "reviewing", "state_transition", ""}
             ])

    assert {"duplicate_transition:draft:submit", 0} =
             :wardwright@state_machine_core.transition_table_status("draft", [
               {"draft", "submit", "reviewing", "state_transition", "submit-for-review"},
               {"draft", "submit", "approved", "state_transition", "skip-review"}
             ])
  end
end
