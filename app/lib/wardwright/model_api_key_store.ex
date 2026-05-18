defmodule Wardwright.ModelApiKeyStore do
  @moduledoc false

  use GenServer

  @store_version 1

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def init(:ok) do
    state = %{path: store_path(), keys: %{}}
    {:ok, load(state)}
  end

  def list(model_id \\ nil), do: GenServer.call(__MODULE__, {:list, model_id})
  def create(model_id, label), do: GenServer.call(__MODULE__, {:create, model_id, label})
  def revoke(id), do: GenServer.call(__MODULE__, {:revoke, id})
  def valid?(model_id, key), do: GenServer.call(__MODULE__, {:valid?, model_id, key})
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
      "id" => generate_id(),
      "model_id" => model_id |> to_string() |> String.trim(),
      "label" => label |> to_string() |> String.trim(),
      "prefix" => String.slice(raw_key, 0, 16),
      "key_hash" => hash_key(raw_key),
      "created_at" => now
    }

    state = put_in(state.keys[record["id"]], record) |> persist()
    {:reply, {:ok, Map.put(public_key_record(record), "key", raw_key)}, state}
  end

  def handle_call({:revoke, id}, _from, state) do
    {record, keys} = Map.pop(state.keys, id)
    state = %{state | keys: keys} |> persist()
    {:reply, if(record, do: :ok, else: {:error, :not_found}), state}
  end

  def handle_call({:valid?, model_id, key}, _from, state) do
    key_hash = hash_key(key |> to_string() |> String.trim())

    valid? =
      Enum.any?(state.keys, fn {_id, record} ->
        record["model_id"] == model_id and
          Plug.Crypto.secure_compare(record["key_hash"], key_hash)
      end)

    {:reply, valid?, state}
  rescue
    _error -> {:reply, false, state}
  end

  def handle_call(:reset, _from, state) do
    state = %{state | keys: %{}} |> persist()
    {:reply, :ok, state}
  end

  defp public_key_record(record) do
    Map.take(record, ["id", "model_id", "label", "prefix", "created_at"])
  end

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

  defp load(%{path: nil} = state), do: state

  defp load(%{path: path} = state) do
    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, %{"keys" => keys}} <- Jason.decode(body) do
      %{state | keys: Map.new(keys, &{&1["id"], &1})}
    else
      _ -> state
    end
  end

  defp persist(%{path: nil} = state), do: state

  defp persist(%{path: path, keys: keys} = state) do
    File.mkdir_p!(Path.dirname(path))

    body =
      Jason.encode!(%{
        "store_version" => @store_version,
        "keys" => keys |> Map.values() |> Enum.sort_by(& &1["created_at"])
      })

    File.write!("#{path}.tmp", body)
    File.chmod!("#{path}.tmp", 0o600)
    File.rename!("#{path}.tmp", path)
    File.chmod!(path, 0o600)
    state
  end

  defp store_path do
    case Application.get_env(:wardwright, :model_api_key_store_path, :default) do
      nil -> nil
      :default -> System.get_env("WARDWRIGHT_MODEL_API_KEY_STORE") || default_store_path()
      path -> path
    end
  end

  defp default_store_path do
    Path.join(System.user_home!(), ".wardwright/model-api-keys.json")
  end
end
