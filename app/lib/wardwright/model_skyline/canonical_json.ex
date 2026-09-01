defmodule Wardwright.ModelSkyline.CanonicalJson do
  @moduledoc false

  import Bitwise

  @max_depth 64
  @max_integer 9_007_199_254_740_991
  @max_nodes 200_000

  @type reason ::
          :duplicate_object_name
          | :invalid_json
          | :json_too_deep
          | :json_too_large
          | :unsupported_json_number
          | :unsupported_json_value

  @spec decode(binary()) :: {:ok, term()} | {:error, reason()}
  def decode(raw) when is_binary(raw) do
    with :ok <- preflight_depth(raw),
         {:ok, value} <- decode_value(raw),
         :ok <- validate_value(value) do
      {:ok, value}
    end
  end

  def decode(_raw), do: {:error, :invalid_json}

  @spec encode(term()) :: {:ok, binary()} | {:error, reason()}
  def encode(value) do
    with :ok <- validate_value(value) do
      {:ok, value |> encode_value() |> IO.iodata_to_binary()}
    end
  rescue
    _error -> {:error, :unsupported_json_value}
  catch
    {:model_skyline_json, reason} -> {:error, reason}
  end

  @spec sha256(term()) :: {:ok, String.t()} | {:error, reason()}
  def sha256(value) do
    with {:ok, encoded} <- encode(value) do
      {:ok, :sha256 |> :crypto.hash(encoded) |> Base.encode16(case: :lower)}
    end
  end

  defp decode_value(raw) do
    decoders = [
      float: fn _token -> :model_skyline_unsupported_number end,
      integer: &decode_integer/1,
      object_finish: &finish_object/2
    ]

    case JSON.decode(raw, nil, decoders) do
      {value, nil, rest} when is_binary(rest) ->
        if String.trim(rest) == "", do: {:ok, value}, else: {:error, :invalid_json}

      {:error, _reason} ->
        {:error, :invalid_json}

      _other ->
        {:error, :invalid_json}
    end
  rescue
    _error -> {:error, :invalid_json}
  catch
    {:model_skyline_json, reason} -> {:error, reason}
  end

  defp decode_integer(token) do
    value = String.to_integer(token)

    if abs(value) <= @max_integer and token not in ["-0", "+0"] do
      value
    else
      :model_skyline_unsupported_number
    end
  end

  defp finish_object(entries, old_acc) do
    object = Map.new(entries)

    if map_size(object) == length(entries) do
      {object, old_acc}
    else
      throw({:model_skyline_json, :duplicate_object_name})
    end
  end

  defp preflight_depth(raw) do
    scan_depth(raw, 0, false, false)
  end

  defp scan_depth(<<>>, _depth, _in_string?, _escaped?), do: :ok

  defp scan_depth(<<byte, rest::binary>>, depth, in_string?, escaped?) do
    cond do
      in_string? and escaped? ->
        scan_depth(rest, depth, true, false)

      in_string? and byte == ?\\ ->
        scan_depth(rest, depth, true, true)

      in_string? and byte == ?" ->
        scan_depth(rest, depth, false, false)

      in_string? ->
        scan_depth(rest, depth, true, false)

      byte == ?" ->
        scan_depth(rest, depth, true, false)

      byte in [?{, ?[] and depth + 1 > @max_depth ->
        {:error, :json_too_deep}

      byte in [?{, ?[] ->
        scan_depth(rest, depth + 1, false, false)

      byte in [?}, ?]] ->
        scan_depth(rest, depth - 1, false, false)

      true ->
        scan_depth(rest, depth, false, false)
    end
  end

  defp validate_value(value) do
    case validate_value(value, 0) do
      {:ok, count} when count <= @max_nodes -> :ok
      {:ok, _count} -> {:error, :json_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_value(:model_skyline_unsupported_number, _count), do: {:error, :unsupported_json_number}

  defp validate_value(nil, count), do: {:ok, count + 1}
  defp validate_value(value, count) when is_boolean(value), do: {:ok, count + 1}

  defp validate_value(value, count) when is_integer(value) do
    if abs(value) <= @max_integer,
      do: {:ok, count + 1},
      else: {:error, :unsupported_json_number}
  end

  defp validate_value(value, count) when is_binary(value) do
    if i_json_string?(value),
      do: {:ok, count + 1},
      else: {:error, :unsupported_json_value}
  end

  defp validate_value(values, count) when is_list(values) do
    Enum.reduce_while(values, {:ok, count + 1}, fn value, {:ok, current} ->
      case validate_value(value, current) do
        {:ok, next} when next <= @max_nodes -> {:cont, {:ok, next}}
        other -> {:halt, other}
      end
    end)
  end

  defp validate_value(value, count) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, count + 1}, fn
      {key, child}, {:ok, current} when is_binary(key) ->
        with true <- i_json_string?(key),
             {:ok, next} <- validate_value(child, current + 1),
             true <- next <= @max_nodes do
          {:cont, {:ok, next}}
        else
          false -> {:halt, {:error, :unsupported_json_value}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _entry, _acc ->
        {:halt, {:error, :unsupported_json_value}}
    end)
  end

  defp validate_value(_value, _count), do: {:error, :unsupported_json_value}

  defp i_json_string?(value) do
    String.valid?(value) and
      Enum.all?(String.to_charlist(value), fn codepoint ->
        not noncharacter?(codepoint) and codepoint not in 0xD800..0xDFFF
      end)
  rescue
    _error -> false
  end

  defp noncharacter?(codepoint) do
    codepoint in 0xFDD0..0xFDEF or (codepoint &&& 0xFFFF) in [0xFFFE, 0xFFFF]
  end

  defp encode_value(nil), do: "null"
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value) when is_binary(value), do: [?", encode_string(value), ?"]
  defp encode_value([]), do: "[]"

  defp encode_value(values) when is_list(values) do
    [?[, values |> Enum.map(&encode_value/1) |> Enum.intersperse(?,), ?]]
  end

  defp encode_value(value) when is_map(value) do
    entries =
      value
      |> Enum.sort(fn {left, _left_value}, {right, _right_value} ->
        utf16_sort_key(left) <= utf16_sort_key(right)
      end)
      |> Enum.map(fn {key, child} -> [[?", encode_string(key), ?", ?:], encode_value(child)] end)
      |> Enum.intersperse(?,)

    [?{, entries, ?}]
  end

  defp encode_value(_value), do: throw({:model_skyline_json, :unsupported_json_value})

  defp utf16_sort_key(value) do
    :unicode.characters_to_binary(value, :utf8, {:utf16, :big})
  end

  defp encode_string(value), do: encode_string(value, [])

  defp encode_string(<<>>, acc), do: Enum.reverse(acc)
  defp encode_string(<<?", rest::binary>>, acc), do: encode_string(rest, [~S(\") | acc])
  defp encode_string(<<?\\, rest::binary>>, acc), do: encode_string(rest, [~S(\\) | acc])
  defp encode_string(<<8, rest::binary>>, acc), do: encode_string(rest, [~S(\b) | acc])
  defp encode_string(<<9, rest::binary>>, acc), do: encode_string(rest, [~S(\t) | acc])
  defp encode_string(<<10, rest::binary>>, acc), do: encode_string(rest, [~S(\n) | acc])
  defp encode_string(<<12, rest::binary>>, acc), do: encode_string(rest, [~S(\f) | acc])
  defp encode_string(<<13, rest::binary>>, acc), do: encode_string(rest, [~S(\r) | acc])

  defp encode_string(<<codepoint, rest::binary>>, acc) when codepoint < 0x20 do
    escaped = "\\u00" <> String.pad_leading(Integer.to_string(codepoint, 16), 2, "0")
    encode_string(rest, [escaped | acc])
  end

  defp encode_string(<<codepoint::utf8, rest::binary>>, acc) do
    encode_string(rest, [<<codepoint::utf8>> | acc])
  end
end
