defmodule Wardwright.ModelSkyline.WorkUnit do
  @moduledoc false

  @max_identity_bytes 512
  @scope_fields [
    {:tenant_id, "tenant_id"},
    {:application_id, "application_id"},
    {:agent_id, "consuming_agent_id"},
    {:user_id, "consuming_user_id"},
    {:session_id, "session_id"},
    {:run_id, "run_id"}
  ]

  @enforce_keys [:principal_id, :run_id]
  defstruct [
    :agent_id,
    :application_id,
    :principal_id,
    :run_id,
    :session_id,
    :tenant_id,
    :user_id
  ]

  defmodule RuntimeKey do
    @moduledoc false

    @enforce_keys [:principal_digest, :scope_digest]
    defstruct [:principal_digest, :scope_digest]

    @type t :: %__MODULE__{principal_digest: String.t(), scope_digest: String.t()}
  end

  @type t :: %__MODULE__{
          agent_id: String.t() | nil,
          application_id: String.t() | nil,
          principal_id: String.t(),
          run_id: String.t(),
          session_id: String.t() | nil,
          tenant_id: String.t() | nil,
          user_id: String.t() | nil
        }

  @type reason ::
          :invalid_authenticated_principal
          | :invalid_run_id
          | :invalid_scope_identity
          | :missing_run_id

  @spec from_caller(term(), map()) :: {:ok, t()} | {:error, reason()}
  def from_caller(principal_id, caller) when is_map(caller) do
    scopes =
      Map.new(@scope_fields, fn {field, caller_key} ->
        {field, get_in(caller, [caller_key, "value"])}
      end)

    with :ok <- identity_value(principal_id, :invalid_authenticated_principal),
         :ok <- required_run_id(scopes.run_id),
         :ok <- optional_scope_values(scopes) do
      {:ok, struct!(__MODULE__, Map.put(scopes, :principal_id, principal_id))}
    end
  end

  def from_caller(_principal_id, _caller), do: {:error, :invalid_authenticated_principal}

  @spec runtime_key(t()) :: RuntimeKey.t()
  def runtime_key(%__MODULE__{} = work_unit) do
    scope_values =
      Enum.map(@scope_fields, fn {field, _caller_key} ->
        {field, Map.fetch!(work_unit, field)}
      end)

    payload =
      :erlang.term_to_binary(
        {:wardwright_model_skyline_work_unit_v1, work_unit.principal_id, scope_values},
        [:deterministic]
      )

    %RuntimeKey{
      principal_digest: digest({:wardwright_model_skyline_principal_v1, work_unit.principal_id}),
      scope_digest: :sha256 |> :crypto.hash(payload) |> Base.encode16(case: :lower)
    }
  end

  defp required_run_id(nil), do: {:error, :missing_run_id}

  defp required_run_id(value) do
    if is_binary(value) and String.valid?(value) and String.trim(value) == "" do
      {:error, :missing_run_id}
    else
      identity_value(value, :invalid_run_id)
    end
  end

  defp optional_scope_values(scopes) do
    @scope_fields
    |> Keyword.delete(:run_id)
    |> Enum.reduce_while(:ok, fn {field, _caller_key}, :ok ->
      case Map.fetch!(scopes, field) do
        nil -> {:cont, :ok}
        value -> reduce_identity_value(value)
      end
    end)
  end

  defp reduce_identity_value(value) do
    case identity_value(value, :invalid_scope_identity) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp identity_value(value, reason) do
    if is_binary(value) and String.valid?(value) and byte_size(value) in 1..@max_identity_bytes and
         String.trim(value) != "",
       do: :ok,
       else: {:error, reason}
  end

  defp digest(value) do
    encoded = :erlang.term_to_binary(value, [:deterministic])
    :sha256 |> :crypto.hash(encoded) |> Base.encode16(case: :lower)
  end
end
