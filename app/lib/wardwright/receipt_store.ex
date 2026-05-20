defmodule Wardwright.ReceiptStore do
  @moduledoc false

  use Agent

  alias Wardwright.Runtime.Events

  @contract_version "storage-contract-v0"
  @migration_version 1
  @decision_key "decision"
  @name_key "name"
  @namespace_key "namespace"
  @phase_key "phase"
  @primary_tool_key "primary_tool"
  @risk_class_key "risk_class"
  @source_key "source"
  @tool_call_id_key "tool_call_id"
  @tool_context_key "tool_context"
  @tool_name_key "tool_name"
  @tool_namespace_key "tool_namespace"
  @tool_phase_key "tool_phase"
  @tool_policy_status_key "tool_policy_status"
  @tool_risk_class_key "tool_risk_class"
  @tool_source_key "tool_source"
  @vcr_key "vcr"
  @vcr_mode_key "mode"
  @vcr_redaction_key "redaction"
  @vcr_schema_key "schema"

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  def insert(receipt) do
    :ok = persist_insert(current_storage(), receipt)

    Agent.update(__MODULE__, fn state ->
      put_in(state, [:receipts, receipt["receipt_id"]], receipt)
    end)

    Events.publish(Events.topic(:receipts), %{
      "created_at" => receipt["created_at"],
      "model_id" => receipt["model_id"],
      "model_version" => receipt["model_version"],
      "receipt_id" => receipt["receipt_id"],
      "run_id" => sourced_value(receipt, ["caller", "run_id"]) || receipt["run_id"],
      "session_id" => sourced_value(receipt, ["caller", "session_id"]),
      "simulation" => receipt["simulation"] || false,
      "status" => get_in(receipt, ["final", "status"]),
      "type" => "receipt.stored"
    })

    receipt
  end

  def list(filters \\ %{}, limit \\ 50) do
    limit = limit |> max(1) |> min(500)

    Agent.get(__MODULE__, fn state ->
      state.receipts
      |> Map.values()
      |> Enum.filter(&matches?(&1, filters))
      |> Enum.sort_by(&sort_key/1, :desc)
      |> Enum.take(limit)
      |> Enum.map(&summary/1)
    end)
  end

  def get(receipt_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.receipts, receipt_id)
    end)
  end

  def clear do
    :ok = persist_clear(current_storage())

    Agent.update(__MODULE__, fn state ->
      %{state | receipts: %{}}
    end)
  end

  def health do
    Agent.get(__MODULE__, fn state ->
      durable = state.storage == :file

      %{
        "capabilities" => %{
          "concurrent_writers" => durable,
          "durable" => durable,
          "event_replay" => true,
          "json_queries" => true,
          "retention_jobs" => false,
          "time_range_indexes" => durable,
          "transactional" => true
        },
        "contract_version" => @contract_version,
        "kind" => Atom.to_string(state.storage),
        "migration_version" => @migration_version,
        "path" => if(durable, do: Wardwright.ReceiptFileStore.store_dir()),
        "read_health" => "ok",
        "receipt_count" => map_size(state.receipts),
        "write_health" => "ok"
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end

  def metadata, do: health()

  def configure_storage(storage) when storage in [:memory, :file] do
    Agent.get_and_update(__MODULE__, fn _state ->
      {:ok, loaded} = load_state(storage)
      {{:ok, loaded}, loaded}
    end)
  end

  def summary(receipt) do
    tool_context = tool_context(receipt)
    primary_tool = primary_tool(tool_context)

    %{
      "application_id" => sourced_value(receipt, ["caller", "application_id"]),
      "caller" => receipt["caller"] || %{},
      "consuming_agent_id" => sourced_value(receipt, ["caller", "consuming_agent_id"]),
      "consuming_user_id" => sourced_value(receipt, ["caller", "consuming_user_id"]),
      "created_at" => receipt["created_at"],
      "model_id" => receipt["model_id"],
      "model_version" => receipt["model_version"],
      "receipt_id" => receipt["receipt_id"],
      "receipt_schema" => receipt["receipt_schema"],
      "run_id" => sourced_value(receipt, ["caller", "run_id"]) || receipt["run_id"],
      "selected_model" => get_in(receipt, ["decision", "selected_model"]),
      "selected_provider" => selected_provider(receipt),
      "session_id" => sourced_value(receipt, ["caller", "session_id"]),
      "simulation" => receipt["simulation"] || false,
      "status" => get_in(receipt, ["final", "status"]),
      "stream_policy_action" => get_in(receipt, ["final", "stream_policy_action"]),
      "tenant_id" => sourced_value(receipt, ["caller", "tenant_id"])
    }
    |> put_if_present("vcr", vcr_summary(receipt))
    |> put_if_present(@tool_namespace_key, Map.get(primary_tool, @namespace_key))
    |> put_if_present(@tool_name_key, Map.get(primary_tool, @name_key))
    |> put_if_present(@tool_phase_key, Map.get(tool_context, @phase_key))
    |> put_if_present(@tool_risk_class_key, Map.get(primary_tool, @risk_class_key))
    |> put_if_present(@tool_source_key, Map.get(primary_tool, @source_key))
    |> put_if_present(@tool_call_id_key, Map.get(tool_context, @tool_call_id_key))
    |> put_if_present(
      @tool_policy_status_key,
      get_in(receipt, ["final", "tool_policy", "status"])
    )
  end

  defp matches?(receipt, filters) do
    summary = summary(receipt)

    Enum.all?(filters, fn
      {"model", value} ->
        case Wardwright.normalize_model(value) do
          {:ok, model} -> summary["model_id"] == model
          _ -> false
        end

      {"created_at_min", value} ->
        compare_int(summary["created_at"], value, &>=/2)

      {"created_at_max", value} ->
        compare_int(summary["created_at"], value, &<=/2)

      {"simulation", value} ->
        boolean_value(value) == summary["simulation"]

      {key, value}
      when key in [
             "tenant_id",
             "application_id",
             "consuming_agent_id",
             "consuming_user_id",
             "session_id",
             "run_id",
             "model_id",
             "model_version",
             "selected_provider",
             "selected_model",
             "status",
             "stream_policy_action",
             @tool_namespace_key,
             @tool_name_key,
             @tool_phase_key,
             @tool_policy_status_key,
             @tool_risk_class_key,
             @tool_source_key,
             @tool_call_id_key
           ] ->
        summary[key] == value

      {_key, ""} ->
        true

      {_key, _value} ->
        true
    end)
  end

  defp sourced_value(receipt, path) do
    receipt
    |> get_in(path)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp selected_provider(receipt) do
    get_in(receipt, ["decision", "selected_provider"]) ||
      get_in(receipt, ["decision", "selected_model"]) |> provider_from_model()
  end

  defp tool_context(receipt) when is_map(receipt) do
    case get_in(receipt, [@decision_key, @tool_context_key]) do
      context when is_map(context) -> context
      _context -> %{}
    end
  end

  defp primary_tool(tool_context) when is_map(tool_context) do
    case Map.get(tool_context, @primary_tool_key) do
      tool when is_map(tool) -> tool
      _tool -> %{}
    end
  end

  defp provider_from_model(model) when is_binary(model) do
    model |> String.split("/", parts: 2) |> List.first()
  end

  defp provider_from_model(_), do: nil

  defp sort_key(receipt), do: {receipt["created_at"] || 0, receipt["receipt_id"] || ""}

  defp compare_int(left, right, comparator) when is_integer(left) do
    case integer_value(right) do
      nil -> false
      value -> comparator.(left, value)
    end
  end

  defp compare_int(_left, _right, _comparator), do: false

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp integer_value(_), do: nil

  defp boolean_value(value) when is_boolean(value), do: value
  defp boolean_value("true"), do: true
  defp boolean_value("false"), do: false
  defp boolean_value(_), do: nil

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp vcr_summary(%{@vcr_key => %{} = vcr}) do
    %{
      @vcr_mode_key => Map.get(vcr, @vcr_mode_key),
      @vcr_redaction_key => Map.get(vcr, @vcr_redaction_key),
      @vcr_schema_key => Map.get(vcr, @vcr_schema_key)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
    |> case do
      empty when map_size(empty) == 0 -> nil
      summary -> summary
    end
  end

  defp vcr_summary(_receipt), do: nil

  defp initial_state do
    storage =
      case Wardwright.ReceiptFileStore.enabled?() do
        true -> :file
        false -> :memory
      end

    {:ok, state} = load_state(storage)
    state
  end

  defp load_state(:memory), do: {:ok, %{receipts: %{}, storage: :memory}}

  defp load_state(:file) do
    case Wardwright.ReceiptFileStore.list_receipts() do
      {:ok, receipts} -> {:ok, %{receipts: Map.new(receipts, &{&1["receipt_id"], &1}), storage: :file}}
    end
  end

  defp current_storage do
    Agent.get(__MODULE__, & &1.storage)
  end

  defp persist_insert(:memory, _receipt), do: :ok
  defp persist_insert(:file, receipt), do: storage_result(Wardwright.ReceiptFileStore.insert_receipt(receipt))

  defp persist_clear(:memory), do: :ok
  defp persist_clear(:file), do: storage_result(Wardwright.ReceiptFileStore.clear_receipts())

  defp storage_result({:ok, :ok}), do: :ok
  defp storage_result({:error, reason}), do: raise("receipt store failed: #{inspect(reason)}")
end
