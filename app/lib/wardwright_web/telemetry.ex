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
      ),
      summary("wardwright.sinks.delivery.duration",
        event_name: [:wardwright, :sinks, :delivery],
        measurement: :duration,
        tags: [:sink_id, :kind, :outcome],
        unit: {:native, :millisecond},
        description: "Wardwright sink delivery latency"
      ),
      last_value("wardwright.sinks.queue_capacity",
        event_name: [:wardwright, :sinks, :queue_depth],
        measurement: :capacity,
        tags: [:sink_id, :kind],
        description: "Configured queue capacity for each Wardwright sink"
      ),
      last_value("wardwright.sinks.queue_utilization",
        event_name: [:wardwright, :sinks, :queue_depth],
        measurement: :utilization,
        tags: [:sink_id, :kind],
        description: "Current queued fraction for each Wardwright sink"
      )
    ]
  end
end
