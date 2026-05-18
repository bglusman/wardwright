defmodule WardwrightWeb.Telemetry do
  @moduledoc false

  import Telemetry.Metrics

  def metrics do
    [
      last_value("wardwright.sinks.queue_depth",
        event_name: [:wardwright, :sinks, :queue_depth],
        measurement: :depth,
        tags: [:sink_id, :kind],
        description: "Current queued events retained by each Wardwright sink"
      ),
      counter("wardwright.sinks.delivery.count",
        event_name: [:wardwright, :sinks, :delivery],
        measurement: :count,
        tags: [:sink_id, :kind, :outcome],
        description: "Wardwright sink delivery outcomes"
      )
    ]
  end
end
