defmodule Wardwright.ElixirReference.StructuredValidationCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/structured_validation_core.gleam`.
  """

  def object_schema_valid?(required_ok, additional_properties_ok, properties_ok) do
    required_ok and additional_properties_ok and properties_ok
  end

  def string_property_valid?(is_string, string_length, min_length, enum_ok) do
    is_string and string_length >= min_length and enum_ok
  end

  def number_property_valid?(is_number, gte_ok, lte_ok), do: is_number and gte_ok and lte_ok
  def string_array_property_valid?(is_list, all_strings), do: is_list and all_strings
  def semantic_number_rule_valid?(is_number, bounds_ok), do: is_number and bounds_ok
  def semantic_string_not_contains_valid?(true, contains_pattern), do: not contains_pattern
  def semantic_string_not_contains_valid?(false, _contains_pattern), do: true
end
