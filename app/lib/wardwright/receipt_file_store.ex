defmodule Wardwright.ReceiptFileStore do
  @moduledoc false

  @receipt_id_key "receipt_id"

  def enabled?, do: not is_nil(store_dir())

  def store_dir do
    case Application.get_env(:wardwright, :receipt_store_dir, :default) do
      nil -> nil
      :default -> System.get_env("WARDWRIGHT_RECEIPT_STORE_DIR") || default_store_dir()
      path -> path
    end
  end

  def list_receipts do
    store_dir()
    |> receipt_paths()
    |> Enum.flat_map(&decode_receipt_file/1)
    |> then(&{:ok, &1})
  end

  def insert_receipt(receipt) when is_map(receipt) do
    case receipt[@receipt_id_key] do
      receipt_id when is_binary(receipt_id) and receipt_id != "" ->
        path = receipt_path(receipt_id)
        tmp_path = "#{path}.#{System.unique_integer([:positive])}.tmp"
        payload = JSON.encode!(receipt)

        File.mkdir_p!(Path.dirname(path))
        File.write!(tmp_path, payload)
        File.chmod(tmp_path, 0o600)
        File.rename!(tmp_path, path)
        {:ok, :ok}

      _invalid ->
        {:error, :missing_receipt_id}
    end
  end

  def clear_receipts do
    store_dir()
    |> receipt_paths()
    |> Enum.each(&File.rm/1)

    {:ok, :ok}
  end

  defp receipt_paths(nil), do: []

  defp receipt_paths(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
  end

  defp receipt_path(receipt_id) do
    store_dir()
    |> Path.join("#{receipt_file_id(receipt_id)}.json")
  end

  defp receipt_file_id(receipt_id) do
    Base.url_encode64(receipt_id, padding: false)
  end

  defp decode_receipt_file(path) do
    with {:ok, json} <- File.read(path),
         {:ok, receipt} when is_map(receipt) <- JSON.decode(json) do
      [receipt]
    else
      _error -> []
    end
  end

  defp default_store_dir do
    Wardwright.Paths.data_path("receipts")
  end
end
