defmodule Wardwright.ElixirReference.HistoryCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/history_core.gleam`.
  """

  def count_matches(matches, opts) do
    threshold = opts |> Keyword.fetch!(:threshold) |> max(1)
    recent_limit = opts |> Keyword.fetch!(:recent_limit) |> max(1)
    working_set_size = Keyword.fetch!(opts, :working_set_size)
    scope = Keyword.fetch!(opts, :scope)

    count = matches |> Enum.take(recent_limit) |> Enum.count(& &1)
    status = if count >= threshold, do: :triggered, else: :not_triggered

    {status, scope, count, threshold, recent_limit, working_set_size}
  end
end
