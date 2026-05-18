defmodule Wardwright.ElixirReference.AlertCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/alert_core.gleam`.
  """

  def decide_enqueue(config, queue_depth, already_seen, alert, existing_status \\ :enqueued) do
    cond do
      already_seen ->
        %{
          key: alert.idempotency_key,
          status: {:duplicate, existing_status},
          queue_depth: queue_depth,
          queue_capacity: config.capacity
        }

      queue_depth >= config.capacity ->
        %{
          key: alert.idempotency_key,
          status: full_status(config.on_full),
          queue_depth: queue_depth,
          queue_capacity: config.capacity
        }

      true ->
        %{
          key: alert.idempotency_key,
          status: :enqueued,
          queue_depth: queue_depth + 1,
          queue_capacity: config.capacity
        }
    end
  end

  def classify_attempt(:fail_then_recover, 1, retry_limit) when 1 <= retry_limit, do: :retrying
  def classify_attempt(:fail_then_recover, 1, retry_limit) when 1 > retry_limit, do: :failed
  def classify_attempt(_behavior, _attempt, _retry_limit), do: :delivered

  def terminal?(status) when status in [:enqueued, :retrying], do: false
  def terminal?({:duplicate, _status}), do: true
  def terminal?(_status), do: true

  defp full_status(:dead_letter), do: :dead_lettered
  defp full_status(:drop), do: :dropped
  defp full_status(:fail_closed), do: :blocked
end
