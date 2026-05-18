defmodule Wardwright.ElixirReference.StreamCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/stream_core.gleam`.
  """

  def action_tag("rewrite", "stream_window"), do: "rewrite_window"
  def action_tag("rewrite", _scope), do: "rewrite_chunk"
  def action_tag("rewrite_chunk", "stream_window"), do: "rewrite_window"
  def action_tag("rewrite_chunk", _scope), do: "rewrite_chunk"
  def action_tag("drop_chunk", _scope), do: "drop_chunk"
  def action_tag(action, _scope) when action in ["block", "block_final"], do: "block"
  def action_tag(action, _scope) when action in ["retry", "retry_with_reminder"], do: "retry"
  def action_tag("pass", _scope), do: "pass"
  def action_tag(_action, _scope), do: "annotate"

  def terminal_status(action) do
    case action_tag(action, "chunk") do
      "block" -> "stream_policy_blocked"
      "retry" -> "stream_policy_retry_required"
      _ -> "completed"
    end
  end

  def latency_exceeded?(observed_ms, max_hold_ms), do: observed_ms > max_hold_ms

  def release_budget(stream_window_bytes, horizon_bytes),
    do: max(0, stream_window_bytes - horizon_bytes)

  def rewritten_bytes(_generated_bytes, true), do: 0
  def rewritten_bytes(generated_bytes, false), do: generated_bytes
end
