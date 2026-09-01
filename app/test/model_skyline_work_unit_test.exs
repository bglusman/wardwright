defmodule Wardwright.ModelSkyline.WorkUnitTest do
  use Wardwright.RouterCase

  alias Wardwright.ModelSkyline
  alias Wardwright.ModelSkyline.CanonicalJson
  alias Wardwright.ModelSkyline.WorkUnit
  alias Wardwright.Runtime.ModelRuntime

  @fixture_a Path.expand("fixtures/model_skyline/selection-a.json", __DIR__)
  @fixture_b Path.expand("fixtures/model_skyline/selection-b.json", __DIR__)
  @verification_time ~U[2026-08-31 12:30:00Z]

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wardwright-model-skyline-work-unit-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    %{directory: directory}
  end

  test "loads once at work-unit admission and pins the ordered targets by run_id", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, _model_id} = install_config(path)

    assert {:error, :missing_run_id} = WorkUnit.from_caller("key_principal", caller(nil))

    assert {:error, :invalid_run_id} =
             WorkUnit.from_caller("key_principal", caller(String.duplicate("x", 513)))

    assert {:ok, routed_a, lease_a} =
             ModelSkyline.route_config(config, work_unit("run-a"), now: @verification_time)

    assert Enum.map(routed_a["targets"], & &1["model"]) == [
             "canned/primary",
             "canned/fallback"
           ]

    assert %{
             route_type: "cascade",
             selected_model: "canned/primary",
             selected_models: ["canned/primary", "canned/fallback"]
           } = Wardwright.select_route(routed_a, 16, %{})

    File.cp!(@fixture_b, path)

    assert {:ok, _same_run_config, same_run_lease} =
             ModelSkyline.route_config(config, work_unit("run-a"), now: @verification_time)

    assert same_run_lease.snapshot_id == lease_a.snapshot_id
    assert same_run_lease.ordered_target_models == ["canned/primary", "canned/fallback"]

    assert {:ok, _new_run_config, new_run_lease} =
             ModelSkyline.route_config(config, work_unit("run-b"), now: @verification_time)

    assert new_run_lease.snapshot_id != lease_a.snapshot_id
    assert new_run_lease.ordered_target_models == ["canned/fallback", "canned/primary"]
  end

  test "the authenticated API-key principal isolates otherwise identical work units", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, model_id} = install_config(path)
    {:ok, key_a} = Wardwright.ModelApiKeyStore.create(model_id, "principal-a")
    {:ok, key_b} = Wardwright.ModelApiKeyStore.create(model_id, "principal-b")

    unit_a = work_unit("shared-run", key_a["id"])
    unit_b = work_unit("shared-run", key_b["id"])

    assert {:ok, _routed, lease_a} =
             ModelSkyline.route_config(config, unit_a, now: @verification_time)

    File.cp!(@fixture_b, path)

    assert {:ok, _routed, lease_b} =
             ModelSkyline.route_config(config, unit_b, now: @verification_time)

    assert lease_b.snapshot_id != lease_a.snapshot_id

    assert {:ok, _routed, pinned_a} =
             ModelSkyline.route_config(config, unit_a, now: @verification_time)

    assert pinned_a.snapshot_id == lease_a.snapshot_id
  end

  test "tenant scope isolates identical runs for the same authenticated principal", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, _model_id} = install_config(path)

    unit_a = work_unit("shared-run", "shared-principal", "tenant-a")
    unit_b = work_unit("shared-run", "shared-principal", "tenant-b")

    assert {:ok, _routed, lease_a} =
             ModelSkyline.route_config(config, unit_a, now: @verification_time)

    File.cp!(@fixture_b, path)

    assert {:ok, _routed, lease_b} =
             ModelSkyline.route_config(config, unit_b, now: @verification_time)

    assert lease_b.snapshot_id != lease_a.snapshot_id

    assert {:ok, _routed, pinned_a} =
             ModelSkyline.route_config(config, unit_a, now: @verification_time)

    assert pinned_a.snapshot_id == lease_a.snapshot_id
  end

  test "local mutation fails closed, while expiry ends the pin and permits fresh admission", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, _model_id} = install_config(path)

    assert {:ok, _routed, _lease} =
             ModelSkyline.route_config(config, work_unit("run-expiry"), now: @verification_time)

    changed_config =
      update_in(config, ["targets"], fn [first | rest] ->
        [Map.update!(first, "context_window", &(&1 + 1)) | rest]
      end)

    assert {:error, :local_target_changed} =
             ModelSkyline.route_config(changed_config, work_unit("run-expiry"), now: @verification_time)

    assert {:error, :expired_selection} =
             ModelSkyline.route_config(config, work_unit("run-expiry"), now: ~U[2026-08-31 13:00:00Z])

    write_snapshot_at(
      path,
      @fixture_b,
      ~U[2026-08-31 12:59:00Z],
      ~U[2026-08-31 14:00:00Z]
    )

    assert {:ok, _routed, fresh_lease} =
             ModelSkyline.route_config(config, work_unit("run-expiry"), now: ~U[2026-08-31 13:00:00Z])

    assert fresh_lease.ordered_target_models == ["canned/fallback", "canned/primary"]
  end

  test "a pinned run survives source damage while a new run fails closed", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, _model_id} = install_config(path)

    assert {:ok, _routed, admitted} =
             ModelSkyline.route_config(config, work_unit("run-admitted"), now: @verification_time)

    File.write!(path, ~s({"not":"a selection"}))

    assert {:ok, _routed, pinned} =
             ModelSkyline.route_config(config, work_unit("run-admitted"), now: @verification_time)

    assert pinned.snapshot_id == admitted.snapshot_id

    assert {:error, :invalid_selection} =
             ModelSkyline.route_config(config, work_unit("run-new"), now: @verification_time)
  end

  test "requires the complete offering binding, not only a matching offering_id", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)

    mutate = fn skyline ->
      update_in(skyline, ["bindings", Access.at(0), "offering", "provider"], fn _provider ->
        "lookalike-provider"
      end)
    end

    {config, _model_id} = install_config(path, mutate)

    assert {:error, :selection_binding_mismatch} =
             ModelSkyline.route_config(config, work_unit("run-binding"), now: @verification_time)
  end

  test "concurrent admission gives every caller the same immutable lease", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, _model_id} = install_config(path)

    leases =
      1..16
      |> Task.async_stream(
        fn _index ->
          ModelSkyline.route_config(config, work_unit("run-concurrent"), now: @verification_time)
        end,
        max_concurrency: 16,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, _routed, lease}} -> lease end)

    assert length(leases) == 16
    assert leases |> Enum.map(& &1.snapshot_id) |> Enum.uniq() == [hd(leases).snapshot_id]

    assert leases |> Enum.map(& &1.ordered_target_models) |> Enum.uniq() == [
             ["canned/primary", "canned/fallback"]
           ]
  end

  test "router fails closed without a run_id and emits content-free selection receipt metadata",
       %{
         directory: directory
       } do
    path = Path.join(directory, "selection.json")
    snapshot_id = write_fresh_snapshot(path)
    {_config, model_id} = install_config(path)

    missing_key =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "hello", role: "user"}],
        model: model_id
      })

    assert missing_key.status == 401
    {:ok, api_key} = Wardwright.ModelApiKeyStore.create(model_id, "test-client")
    auth = {"authorization", "Bearer #{api_key["key"]}"}

    blocked =
      call(
        :post,
        "/v1/chat/completions",
        %{messages: [%{content: "hello", role: "user"}], model: model_id},
        [auth]
      )

    assert blocked.status == 429
    blocked_receipt = receipt_for(blocked)

    assert get_in(blocked_receipt, ["decision", "model_skyline", "error_code"]) ==
             "missing_run_id"

    admitted =
      call(
        :post,
        "/v1/chat/completions",
        %{messages: [%{content: "hello", role: "user"}], model: model_id},
        [auth, {"x-wardwright-run-id", "receipt-run-secret"}]
      )

    assert admitted.status == 200

    assert JSON.decode!(admitted.resp_body)["choices"] |> hd() |> get_in(["message", "content"]) ==
             "primary"

    receipt = receipt_for(admitted)
    metadata = get_in(receipt, ["decision", "model_skyline"])

    assert metadata["snapshot_id"] == snapshot_id
    assert metadata["selection_id"] == "coding-agent-defaults"

    assert metadata["ordered_offering_ids"] == [
             "openai/gpt-5.4@direct-us",
             "anthropic/claude-fable-5@direct-us"
           ]

    refute Map.has_key?(metadata, "run_id")
    refute Map.has_key?(metadata, "selection_path")
    refute inspect(metadata) =~ directory
    refute inspect(metadata) =~ "receipt-run-secret"
  end

  test "protected simulation resolves a read-only preview without an API key or pin", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    snapshot_id = write_fresh_snapshot(path)
    {config, model_id} = install_config(path)

    simulated =
      call(:post, "/v1/wardwright/simulate", %{
        model: model_id,
        request: %{messages: [%{content: "hello", role: "user"}]}
      })

    assert simulated.status == 200
    receipt = simulated.resp_body |> JSON.decode!() |> Map.fetch!("receipt")
    metadata = get_in(receipt, ["decision", "model_skyline"])
    assert metadata["snapshot_id"] == snapshot_id
    assert metadata["status"] == "preview_unpinned"
    assert metadata["pin_scope"] == "none"
    assert pin_count(model_id, config["version"]) == 0
  end

  test "a request already failed closed by policy resolves only a preview and never pins", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    write_fresh_snapshot(path)
    {config, model_id} = install_config(path)

    blocked_config =
      config
      |> Map.put("alert_delivery", %{"capacity" => 0, "on_full" => "fail_closed"})
      |> Map.put("governance", [
        %{
          "action" => "alert_async",
          "contains" => "alert me",
          "id" => "always-alert",
          "kind" => "request_guard",
          "message" => "alert queue full"
        }
      ])

    assert {:ok, _normalized} = Wardwright.put_config(blocked_config)
    {:ok, api_key} = Wardwright.ModelApiKeyStore.create(model_id, "policy-client")

    blocked =
      call(
        :post,
        "/v1/chat/completions",
        %{messages: [%{content: "alert me", role: "user"}], model: model_id},
        [{"authorization", "Bearer #{api_key["key"]}"}]
      )

    assert blocked.status == 429
    metadata = blocked |> receipt_for() |> get_in(["decision", "model_skyline"])
    assert metadata["status"] == "preview_unpinned"
    assert metadata["pin_scope"] == "none"
    assert pin_count(model_id, config["version"]) == 0
  end

  test "configuration rejects ModelSkyline when model API keys are disabled", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture_a, path)
    {config, _model_id} = install_config(path)
    unkeyed_config = Map.put(config, "requires_api_key", false)

    assert {:error, message} = Wardwright.put_config(unkeyed_config)
    assert message =~ "model_skyline requires model API keys"
  end

  defp install_config(path, mutate_skyline \\ &Function.identity/1) do
    document = JSON.decode!(File.read!(@fixture_a))
    suffix = System.unique_integer([:positive])
    model_id = "model-skyline-test-#{suffix}"

    skyline =
      %{
        "bindings" => [
          %{
            "offering" => document["default"]["offering"],
            "target_model" => "canned/primary"
          },
          %{
            "offering" => hd(document["fallbacks"])["offering"],
            "target_model" => "canned/fallback"
          }
        ],
        "expected_frontier_id" => "coding-value",
        "expected_selection_id" => "coding-agent-defaults",
        "expected_workload" => %{
          "id" => "coding-session",
          "unit" => "completed_session",
          "version" => "v1"
        },
        "selection_path" => path
      }
      |> mutate_skyline.()

    config = %{
      "cascades" => [
        %{
          "id" => "configured-route",
          "models" => ["canned/outside", "canned/primary", "canned/fallback"]
        }
      ],
      "model_id" => model_id,
      "model_skyline" => skyline,
      "requires_api_key" => true,
      "route_root" => "configured-route",
      "targets" => [
        %{
          "canned_outputs" => ["outside"],
          "context_window" => 4_096,
          "model" => "canned/outside",
          "provider_kind" => "canned_sequence"
        },
        %{
          "canned_outputs" => ["primary"],
          "context_window" => 4_096,
          "model" => "canned/primary",
          "provider_kind" => "canned_sequence"
        },
        %{
          "canned_outputs" => ["fallback"],
          "context_window" => 4_096,
          "model" => "canned/fallback",
          "provider_kind" => "canned_sequence"
        }
      ],
      "version" => "v1-#{suffix}"
    }

    assert {:ok, normalized} = Wardwright.put_config(config)
    {normalized, model_id}
  end

  defp write_fresh_snapshot(path) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    write_snapshot_at(
      path,
      @fixture_a,
      DateTime.add(now, -60, :second),
      DateTime.add(now, 3_600, :second)
    )
  end

  defp write_snapshot_at(path, fixture, generated_at, valid_until) do
    {:ok, document} = fixture |> File.read!() |> CanonicalJson.decode()

    document =
      document
      |> Map.put("generated_at", DateTime.to_iso8601(generated_at))
      |> Map.put("valid_until", DateTime.to_iso8601(valid_until))

    stable_payload =
      document
      |> Map.delete("snapshot_id")
      |> Map.update!("default", &without_null_billing_mode/1)
      |> Map.update!(
        "fallbacks",
        &Enum.map(&1, fn choice -> without_null_billing_mode(choice) end)
      )

    {:ok, snapshot_id} = CanonicalJson.sha256(stable_payload)
    File.write!(path, JSON.encode!(Map.put(document, "snapshot_id", snapshot_id)))
    snapshot_id
  end

  defp without_null_billing_mode(choice) do
    update_in(choice, ["offering"], fn offering ->
      if is_nil(offering["billing_mode"]),
        do: Map.delete(offering, "billing_mode"),
        else: offering
    end)
  end

  defp receipt_for(conn) do
    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    Wardwright.ReceiptStore.get(receipt_id)
  end

  defp pin_count(model_id, version) do
    {:ok, pid} = Wardwright.Runtime.ensure_model(model_id, version)
    ModelRuntime.status(pid)["model_skyline_pin_count"]
  end

  defp work_unit(run_id, principal_id \\ "key_principal", tenant_id \\ "tenant-a") do
    {:ok, work_unit} = WorkUnit.from_caller(principal_id, caller(run_id, tenant_id))
    work_unit
  end

  defp caller(run_id, tenant_id \\ "tenant-a")

  defp caller(nil, _tenant_id), do: %{}

  defp caller(run_id, tenant_id) do
    %{
      "run_id" => %{"source" => "header", "value" => run_id},
      "session_id" => %{"source" => "header", "value" => "session-a"},
      "tenant_id" => %{"source" => "header", "value" => tenant_id}
    }
  end
end
