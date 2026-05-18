defmodule Wardwright.PolicySandbox.Dune do
  @moduledoc """
  Thin Dune adapter for evaluating BEAM-native policy snippets.

  This is an evaluation spike, not a promise that Dune is a hostile-code
  security boundary. The adapter normalizes Dune's result into policy-engine
  terms so callers can fail closed and record receipts without matching on
  Dune structs directly.
  """

  @default_opts [
    timeout: 1_000,
    max_reductions: 100_000,
    max_heap_size: 250_000,
    inspect_sort_maps: true
  ]

  def default_opts, do: @default_opts

  def eval_string(source, opts \\ []) when is_binary(source) and is_list(opts) do
    source
    |> Dune.eval_string(Keyword.merge(@default_opts, opts))
    |> normalize_result()
  end

  def parse_string(source, opts \\ []) when is_binary(source) and is_list(opts) do
    source
    |> Dune.string_to_quoted(Keyword.merge(@default_opts, opts))
    |> normalize_result()
  end

  def eval_snippet(source, input, opts \\ []) when is_binary(source) and is_list(opts) do
    source
    |> snippet_source(input)
    |> eval_string(opts)
    |> normalize_policy_result()
  end

  def eval_snippet_in_session(source, input, %Dune.Session{} = session, opts \\ [])
      when is_binary(source) and is_list(opts) do
    session =
      Dune.Session.eval_string(
        session,
        snippet_source(source, input),
        Keyword.merge(@default_opts, opts)
      )

    {session, session.last_result |> normalize_result() |> normalize_policy_result()}
  end

  defp snippet_source(source, input) do
    input = normalize_json_value(input)

    """
    input = #{inspect(input, limit: :infinity, printable_limit: :infinity)}

    #{source}
    """
  end

  defp normalize_policy_result(%{"status" => "ok", "value" => value} = result)
       when is_map(value) do
    result
    |> Map.put("policy_result", normalize_policy_map(value))
    |> Map.put("policy_status", policy_status(value))
  end

  defp normalize_policy_result(%{"status" => "ok"} = result) do
    Map.merge(result, %{
      "policy_status" => "error",
      "policy_result" => fail_closed_result("invalid_result", "Dune snippet must return a map.")
    })
  end

  defp normalize_policy_result(
         %{"status" => "error", "reason" => reason, "message" => message} = result
       ) do
    Map.merge(result, %{
      "policy_status" => "error",
      "policy_result" => fail_closed_result(reason, message)
    })
  end

  defp normalize_result(%Dune.Success{} = success) do
    %{
      "engine" => "dune",
      "status" => "ok",
      "value" => success.value,
      "inspected" => success.inspected,
      "stdio" => success.stdio
    }
  end

  defp normalize_result(%Dune.Failure{} = failure) do
    %{
      "engine" => "dune",
      "status" => "error",
      "reason" => Atom.to_string(failure.type),
      "message" => failure.message,
      "stdio" => failure.stdio
    }
  end

  defp normalize_policy_map(result) do
    result
    |> Map.put_new("schema", "wardwright.policy_result.v1")
    |> Map.put_new("source", "dune")
    |> Map.put_new("action", "block")
    |> Map.put_new("status", "matched")
    |> Map.put_new("trace", [])
  end

  defp policy_status(%{"action" => action}) when is_binary(action), do: "ok"
  defp policy_status(_result), do: "error"

  defp fail_closed_result(reason, message) do
    %{
      "schema" => "wardwright.policy_result.v1",
      "source" => "dune",
      "status" => "error",
      "action" => "block",
      "reason" => reason,
      "message" => message,
      "trace" => [
        %{
          "rule" => "dune-snippet",
          "result" => false,
          "reason" => reason
        }
      ]
    }
  end

  defp normalize_json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> {to_string(key), normalize_json_value(inner)} end)
    |> Map.new()
  end

  defp normalize_json_value(value) when is_list(value),
    do: Enum.map(value, &normalize_json_value/1)

  defp normalize_json_value(value) when is_binary(value), do: value
  defp normalize_json_value(value) when is_boolean(value), do: value
  defp normalize_json_value(value) when is_number(value), do: value
  defp normalize_json_value(nil), do: nil
  defp normalize_json_value(value), do: inspect(value)
end
