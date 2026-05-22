defmodule Wardwright.Test.SinkWebhook do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    send(:persistent_term.get({__MODULE__, :pid}), {:sink_webhook, JSON.decode!(body)})
    Plug.Conn.send_resp(conn, 204, "")
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end

defmodule Wardwright.SinkAdaptersTest do
  use Wardwright.RouterCase

  alias Wardwright.Policy.AlertDelivery
  alias Wardwright.Test.SinkWebhook

  test "configured sinks independently receive selected metadata events" do
    jsonl_path =
      Path.join(
        System.tmp_dir!(),
        "wardwright-sinks-#{System.unique_integer([:positive, :monotonic])}.jsonl"
      )

    File.rm(jsonl_path)
    webhook_url = webhook_url()

    config =
      unit_policy_config()
      |> Map.put("sinks", [
        %{
          "delivery" => %{"capacity" => 8, "on_full" => "fail_closed"},
          "id" => "alerts",
          "kind" => "memory_alert",
          "select" => %{"types" => ["policy.alert"]}
        },
        %{
          "delivery" => %{"path" => jsonl_path},
          "id" => "jsonl-audit",
          "kind" => "jsonl_file",
          "redaction" => "metadata",
          "select" => %{"types" => ["policy.*", "receipt.finalized"]}
        },
        %{
          "delivery" => %{"timeout_ms" => 1_000, "url" => webhook_url},
          "id" => "ops-webhook",
          "kind" => "webhook",
          "redaction" => "metadata",
          "select" => %{"types" => ["policy.alert"]}
        }
      ])
      |> Map.put("governance", [
        %{
          "action" => "alert_async",
          "contains" => "alert me",
          "id" => "always-alert",
          "kind" => "request_guard",
          "message" => "operator review requested",
          "severity" => "warning"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "alert me raw-private-prompt", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200
    assert_receive {:sink_webhook, %{"redaction" => "metadata", "type" => "policy.alert"}}

    second =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "alert me raw-private-prompt", role: "user"}],
        model: "unit-model"
      })

    assert second.status == 200
    assert_receive {:sink_webhook, %{"redaction" => "metadata", "type" => "policy.alert"}}

    jsonl_events =
      jsonl_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert jsonl_events |> Enum.count(&(&1["type"] == "policy.alert")) == 2
    assert jsonl_events |> Enum.count(&(&1["type"] == "receipt.finalized")) == 2
    refute File.read!(jsonl_path) =~ "raw-private-prompt"

    status = call(:get, "/admin/sinks") |> Map.fetch!(:resp_body) |> JSON.decode!()
    assert %{"data" => sinks} = status
    assert Enum.find(sinks, &(&1["id"] == "jsonl-audit"))["delivered_count"] == 4
    assert Enum.find(sinks, &(&1["id"] == "ops-webhook"))["delivered_count"] == 2
  after
    :persistent_term.erase({SinkWebhook, :pid})
    Wardwright.Sinks.reset()
  end

  test "failed durable sink delivery does not suppress later retries as duplicates" do
    not_a_dir = Path.join(System.tmp_dir!(), "wardwright-sink-parent-#{System.unique_integer()}")
    on_exit(fn -> File.rm(not_a_dir) end)
    File.write!(not_a_dir, "not a directory")

    Wardwright.Sinks.configure([
      %{
        "delivery" => %{"path" => Path.join(not_a_dir, "events.jsonl")},
        "id" => "jsonl-audit",
        "kind" => "jsonl_file",
        "select" => %{"types" => ["policy.alert"]}
      }
    ])

    event = %{
      "message" => "operator review requested",
      "rule_id" => "always-alert",
      "severity" => "warning",
      "type" => "policy.alert"
    }

    assert [%{"outcome" => "dead_lettered"}] = Wardwright.Sinks.emit([event])
    assert [%{"outcome" => "dead_lettered"}] = Wardwright.Sinks.emit([event])
  after
    Wardwright.Sinks.reset()
  end

  test "sink normalization rejects unsupported sink kinds" do
    assert [
             %{"id" => "alerts", "kind" => "memory_alert"}
           ] =
             Wardwright.Sinks.normalize_config([
               %{"id" => "bad", "kind" => "webhok"},
               %{"id" => "alerts", "kind" => "memory_alert"}
             ])
  end

  test "legacy alert delivery settings still update the default memory sink" do
    config =
      Wardwright.default_config()
      |> Map.put("alert_delivery", %{"capacity" => 0, "on_full" => "fail_closed"})
      |> Wardwright.normalize_config()

    assert %{
             "delivery" => %{"capacity" => 0, "on_full" => "fail_closed"}
           } = Enum.find(config["sinks"], &(&1["id"] == "policy-alerts"))
  end

  test "fail-closed policy alert sinks are visible to legacy alert delivery callers" do
    Wardwright.Sinks.configure([
      %{
        "delivery" => %{"on_error" => "fail_closed", "url" => "http://127.0.0.1:1/"},
        "id" => "webhook-alerts",
        "kind" => "webhook",
        "select" => %{"types" => ["policy.alert"]}
      }
    ])

    results =
      AlertDelivery.deliver([
        %{
          "message" => "operator review requested",
          "rule_id" => "always-alert",
          "severity" => "warning",
          "type" => "policy.alert"
        }
      ])

    assert [%{"kind" => "webhook", "outcome" => "failed_closed"}] = results
    assert AlertDelivery.fail_closed?(results)
  after
    Wardwright.Sinks.reset()
  end

  test "sink telemetry metrics expose dashboard history chart inputs" do
    metric_names = Enum.map(WardwrightWeb.Telemetry.metrics(), & &1.name)

    assert [:wardwright, :sinks, :queue_depth] in metric_names
    assert [:wardwright, :sinks, :queue_capacity] in metric_names
    assert [:wardwright, :sinks, :queue_utilization] in metric_names
    assert [:wardwright, :sinks, :delivery, :count] in metric_names
    assert [:wardwright, :sinks, :delivery, :duration] in metric_names
    assert [:wardwright, :model, :requests, :count] in metric_names
    assert [:wardwright, :model, :tokens, :estimated_prompt] in metric_names
    assert [:wardwright, :model, :tokens, :prompt] in metric_names
    assert [:wardwright, :model, :tokens, :completion] in metric_names
    assert [:wardwright, :model, :tokens, :total] in metric_names
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
        "delivery" => %{"capacity" => 2, "on_full" => "dead_letter"},
        "id" => "alerts",
        "kind" => "memory_alert",
        "select" => %{"types" => ["policy.alert"]}
      }
    ])

    assert [
             %{
               "kind" => "memory_alert",
               "outcome" => "queued",
               "sink_id" => "alerts"
             }
           ] =
             Wardwright.Sinks.emit([
               %{
                 "message" => "operator review requested",
                 "rule_id" => "always-alert",
                 "severity" => "warning",
                 "type" => "policy.alert"
               }
             ])

    assert_receive {:sink_telemetry, [:wardwright, :sinks, :delivery], measurements,
                    %{kind: "memory_alert", outcome: "queued", sink_id: "alerts"}}

    assert measurements.count == 1
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0

    assert_receive {:sink_telemetry, [:wardwright, :sinks, :queue_depth], %{capacity: 2, depth: 1, utilization: 0.5},
                    %{kind: "memory_alert", sink_id: "alerts"}}
  end

  test "receipt sink events emit simple model usage telemetry" do
    test_pid = self()
    handler_id = "model-usage-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:wardwright, :model, :usage],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:model_usage_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Wardwright.Sinks.reset()
    end)

    Wardwright.Sinks.configure([
      %{
        "delivery" => %{"path" => Path.join(System.tmp_dir!(), "wardwright-usage-#{System.unique_integer()}.jsonl")},
        "id" => "jsonl-audit",
        "kind" => "jsonl_file",
        "select" => %{"types" => ["receipt.finalized"]}
      }
    ])

    assert [
             %{
               "event_type" => "receipt.finalized",
               "kind" => "jsonl_file",
               "outcome" => "delivered",
               "sink_id" => "jsonl-audit"
             }
           ] =
             Wardwright.Sinks.emit([
               %{
                 "completion_tokens" => 7,
                 "estimated_prompt_tokens" => 11,
                 "prompt_tokens" => 12,
                 "receipt_id" => "rcpt_usage_1",
                 "selected_model" => "managed/kimi",
                 "selected_provider" => "managed",
                 "simulation" => false,
                 "status" => "completed",
                 "total_tokens" => 19,
                 "type" => "receipt.finalized"
               }
             ])

    assert_receive {:model_usage_telemetry, [:wardwright, :model, :usage], measurements,
                    %{
                      selected_model: "managed/kimi",
                      selected_provider: "managed",
                      simulation: false,
                      status: "completed"
                    }}

    assert measurements == %{
             completion_tokens: 7,
             count: 1,
             estimated_prompt_tokens: 11,
             prompt_tokens: 12,
             total_tokens: 19
           }
  end

  defp webhook_url do
    ref = {:wardwright_sink_webhook, System.unique_integer([:positive])}
    :persistent_term.put({SinkWebhook, :pid}, self())
    {:ok, _pid} = Plug.Cowboy.http(SinkWebhook, [], ref: ref, port: 0)
    port = :ranch.get_port(ref)
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    "http://127.0.0.1:#{port}/"
  end
end
