defmodule Wardwright.ModelSkyline.Source do
  @moduledoc false

  @max_bytes 10 * 1024 * 1024
  @read_chunk_bytes 64 * 1024

  @type reason ::
          :selection_source_changed
          | :selection_source_invalid
          | :selection_source_not_regular
          | :selection_source_too_large
          | :selection_source_unreadable

  @spec load(String.t(), keyword()) :: {:ok, binary()} | {:error, reason()}
  def load(path, opts \\ [])

  def load(path, opts) when is_binary(path) do
    maximum = Keyword.get(opts, :max_bytes, @max_bytes)

    with true <- Path.type(path) == :absolute,
         true <- is_integer(maximum) and maximum > 0 and maximum <= @max_bytes,
         {:ok, before_info} <- read_link_info(path),
         :ok <- regular_and_bounded(before_info, maximum),
         {:ok, descriptor} <- open(path) do
      read_open_file(descriptor, path, before_info, maximum)
    else
      false -> {:error, :selection_source_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  def load(_path, _opts), do: {:error, :selection_source_invalid}

  defp open(path) do
    case :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      {:ok, descriptor} -> {:ok, descriptor}
      {:error, _reason} -> {:error, :selection_source_unreadable}
    end
  end

  defp read_open_file(descriptor, path, before_info, maximum) do
    result =
      with {:ok, opened_info} <- read_file_info(descriptor),
           :ok <- stable_identity(before_info, opened_info),
           {:ok, payload} <- read_all(descriptor, maximum, []),
           {:ok, finished_info} <- read_file_info(descriptor),
           {:ok, after_info} <- read_link_info(path),
           :ok <- stable_identity(opened_info, finished_info),
           :ok <- stable_identity(finished_info, after_info),
           true <- byte_size(payload) == info_size(finished_info) do
        {:ok, payload}
      else
        false -> {:error, :selection_source_changed}
        {:error, reason} -> {:error, reason}
      end

    :file.close(descriptor)
    result
  end

  defp read_all(descriptor, maximum, acc) do
    consumed = Enum.reduce(acc, 0, fn part, total -> total + byte_size(part) end)
    request_bytes = min(@read_chunk_bytes, maximum - consumed + 1)

    case :file.read(descriptor, request_bytes) do
      :eof ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, part} when consumed + byte_size(part) <= maximum ->
        read_all(descriptor, maximum, [part | acc])

      {:ok, _part} ->
        {:error, :selection_source_too_large}

      {:error, _reason} ->
        {:error, :selection_source_unreadable}
    end
  end

  defp read_link_info(path) do
    case :file.read_link_info(String.to_charlist(path), time: :posix) do
      {:ok, info} -> {:ok, info}
      {:error, _reason} -> {:error, :selection_source_unreadable}
    end
  end

  defp read_file_info(descriptor) do
    case :file.read_file_info(descriptor, time: :posix) do
      {:ok, info} -> {:ok, info}
      {:error, _reason} -> {:error, :selection_source_unreadable}
    end
  end

  defp regular_and_bounded(info, maximum) do
    stat = File.Stat.from_record(info)

    cond do
      stat.type != :regular -> {:error, :selection_source_not_regular}
      stat.size > maximum -> {:error, :selection_source_too_large}
      true -> :ok
    end
  end

  defp stable_identity(left, right) do
    if fingerprint(left) == fingerprint(right),
      do: :ok,
      else: {:error, :selection_source_changed}
  end

  defp fingerprint(info) do
    stat = File.Stat.from_record(info)

    {
      stat.type,
      stat.size,
      stat.mtime,
      stat.ctime,
      stat.mode,
      stat.links,
      stat.major_device,
      stat.minor_device,
      stat.inode
    }
  end

  defp info_size(info), do: info |> File.Stat.from_record() |> Map.fetch!(:size)
end
