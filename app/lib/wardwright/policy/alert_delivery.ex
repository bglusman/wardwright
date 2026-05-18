defmodule Wardwright.Policy.AlertDelivery do
  @moduledoc false

  def configure(config),
    do: Wardwright.Sinks.configure([Wardwright.Sinks.legacy_alert_sink(config)])

  def reset, do: configure(%{})

  def deliver(events, receipt_hint \\ nil) when is_list(events) do
    events
    |> Wardwright.Sinks.emit(receipt_id: receipt_hint)
    |> Wardwright.Sinks.alert_results()
  end

  def fail_closed?(results), do: Wardwright.Sinks.fail_closed?(results)
  def status, do: Wardwright.Sinks.legacy_alert_status()
end
