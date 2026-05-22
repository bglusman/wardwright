defmodule Wardwright.Json do
  @moduledoc false

  def encode_display!(value) do
    JSON.encode!(value)
  end

  def decode_error_message(%JSON.DecodeError{} = error), do: Exception.message(error)
  def decode_error_message(reason), do: inspect(reason)
end
