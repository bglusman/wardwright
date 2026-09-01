defmodule Wardwright.ModelSkyline do
  @moduledoc false

  alias Wardwright.ModelGraph
  alias Wardwright.ModelSkyline.SelectionSnapshot
  alias Wardwright.ModelSkyline.Source
  alias Wardwright.ModelSkyline.WorkUnit

  @route_id "model_skyline.pinned_selection"
  @pin_scope "authenticated_principal+caller_scopes"
  @max_bindings 64
  @config_keys ~w(bindings expected_frontier_id expected_selection_id expected_workload selection_path)
  @binding_keys ~w(offering target_model)
  @workload_keys ~w(id unit version)

  defmodule Lease do
    @moduledoc false

    @enforce_keys [
      :frontier_id,
      :frontier_snapshot_id,
      :local_revision_digest,
      :ordered_offering_ids,
      :ordered_target_models,
      :policy_hash,
      :selection_id,
      :snapshot_id,
      :valid_until,
      :workload
    ]
    defstruct [
      :frontier_id,
      :frontier_snapshot_id,
      :local_revision_digest,
      :ordered_offering_ids,
      :ordered_target_models,
      :policy_hash,
      :selection_id,
      :snapshot_id,
      :valid_until,
      :workload
    ]

    @type t :: %__MODULE__{
            frontier_id: String.t(),
            frontier_snapshot_id: String.t(),
            local_revision_digest: String.t(),
            ordered_offering_ids: [String.t()],
            ordered_target_models: [String.t()],
            policy_hash: String.t(),
            selection_id: String.t(),
            snapshot_id: String.t(),
            valid_until: DateTime.t(),
            workload: map()
          }
  end

  @type reason ::
          SelectionSnapshot.reason()
          | Source.reason()
          | :invalid_model_skyline_config
          | :invalid_run_id
          | :local_target_changed
          | :missing_run_id
          | :model_skyline_runtime_unavailable
          | :selection_binding_mismatch
          | :selection_pin_capacity_exceeded
          | :selection_principal_pin_capacity_exceeded
          | WorkUnit.reason()

  @spec configured?(map()) :: boolean()
  def configured?(config) when is_map(config), do: is_map(Map.get(config, "model_skyline"))

  @spec work_unit(map(), term(), map(), :admit | :preview) ::
          {:ok, WorkUnit.t() | nil} | {:error, WorkUnit.reason()}
  def work_unit(config, principal_id, caller, mode) when is_map(config) and is_map(caller) do
    cond do
      not configured?(config) -> {:ok, nil}
      mode == :preview -> {:ok, nil}
      true -> WorkUnit.from_caller(principal_id, caller)
    end
  end

  @spec validate_config(term(), map()) :: :ok | {:error, String.t()}
  def validate_config(nil, _wardwright_config), do: :ok

  def validate_config(selection_config, wardwright_config)
      when is_map(selection_config) and is_map(wardwright_config) do
    with :ok <- exact_keys(selection_config, @config_keys),
         true <- wardwright_config["requires_api_key"] == true,
         :ok <- validate_source_path(selection_config["selection_path"]),
         :ok <- validate_expected(selection_config),
         :ok <- validate_bindings(selection_config["bindings"], wardwright_config) do
      :ok
    else
      _reason ->
        {:error,
         "model_skyline requires model API keys, an absolute local-file path, exact expected IDs, full offering bindings, and distinct direct targets"}
    end
  end

  def validate_config(_selection_config, _wardwright_config) do
    {:error, "model_skyline must be a JSON object when configured"}
  end

  @spec route_config(map(), WorkUnit.t() | nil, keyword()) ::
          {:ok, map(), Lease.t() | nil} | {:error, reason()}
  def route_config(config, work_unit, opts \\ []) when is_map(config) do
    route_config(config, work_unit, :admit, opts)
  end

  @spec preview_config(map(), WorkUnit.t() | nil, keyword()) ::
          {:ok, map(), Lease.t() | nil} | {:error, reason()}
  def preview_config(config, work_unit, opts \\ []) when is_map(config) do
    route_config(config, work_unit, :preview, opts)
  end

  defp route_config(config, work_unit, mode, opts) do
    case Map.get(config, "model_skyline") do
      nil ->
        {:ok, config, nil}

      selection_config ->
        now = Keyword.get(opts, :now, DateTime.utc_now())

        with :ok <- runtime_work_unit(work_unit, mode),
             :ok <- runtime_config(selection_config, config),
             local_revision_digest = local_revision_digest(selection_config, config),
             {:ok, lease} <-
               selected_lease(
                 config,
                 selection_config,
                 work_unit,
                 local_revision_digest,
                 now,
                 mode
               ),
             :ok <- validate_pinned_lease(lease, local_revision_digest, now),
             {:ok, routed_config} <- overlay_route(config, lease) do
          {:ok, routed_config, lease}
        end
    end
  end

  @spec decorate_decision(map(), Lease.t() | nil) :: map()
  def decorate_decision(decision, lease, status \\ :pinned)

  def decorate_decision(decision, nil, _status), do: decision

  def decorate_decision(decision, %Lease{} = lease, status) when status in [:pinned, :preview_unpinned] do
    Map.put(decision, :model_skyline, receipt_metadata(lease, status))
  end

  @spec blocked_decision(non_neg_integer(), map(), reason(), :admit | :preview) :: map()
  def blocked_decision(estimated_prompt_tokens, policy_route_constraints, reason, mode \\ :admit) do
    code = error_code(reason)

    %{
      combine_strategy: "model_skyline_fail_closed",
      estimated_prompt_tokens: max(1, estimated_prompt_tokens),
      fallback_models: [],
      fallback_used: false,
      model_skyline: %{
        "error_code" => code,
        "pin_scope" => blocked_pin_scope(mode),
        "status" => "blocked"
      },
      policy_route_constraints: policy_route_constraints,
      reason: "ModelSkyline selection admission failed closed (#{code})",
      route_blocked: true,
      route_id: @route_id,
      route_lineage: [],
      route_type: "model_skyline",
      rule: "admit one verified local SelectionSnapshot per authenticated work unit",
      selected_context_window: nil,
      selected_model: "unconfigured/no-target",
      selected_models: [],
      selected_provider: "unconfigured",
      skipped: []
    }
  end

  defp selected_lease(config, selection_config, work_unit, local_revision_digest, now, :admit) do
    model_id = Wardwright.model_id(config)
    version = config["version"]

    case Wardwright.Runtime.model_skyline_pin(model_id, version, work_unit, now) do
      {:ok, %Lease{} = lease} ->
        {:ok, lease}

      :missing ->
        with {:ok, lease} <- resolved_lease(selection_config, local_revision_digest, now) do
          Wardwright.Runtime.put_model_skyline_pin(model_id, version, work_unit, lease, now)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp selected_lease(_config, selection_config, _work_unit, local_revision_digest, now, :preview) do
    resolved_lease(selection_config, local_revision_digest, now)
  end

  defp resolved_lease(selection_config, local_revision_digest, now) do
    with {:ok, raw} <- Source.load(selection_config["selection_path"]),
         {:ok, snapshot} <- SelectionSnapshot.verify(raw, expected(selection_config), now: now) do
      bind_snapshot(snapshot, selection_config, local_revision_digest)
    end
  end

  defp bind_snapshot(snapshot, selection_config, local_revision_digest) do
    bindings =
      Map.new(selection_config["bindings"], fn binding ->
        {:ok, offering} = SelectionSnapshot.normalize_offering(binding["offering"])
        {offering["offering_id"], {offering, binding["target_model"]}}
      end)

    snapshot.choices
    |> Enum.reduce_while({:ok, [], []}, fn choice, {:ok, offering_ids, target_models} ->
      offering_id = choice.offering["offering_id"]

      case Map.get(bindings, offering_id) do
        {expected_offering, target_model} when expected_offering == choice.offering ->
          {:cont, {:ok, [offering_id | offering_ids], [target_model | target_models]}}

        _missing_or_mismatched ->
          {:halt, {:error, :selection_binding_mismatch}}
      end
    end)
    |> case do
      {:ok, offering_ids, target_models} ->
        {:ok,
         %Lease{
           frontier_id: snapshot.frontier_id,
           frontier_snapshot_id: snapshot.frontier_snapshot_id,
           local_revision_digest: local_revision_digest,
           ordered_offering_ids: Enum.reverse(offering_ids),
           ordered_target_models: Enum.reverse(target_models),
           policy_hash: snapshot.policy_hash,
           selection_id: snapshot.selection_id,
           snapshot_id: snapshot.snapshot_id,
           valid_until: snapshot.valid_until,
           workload: snapshot.workload
         }}

      error ->
        error
    end
  end

  defp validate_pinned_lease(%Lease{} = lease, local_revision_digest, now) do
    cond do
      lease.local_revision_digest != local_revision_digest ->
        {:error, :local_target_changed}

      DateTime.compare(now, lease.valid_until) != :lt ->
        {:error, :expired_selection}

      true ->
        :ok
    end
  end

  defp overlay_route(config, %Lease{} = lease) do
    target_index = Map.new(config["targets"], &{ModelGraph.target_model(&1), &1})

    targets = Enum.map(lease.ordered_target_models, &Map.get(target_index, &1))

    if Enum.any?(targets, &is_nil/1) do
      {:error, :local_target_changed}
    else
      cascade = %{"id" => @route_id, "models" => lease.ordered_target_models}

      cascades =
        [cascade | Enum.reject(config["cascades"] || [], &(&1["id"] == @route_id))]

      {:ok,
       config
       |> Map.put("cascades", cascades)
       |> Map.put("route_root", @route_id)
       |> Map.put("targets", targets)}
    end
  end

  defp receipt_metadata(%Lease{} = lease, status) do
    %{
      "frontier_id" => lease.frontier_id,
      "frontier_snapshot_id" => lease.frontier_snapshot_id,
      "ordered_offering_ids" => lease.ordered_offering_ids,
      "pin_scope" => pin_scope(status),
      "policy_hash" => lease.policy_hash,
      "selection_id" => lease.selection_id,
      "snapshot_id" => lease.snapshot_id,
      "status" => Atom.to_string(status),
      "valid_until" => DateTime.to_iso8601(lease.valid_until),
      "workload" => lease.workload
    }
  end

  defp runtime_work_unit(%WorkUnit{}, _mode), do: :ok
  defp runtime_work_unit(nil, :preview), do: :ok
  defp runtime_work_unit(_work_unit, _mode), do: {:error, :invalid_authenticated_principal}

  defp pin_scope(:pinned), do: @pin_scope
  defp pin_scope(:preview_unpinned), do: "none"

  defp blocked_pin_scope(:admit), do: @pin_scope
  defp blocked_pin_scope(:preview), do: "none"

  defp runtime_config(selection_config, config) do
    case validate_config(selection_config, config) do
      :ok -> :ok
      {:error, _message} -> {:error, :invalid_model_skyline_config}
    end
  end

  defp validate_source_path(path) do
    if is_binary(path) and String.valid?(path) and Path.type(path) == :absolute,
      do: :ok,
      else: {:error, :invalid_model_skyline_config}
  end

  defp validate_expected(config) do
    workload = config["expected_workload"]

    with :ok <- required_string(config["expected_selection_id"]),
         :ok <- required_string(config["expected_frontier_id"]),
         true <- is_map(workload),
         :ok <- exact_keys(workload, @workload_keys),
         :ok <- required_string(workload["id"]),
         :ok <- required_string(workload["version"]),
         :ok <- required_string(workload["unit"]) do
      :ok
    else
      _reason -> {:error, :invalid_model_skyline_config}
    end
  end

  defp validate_bindings(bindings, config)
       when is_list(bindings) and bindings != [] and length(bindings) <= @max_bindings do
    target_index = Map.new(config["targets"], &{ModelGraph.target_model(&1), &1})

    bindings
    |> Enum.reduce_while({:ok, MapSet.new(), MapSet.new()}, fn binding, {:ok, offering_ids, target_models} ->
      with true <- is_map(binding),
           :ok <- exact_keys(binding, @binding_keys),
           {:ok, offering} <- SelectionSnapshot.normalize_offering(binding["offering"]),
           target_model when is_binary(target_model) and target_model != "" <-
             binding["target_model"],
           target when is_map(target) <- Map.get(target_index, target_model),
           false <- ModelGraph.wardwright_model_target?(target),
           false <- MapSet.member?(offering_ids, offering["offering_id"]),
           false <- MapSet.member?(target_models, target_model) do
        {:cont, {:ok, MapSet.put(offering_ids, offering["offering_id"]), MapSet.put(target_models, target_model)}}
      else
        _reason -> {:halt, {:error, :invalid_model_skyline_config}}
      end
    end)
    |> case do
      {:ok, _offering_ids, _target_models} -> :ok
      error -> error
    end
  end

  defp validate_bindings(_bindings, _config), do: {:error, :invalid_model_skyline_config}

  defp expected(config) do
    %{
      "frontier_id" => config["expected_frontier_id"],
      "selection_id" => config["expected_selection_id"],
      "workload" => config["expected_workload"]
    }
  end

  defp local_revision_digest(selection_config, config) do
    encoded =
      %{selection_config: selection_config, targets: config["targets"]}
      |> :erlang.term_to_binary([:deterministic])

    :sha256
    |> :crypto.hash(encoded)
    |> Base.encode16(case: :lower)
  end

  defp required_string(value) do
    if is_binary(value) and byte_size(value) in 1..512 and String.trim(value) != "",
      do: :ok,
      else: {:error, :invalid_model_skyline_config}
  end

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_reason), do: "model_skyline_internal_error"

  defp exact_keys(map, expected) do
    if map |> Map.keys() |> Enum.sort() == Enum.sort(expected),
      do: :ok,
      else: {:error, :invalid_model_skyline_config}
  end
end
