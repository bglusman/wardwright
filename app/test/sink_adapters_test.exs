defmodule Wardwright.Test.SinkWebhook do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    send(:persistent_term.get({__MODULE__, :pid}), {:sink_webhook, Jason.decode!(body)})
    Plug.Conn.send_resp(conn, 204, "")
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end

defmodule Wardwright.SinkAdaptersTest do
  use Wardwright.RouterCase

  test "configured sinks independently receive selected metadata events" do
    jsonl_path = Path.join(System.tmp_dir!(), "wardwright-sinks-#{System.unique_integer()}.jsonl")
    webhook_url = webhook_url()

    config =
      unit_policy_config()
      |> Map.put("sinks", [
        %{
          "id" => "alerts",
          "kind" => "memory_alert",
          "select" => %{"types" => ["policy.alert"]},
          "delivery" => %{"capacity" => 8, "on_full" => "fail_closed"}
        },
        %{
          "id" => "jsonl-audit",
          "kind" => "jsonl_file",
          "select" => %{"types" => ["policy.*", "receipt.finalized"]},
          "redaction" => "metadata",
          "delivery" => %{"path" => jsonl_path}
        },
        %{
          "id" => "ops-webhook",
          "kind" => "webhook",
          "select" => %{"types" => ["policy.alert"]},
          "redaction" => "metadata",
          "delivery" => %{"url" => webhook_url, "timeout_ms" => 1_000}
        }
      ])
      |> Map.put("governance", [
        %{
          "id" => "always-alert",
          "kind" => "request_guard",
          "action" => "alert_async",
          "contains" => "alert me",
          "message" => "operator review requested",
          "severity" => "warning"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        model: "unit-model",
        messages: [%{role: "user", content: "alert me raw-private-prompt"}]
      })

    assert conn.status == 200
    assert_receive {:sink_webhook, %{"type" => "policy.alert", "redaction" => "metadata"}}

    second =
      call(:post, "/v1/chat/completions", %{
        model: "unit-model",
        messages: [%{role: "user", content: "alert me raw-private-prompt"}]
      })

    assert second.status == 200
    assert_receive {:sink_webhook, %{"type" => "policy.alert", "redaction" => "metadata"}}

    jsonl_events =
      jsonl_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert jsonl_events |> Enum.count(&(&1["type"] == "policy.alert")) == 2
    assert jsonl_events |> Enum.count(&(&1["type"] == "receipt.finalized")) == 2
    refute File.read!(jsonl_path) =~ "raw-private-prompt"

    status = call(:get, "/admin/sinks") |> Map.fetch!(:resp_body) |> Jason.decode!()
    assert %{"data" => sinks} = status
    assert Enum.find(sinks, &(&1["id"] == "jsonl-audit"))["delivered_count"] == 4
    assert Enum.find(sinks, &(&1["id"] == "ops-webhook"))["delivered_count"] == 2
  after
    :persistent_term.erase({Wardwright.Test.SinkWebhook, :pid})
  end

  test "sink telemetry metrics expose dashboard history chart inputs" do
    metric_names = Enum.map(WardwrightWeb.Telemetry.metrics(), & &1.name)

    assert [:wardwright, :sinks, :queue_depth] in metric_names
    assert [:wardwright, :sinks, :queue_capacity] in metric_names
    assert [:wardwright, :sinks, :queue_utilization] in metric_names
    assert [:wardwright, :sinks, :delivery, :count] in metric_names
    assert [:wardwright, :sinks, :delivery, :duration] in metric_names
  end

  test "sink delivery emits latency and queue utilization telemetry" do
    test_pid = self()
    handler_id = "sink-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [[:wardwright, :sinks, :delivery], [:wardwright, :sinks, :queue_depth]],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:sink_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Wardwright.Sinks.reset()
    end)

    Wardwright.Sinks.configure([
      %{
        "id" => "alerts",
        "kind" => "memory_alert",
        "select" => %{"types" => ["policy.alert"]},
        "delivery" => %{"capacity" => 2, "on_full" => "dead_letter"}
      }
    ])

    assert [
             %{
               "sink_id" => "alerts",
               "kind" => "memory_alert",
               "outcome" => "queued"
             }
           ] =
             Wardwright.Sinks.emit([
               %{
                 "type" => "policy.alert",
                 "rule_id" => "always-alert",
                 "message" => "operator review requested",
                 "severity" => "warning"
               }
             ])

    assert_receive {:sink_telemetry, [:wardwright, :sinks, :delivery], measurements,
                    %{sink_id: "alerts", kind: "memory_alert", outcome: "queued"}}

    assert measurements.count == 1
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0

    assert_receive {:sink_telemetry, [:wardwright, :sinks, :queue_depth],
                    %{depth: 1, capacity: 2, utilization: 0.5},
                    %{sink_id: "alerts", kind: "memory_alert"}}
  end

  defp webhook_url do
    ref = :"wardwright_sink_webhook_#{System.unique_integer([:positive])}"
    :persistent_term.put({Wardwright.Test.SinkWebhook, :pid}, self())
    {:ok, _pid} = Plug.Cowboy.http(Wardwright.Test.SinkWebhook, [], ref: ref, port: 0)
    port = :ranch.get_port(ref)
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    "http://127.0.0.1:#{port}/"
  end
end
