defmodule Wardwright.ModelApiKeyStore do
  @moduledoc false

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def init(:ok) do
    state =
      case Wardwright.SQLiteStore.enabled?() do
        true -> %{keys: load_sqlite_keys(), storage: :sqlite}
        false -> %{keys: %{}, storage: :memory}
      end

    {:ok, state}
  end

  def list(model_id \\ nil), do: GenServer.call(__MODULE__, {:list, model_id})
  def create(model_id, label), do: GenServer.call(__MODULE__, {:create, model_id, label})
  def revoke(id), do: GenServer.call(__MODULE__, {:revoke, id})
  def authenticate(model_id, key), do: GenServer.call(__MODULE__, {:authenticate, model_id, key})

  def valid?(model_id, key) do
    match?({:ok, _record_id}, authenticate(model_id, key))
  end

  def reset!, do: GenServer.call(__MODULE__, :reset)

  def handle_call({:list, model_id}, _from, state) do
    keys =
      state.keys
      |> Map.values()
      |> Enum.reject(fn key -> model_id && key["model_id"] != model_id end)
      |> Enum.sort_by(& &1["created_at"], :desc)
      |> Enum.map(&public_key_record/1)

    {:reply, keys, state}
  end

  def handle_call({:create, model_id, label}, _from, state) do
    raw_key = generate_key()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record = %{
      "created_at" => now,
      "id" => generate_id(),
      "key_hash" => hash_key(raw_key),
      "label" => label |> to_string() |> String.trim(),
      "model_id" => model_id |> to_string() |> String.trim(),
      "prefix" => String.slice(raw_key, 0, 16)
    }

    case persist_insert(state, record) do
      :ok ->
        state = put_in(state.keys[record["id"]], record)
        {:reply, {:ok, Map.put(public_key_record(record), "key", raw_key)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:revoke, id}, _from, state) do
    {record, keys} = Map.pop(state.keys, id)

    case {record, persist_delete(state, id)} do
      {nil, _result} ->
        {:reply, {:error, :not_found}, state}

      {_record, :ok} ->
        {:reply, :ok, %{state | keys: keys}}

      {_record, {:error, reason}} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:authenticate, model_id, key}, _from, state) do
    key_hash = key |> to_string() |> String.trim() |> hash_key()

    result =
      Enum.find_value(state.keys, :error, fn {id, record} ->
        if key_hash_matches?(record, model_id, key_hash), do: {:ok, id}
      end)

    {:reply, result, state}
  end

  def handle_call(:reset, _from, state) do
    case persist_clear(state) do
      :ok -> {:reply, :ok, %{state | keys: %{}}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp load_sqlite_keys do
    case Wardwright.SQLiteStore.list_api_keys() do
      {:ok, keys} -> Map.new(keys, &{&1["id"], &1})
      {:error, reason} -> raise "failed to load model API keys from SQLite: #{inspect(reason)}"
    end
  end

  defp public_key_record(record) do
    Map.take(record, ["id", "model_id", "label", "prefix", "created_at"])
  end

  defp key_hash_matches?(%{"key_hash" => stored_hash, "model_id" => record_model_id}, model_id, key_hash)
       when record_model_id == model_id and is_binary(stored_hash) and is_binary(key_hash) do
    Plug.Crypto.secure_compare(stored_hash, key_hash)
  rescue
    _error -> false
  end

  defp key_hash_matches?(_record, _model_id, _key_hash), do: false

  defp generate_key do
    "wwk_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  defp generate_id do
    "key_" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end

  defp hash_key(key) do
    :crypto.mac(:hmac, :sha256, hash_secret(), key)
    |> Base.url_encode64(padding: false)
  end

  defp hash_secret do
    Application.get_env(:wardwright, :model_api_key_hash_secret) ||
      System.get_env("WARDWRIGHT_MODEL_API_KEY_HASH_SECRET") ||
      System.get_env("WARDWRIGHT_SECRET_KEY_BASE") ||
      "wardwright-local-model-api-key-hash-secret"
  end

  defp persist_insert(%{storage: :sqlite}, record), do: sqlite_result(Wardwright.SQLiteStore.insert_api_key(record))

  defp persist_insert(%{storage: :memory}, _record), do: :ok

  defp persist_delete(%{storage: :sqlite}, id) do
    case Wardwright.SQLiteStore.delete_api_key(id) do
      {:ok, {:ok, changed}} when changed > 0 -> :ok
      {:ok, {:ok, _changed}} -> {:error, :not_found}
      {:ok, other} -> other
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_delete(%{storage: :memory}, _id), do: :ok

  defp persist_clear(%{storage: :sqlite}), do: sqlite_result(Wardwright.SQLiteStore.clear_api_keys())

  defp persist_clear(%{storage: :memory}), do: :ok

  defp sqlite_result({:ok, :ok}), do: :ok
  defp sqlite_result({:ok, result}), do: result
  defp sqlite_result({:error, reason}), do: {:error, reason}
end
