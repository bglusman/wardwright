defmodule Wardwright.ModelSkyline.RuntimeTest do
  use ExUnit.Case, async: false

  alias Wardwright.ModelSkyline.Lease
  alias Wardwright.ModelSkyline.WorkUnit
  alias Wardwright.Runtime
  alias Wardwright.Runtime.ModelRuntime

  @now ~U[2026-08-31 12:00:00Z]

  test "runtime state retains only digests of the authenticated principal and caller scopes" do
    model_id = unique_model_id()
    version = "v1"
    principal_id = "key_content_free_record_id"
    run_id = "customer-run-id-that-must-not-be-retained"
    session_id = "customer-session-that-must-not-be-retained"
    work_unit = work_unit(principal_id, run_id, session_id)
    lease = lease(DateTime.add(@now, 3_600, :second), "first")

    assert {:ok, pid} = Runtime.ensure_model(model_id, version)

    assert {:ok, ^lease} =
             Runtime.put_model_skyline_pin(model_id, version, work_unit, lease, @now)

    state = :sys.get_state(pid)
    assert map_size(state.model_skyline_pins) == 1
    runtime_keys = inspect(Map.keys(state.model_skyline_pins))
    refute runtime_keys =~ principal_id
    refute runtime_keys =~ run_id
    refute runtime_keys =~ session_id
  end

  test "one principal cannot consume the global pin capacity" do
    model_id = unique_model_id()
    version = "v1"
    lease = lease(DateTime.add(@now, 3_600, :second), "bounded")

    Enum.each(1..64, fn slot ->
      unit = work_unit("key_principal_a", "run-#{slot}")
      assert {:ok, ^lease} = Runtime.put_model_skyline_pin(model_id, version, unit, lease, @now)
    end)

    assert {:error, :selection_principal_pin_capacity_exceeded} =
             Runtime.put_model_skyline_pin(
               model_id,
               version,
               work_unit("key_principal_a", "run-over-principal-cap"),
               lease,
               @now
             )

    assert {:ok, ^lease} =
             Runtime.put_model_skyline_pin(
               model_id,
               version,
               work_unit("key_principal_b", "run-b"),
               lease,
               @now
             )

    assert {:ok, pid} = Runtime.ensure_model(model_id, version)
    assert %{"model_skyline_pin_count" => 65} = ModelRuntime.status(pid, @now)
  end

  test "the model-version runtime enforces a global pin capacity" do
    model_id = unique_model_id()
    version = "v1"
    lease = lease(DateTime.add(@now, 3_600, :second), "global")

    Enum.each(1..16, fn principal ->
      Enum.each(1..64, fn slot ->
        unit = work_unit("key_principal_#{principal}", "run-#{slot}")
        assert {:ok, ^lease} = Runtime.put_model_skyline_pin(model_id, version, unit, lease, @now)
      end)
    end)

    assert {:error, :selection_pin_capacity_exceeded} =
             Runtime.put_model_skyline_pin(
               model_id,
               version,
               work_unit("key_principal_17", "run-over-global-cap"),
               lease,
               @now
             )

    assert {:ok, pid} = Runtime.ensure_model(model_id, version)
    assert %{"model_skyline_pin_count" => 1_024} = ModelRuntime.status(pid, @now)
  end

  test "valid_until prunes the old pin and makes the next request a fresh admission" do
    model_id = unique_model_id()
    version = "v1"
    work_unit = work_unit("key_principal", "expiring-run")
    expires_at = DateTime.add(@now, 10, :second)
    old_lease = lease(expires_at, "old")
    fresh_lease = lease(DateTime.add(expires_at, 3_600, :second), "fresh")

    assert {:ok, ^old_lease} =
             Runtime.put_model_skyline_pin(model_id, version, work_unit, old_lease, @now)

    assert :missing = Runtime.model_skyline_pin(model_id, version, work_unit, expires_at)

    assert {:ok, ^fresh_lease} =
             Runtime.put_model_skyline_pin(model_id, version, work_unit, fresh_lease, expires_at)

    assert {:ok, ^fresh_lease} =
             Runtime.model_skyline_pin(model_id, version, work_unit, expires_at)
  end

  defp unique_model_id do
    "model-skyline-runtime-#{System.unique_integer([:positive])}"
  end

  defp work_unit(principal_id, run_id, session_id \\ "session-a") do
    caller = %{
      "application_id" => %{"value" => "application-a"},
      "consuming_agent_id" => %{"value" => "agent-a"},
      "consuming_user_id" => %{"value" => "user-a"},
      "run_id" => %{"value" => run_id},
      "session_id" => %{"value" => session_id},
      "tenant_id" => %{"value" => "tenant-a"}
    }

    {:ok, work_unit} = WorkUnit.from_caller(principal_id, caller)
    work_unit
  end

  defp lease(valid_until, snapshot_id) do
    %Lease{
      frontier_id: "frontier-a",
      frontier_snapshot_id: String.duplicate("a", 64),
      local_revision_digest: String.duplicate("b", 64),
      ordered_offering_ids: ["provider/model@direct"],
      ordered_target_models: ["canned/model"],
      policy_hash: String.duplicate("c", 64),
      selection_id: "selection-a",
      snapshot_id: snapshot_id,
      valid_until: valid_until,
      workload: %{"id" => "coding", "unit" => "run", "version" => "v1"}
    }
  end
end
