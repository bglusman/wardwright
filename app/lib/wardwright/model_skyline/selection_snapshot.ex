defmodule Wardwright.ModelSkyline.SelectionSnapshot do
  @moduledoc false

  alias Wardwright.ModelSkyline.CanonicalJson

  @max_candidates 10_000
  @max_capabilities 128
  @max_axes 64
  @max_axis_evidence_items 256
  @max_ttl_seconds 31_536_000
  @max_safe_integer 9_007_199_254_740_991
  @decimal ~r/^[+-]?\d+(?:\.\d+)?$/
  @sha256 ~r/^[0-9a-f]{64}$/

  @top_level_keys ~w(
    default fallbacks frontier_id frontier_snapshot_id generated_at hash_algorithm
    kind max_per_provider on_insufficient order_by policy_hash requested_count
    schema_version selection_id snapshot_id strategy valid_until workload
  )
  @choice_keys ~w(axes metadata offering)
  @axis_estimate_keys ~w(
    dependencies lower minimum_sample_count oldest_observed_at source_ids sources unit upper value
  )
  @offering_keys ~w(
    agent_harness billing_mode capabilities endpoint model_id offering_id provider
    quantization reasoning_effort region service_tier
  )
  @optional_offering_keys ~w(
    agent_harness billing_mode endpoint quantization reasoning_effort region service_tier
  )
  @workload_keys ~w(id unit version)

  defmodule Choice do
    @moduledoc false

    @enforce_keys [:axes, :metadata, :offering]
    defstruct [:axes, :metadata, :offering]
  end

  @enforce_keys [
    :choices,
    :frontier_id,
    :frontier_snapshot_id,
    :generated_at,
    :policy_hash,
    :selection_id,
    :snapshot_id,
    :valid_until,
    :workload
  ]
  defstruct [
    :choices,
    :frontier_id,
    :frontier_snapshot_id,
    :generated_at,
    :policy_hash,
    :selection_id,
    :snapshot_id,
    :valid_until,
    :workload
  ]

  @type reason ::
          CanonicalJson.reason()
          | :expired_selection
          | :frontier_id_mismatch
          | :future_selection
          | :invalid_selection
          | :invalid_selection_digest
          | :selection_id_mismatch
          | :unsupported_selection
          | :workload_mismatch

  @spec verify(binary(), map(), keyword()) :: {:ok, struct()} | {:error, reason()}
  def verify(raw, expected, opts \\ [])

  def verify(raw, expected, opts) when is_binary(raw) and is_map(expected) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, document} <- CanonicalJson.decode(raw),
         {:ok, normalized, choices} <- validate_document(document),
         :ok <- verify_digest(normalized),
         :ok <- verify_expected(normalized, expected),
         {:ok, generated_at} <- timestamp(normalized["generated_at"]),
         {:ok, valid_until} <- timestamp(normalized["valid_until"]),
         :ok <- verify_validity(generated_at, valid_until, now) do
      {:ok,
       %__MODULE__{
         choices: choices,
         frontier_id: normalized["frontier_id"],
         frontier_snapshot_id: normalized["frontier_snapshot_id"],
         generated_at: generated_at,
         policy_hash: normalized["policy_hash"],
         selection_id: normalized["selection_id"],
         snapshot_id: normalized["snapshot_id"],
         valid_until: valid_until,
         workload: normalized["workload"]
       }}
    end
  end

  def verify(_raw, _expected, _opts), do: {:error, :invalid_selection}

  @spec normalize_offering(term()) :: {:ok, map()} | {:error, :invalid_selection}
  def normalize_offering(offering) when is_map(offering) do
    offering = Map.put_new(offering, "billing_mode", nil)

    with :ok <- exact_keys(offering, @offering_keys),
         :ok <- required_string(offering["offering_id"]),
         :ok <- required_string(offering["model_id"]),
         :ok <- required_string(offering["provider"]),
         :ok <- optional_offering_strings(offering),
         :ok <- capabilities(offering["capabilities"]) do
      {:ok, offering}
    else
      _reason -> {:error, :invalid_selection}
    end
  end

  def normalize_offering(_offering), do: {:error, :invalid_selection}

  defp validate_document(document) when is_map(document) do
    with :ok <- exact_keys(document, @top_level_keys),
         :ok <- fixed_contract(document),
         :ok <- identifiers(document),
         :ok <- workload(document["workload"]),
         :ok <- selection_options(document),
         {:ok, default, normalized_default} <- choice(document["default"]),
         {:ok, fallbacks, normalized_fallbacks} <- choices(document["fallbacks"]),
         normalized =
           document
           |> Map.put("default", normalized_default)
           |> Map.put("fallbacks", normalized_fallbacks),
         all_choices = [default | fallbacks],
         :ok <- choice_coherence(all_choices, document) do
      {:ok, normalized, all_choices}
    else
      {:error, reason} -> {:error, reason}
      _reason -> {:error, :invalid_selection}
    end
  end

  defp validate_document(_document), do: {:error, :invalid_selection}

  defp fixed_contract(document) do
    if document["schema_version"] == "model-skyline/v1alpha1" and
         document["kind"] == "selection" and
         document["hash_algorithm"] == "sha256-rfc8785-v1" and
         document["strategy"] == "lexicographic" do
      :ok
    else
      {:error, :unsupported_selection}
    end
  end

  defp identifiers(document) do
    if sha256?(document["snapshot_id"]) and
         sha256?(document["policy_hash"]) and
         sha256?(document["frontier_snapshot_id"]) and
         valid_identifier?(document["selection_id"]) and
         valid_identifier?(document["frontier_id"]) and
         valid_identifier?(document["order_by"]) do
      :ok
    else
      {:error, :invalid_selection}
    end
  end

  defp sha256?(value), do: is_binary(value) and Regex.match?(@sha256, value)

  defp valid_identifier?(value) do
    is_binary(value) and byte_size(value) in 1..512 and String.trim(value) != ""
  end

  defp workload(workload) when is_map(workload) do
    with :ok <- exact_keys(workload, @workload_keys),
         :ok <- required_string(workload["id"]),
         :ok <- required_string(workload["version"]) do
      required_string(workload["unit"])
    end
  end

  defp workload(_workload), do: {:error, :invalid_selection}

  defp selection_options(document) do
    requested_count = document["requested_count"]
    max_per_provider = document["max_per_provider"]

    cond do
      not (is_integer(requested_count) and requested_count in 1..@max_candidates) ->
        {:error, :invalid_selection}

      not (is_nil(max_per_provider) or
               (is_integer(max_per_provider) and max_per_provider in 1..@max_candidates)) ->
        {:error, :invalid_selection}

      document["on_insufficient"] not in ["error", "return_available"] ->
        {:error, :invalid_selection}

      not is_list(document["fallbacks"]) ->
        {:error, :invalid_selection}

      length(document["fallbacks"]) >= @max_candidates ->
        {:error, :invalid_selection}

      true ->
        :ok
    end
  end

  defp choice(choice) when is_map(choice) do
    with :ok <- exact_keys(choice, @choice_keys),
         {:ok, offering} <- normalize_offering(choice["offering"]),
         axes when is_map(axes) <- choice["axes"],
         :ok <- axes(axes),
         metadata when is_map(metadata) <- choice["metadata"] do
      normalized = Map.put(choice, "offering", offering)
      {:ok, %Choice{axes: axes, metadata: metadata, offering: offering}, normalized}
    else
      _reason -> {:error, :invalid_selection}
    end
  end

  defp choice(_choice), do: {:error, :invalid_selection}

  defp choices(choices) when is_list(choices) do
    choices
    |> Enum.reduce_while({:ok, [], []}, fn raw, {:ok, parsed, normalized} ->
      case choice(raw) do
        {:ok, choice, normalized_choice} ->
          {:cont, {:ok, [choice | parsed], [normalized_choice | normalized]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, parsed, normalized} -> {:ok, Enum.reverse(parsed), Enum.reverse(normalized)}
      error -> error
    end
  end

  defp choices(_choices), do: {:error, :invalid_selection}

  defp axes(values) when map_size(values) in 1..@max_axes do
    Enum.reduce_while(values, :ok, fn {name, estimate}, :ok ->
      with :ok <- required_string(name),
           :ok <- axis_estimate(estimate) do
        {:cont, :ok}
      else
        _reason -> {:halt, {:error, :invalid_selection}}
      end
    end)
  end

  defp axes(_values), do: {:error, :invalid_selection}

  defp axis_estimate(estimate) when is_map(estimate) do
    with :ok <- known_keys(estimate, @axis_estimate_keys, ~w(unit value)),
         :ok <- decimal_string(estimate["value"]),
         :ok <- required_string(estimate["unit"]),
         :ok <- optional_decimal_string(estimate["lower"]),
         :ok <- optional_decimal_string(estimate["upper"]),
         :ok <- bounded_unique_strings(Map.get(estimate, "dependencies", [])),
         :ok <- bounded_unique_strings(Map.get(estimate, "source_ids", [])),
         :ok <- bounded_sources(Map.get(estimate, "sources", [])),
         :ok <- optional_timestamp(estimate["oldest_observed_at"]) do
      optional_sample_count(estimate["minimum_sample_count"])
    end
  end

  defp axis_estimate(_estimate), do: {:error, :invalid_selection}

  defp choice_coherence(choices, document) do
    offering_ids = Enum.map(choices, & &1.offering["offering_id"])
    provider_counts = Enum.frequencies_by(choices, & &1.offering["provider"])
    count = length(choices)
    requested_count = document["requested_count"]
    max_per_provider = document["max_per_provider"]
    order_by = document["order_by"]

    cond do
      count > requested_count ->
        {:error, :invalid_selection}

      document["on_insufficient"] == "error" and count != requested_count ->
        {:error, :invalid_selection}

      length(Enum.uniq(offering_ids)) != count ->
        {:error, :invalid_selection}

      not Enum.all?(choices, &Map.has_key?(&1.axes, order_by)) ->
        {:error, :invalid_selection}

      is_integer(max_per_provider) and
          Enum.any?(provider_counts, fn {_provider, provider_count} ->
            provider_count > max_per_provider
          end) ->
        {:error, :invalid_selection}

      true ->
        :ok
    end
  end

  defp optional_offering_strings(offering) do
    if Enum.all?(@optional_offering_keys, &optional_offering_string?(offering[&1])) do
      :ok
    else
      {:error, :invalid_selection}
    end
  end

  defp optional_offering_string?(nil), do: true

  defp optional_offering_string?(value) do
    is_binary(value) and byte_size(value) in 1..512
  end

  defp capabilities(values) when is_list(values) and length(values) <= @max_capabilities do
    if Enum.all?(values, &(is_binary(&1) and byte_size(&1) in 1..64)) and
         values == values |> Enum.uniq() |> Enum.sort() do
      :ok
    else
      {:error, :invalid_selection}
    end
  end

  defp capabilities(_values), do: {:error, :invalid_selection}

  defp required_string(value) do
    if is_binary(value) and String.valid?(value) and byte_size(value) in 1..512 and
         String.trim(value) != "",
       do: :ok,
       else: {:error, :invalid_selection}
  end

  defp decimal_string(value) do
    if is_binary(value) and byte_size(value) in 1..1024 and Regex.match?(@decimal, value),
      do: :ok,
      else: {:error, :invalid_selection}
  end

  defp optional_decimal_string(nil), do: :ok
  defp optional_decimal_string(value), do: decimal_string(value)

  defp bounded_unique_strings(values) when is_list(values) and length(values) <= @max_axis_evidence_items do
    if Enum.all?(values, &(required_string(&1) == :ok)) and
         length(values) == length(Enum.uniq(values)),
       do: :ok,
       else: {:error, :invalid_selection}
  end

  defp bounded_unique_strings(_values), do: {:error, :invalid_selection}

  defp bounded_sources(values) when is_list(values) and length(values) <= @max_axis_evidence_items do
    if Enum.all?(values, &is_map/1), do: :ok, else: {:error, :invalid_selection}
  end

  defp bounded_sources(_values), do: {:error, :invalid_selection}

  defp optional_timestamp(nil), do: :ok

  defp optional_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> :ok
      _result -> {:error, :invalid_selection}
    end
  end

  defp optional_timestamp(_value), do: {:error, :invalid_selection}

  defp optional_sample_count(nil), do: :ok

  defp optional_sample_count(value) when is_integer(value) and value >= 0 and value <= @max_safe_integer, do: :ok

  defp optional_sample_count(_value), do: {:error, :invalid_selection}

  defp exact_keys(map, expected) do
    if map |> Map.keys() |> Enum.sort() == Enum.sort(expected),
      do: :ok,
      else: {:error, :invalid_selection}
  end

  defp known_keys(map, allowed, required) do
    keys = Map.keys(map)

    if Enum.all?(keys, &(&1 in allowed)) and Enum.all?(required, &Map.has_key?(map, &1)),
      do: :ok,
      else: {:error, :invalid_selection}
  end

  defp verify_digest(document) do
    payload = Map.delete(document, "snapshot_id")
    stable = omit_null_billing_modes(payload)

    with {:ok, stable_hash} <- CanonicalJson.sha256(stable),
         {:ok, legacy_hash} <- CanonicalJson.sha256(payload) do
      if document["snapshot_id"] in [stable_hash, legacy_hash],
        do: :ok,
        else: {:error, :invalid_selection_digest}
    end
  end

  defp omit_null_billing_modes(payload) do
    payload
    |> Map.update!("default", &omit_choice_null_billing_mode/1)
    |> Map.update!(
      "fallbacks",
      &Enum.map(&1, fn choice -> omit_choice_null_billing_mode(choice) end)
    )
  end

  defp omit_choice_null_billing_mode(choice) do
    update_in(choice, ["offering"], fn offering ->
      if is_nil(offering["billing_mode"]),
        do: Map.delete(offering, "billing_mode"),
        else: offering
    end)
  end

  defp verify_expected(document, expected) do
    cond do
      document["selection_id"] != expected["selection_id"] ->
        {:error, :selection_id_mismatch}

      document["frontier_id"] != expected["frontier_id"] ->
        {:error, :frontier_id_mismatch}

      document["workload"] != expected["workload"] ->
        {:error, :workload_mismatch}

      true ->
        :ok
    end
  end

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _result -> {:error, :invalid_selection}
    end
  end

  defp timestamp(_value), do: {:error, :invalid_selection}

  defp verify_validity(generated_at, valid_until, now) do
    cond do
      not is_struct(now, DateTime) ->
        {:error, :invalid_selection}

      DateTime.compare(valid_until, generated_at) != :gt ->
        {:error, :invalid_selection}

      DateTime.diff(valid_until, generated_at, :second) > @max_ttl_seconds ->
        {:error, :invalid_selection}

      DateTime.after?(generated_at, now) ->
        {:error, :future_selection}

      DateTime.compare(now, valid_until) != :lt ->
        {:error, :expired_selection}

      true ->
        :ok
    end
  end
end
