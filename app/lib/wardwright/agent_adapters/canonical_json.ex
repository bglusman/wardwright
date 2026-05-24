defmodule Wardwright.AgentAdapters.CanonicalJson do
  @moduledoc false

  def encode!(value) do
    value
    |> encode_value()
    |> IO.iodata_to_binary()
  end

  defp encode_value(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        [JSON.encode!(to_string(key)), ":", encode_value(nested)]
      end)

    ["{", Enum.intersperse(entries, ","), "}"]
  end

  defp encode_value(value) when is_list(value) do
    values = Enum.map(value, &encode_value/1)
    ["[", Enum.intersperse(values, ","), "]"]
  end

  defp encode_value(value), do: JSON.encode!(value)
end
