defmodule Wardwright.AlertDeliveryPolicyTest do
  use Wardwright.RouterCase

  alias Wardwright.Policy.AlertDelivery
  alias Wardwright.Runtime.Events

  test "alert delivery backpressure can fail closed before provider invocation" do
    config =
      unit_policy_config()
      |> Map.put("alert_delivery", %{"capacity" => 0, "on_full" => "fail_closed"})
      |> Map.put("governance", [
        %{
          "action" => "alert_async",
          "contains" => "alert me",
          "id" => "always-alert",
          "kind" => "request_guard",
          "message" => "alert queue full"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "alert me", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 429
    body = Jason.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "policy_failed_closed"
    assert [%{"outcome" => "failed_closed"}] = get_in(body, ["wardwright", "alert_delivery"])
  end

  test "successful alert delivery records queued receipts without failing closed" do
    config =
      unit_policy_config()
      |> Map.put("alert_delivery", %{"capacity" => 4, "on_full" => "fail_closed"})
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
        messages: [%{content: "alert me", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert [
             %{
               "idempotency_key" => ":always-alert:operator review requested:warning",
               "outcome" => "queued",
               "rule_id" => "always-alert"
             }
           ] = get_in(body, ["wardwright", "alert_delivery"])

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()

    assert [
             %{
               "message" => "operator review requested",
               "rule_id" => "always-alert",
               "severity" => "warning",
               "type" => "policy.alert"
             }
           ] = get_in(receipt, ["final", "events"])
  end

  test "alert delivery exposes queue health and publishes delivery events" do
    AlertDelivery.configure(%{"capacity" => 1, "on_full" => "dead_letter"})
    assert :ok = Events.subscribe(Events.topic(:policies))

    results =
      AlertDelivery.deliver([
        %{
          "message" => "first",
          "rule_id" => "first-alert",
          "severity" => "warning",
          "type" => "policy.alert"
        },
        %{
          "message" => "second",
          "rule_id" => "second-alert",
          "severity" => "warning",
          "type" => "policy.alert"
        }
      ])

    assert [%{"outcome" => "queued"}, %{"outcome" => "dead_lettered"}] = results

    assert %{
             "capacity" => 1,
             "dead_letter_count" => 1,
             "kind" => "in_memory_alert_sink",
             "last_result" => %{"outcome" => "dead_lettered", "rule_id" => "second-alert"},
             "on_full" => "dead_letter",
             "queue_depth" => 1,
             "queued_count" => 1
           } = AlertDelivery.status()

    assert_receive {:wardwright_runtime_event, "runtime:policies",
                    %{
                      "capacity" => 1,
                      "outcome" => "queued",
                      "queue_depth" => 1,
                      "rule_id" => "first-alert",
                      "type" => "policy_alert.delivery"
                    }}

    assert_receive {:wardwright_runtime_event, "runtime:policies",
                    %{
                      "capacity" => 1,
                      "outcome" => "dead_lettered",
                      "queue_depth" => 1,
                      "rule_id" => "second-alert",
                      "type" => "policy_alert.delivery"
                    }}
  end

  test "admin policy alert status is protected and exposes sink health" do
    assert call(:get, "/admin/policy-alerts", nil, [], {203, 0, 113, 10}).status == 403

    conn = call(:get, "/admin/policy-alerts")
    assert conn.status == 200
    assert %{"kind" => "in_memory_alert_sink", "queue_depth" => 0} = Jason.decode!(conn.resp_body)
  end

  test "admin sink status is protected and exposes all configured sinks" do
    assert call(:get, "/admin/sinks", nil, [], {203, 0, 113, 10}).status == 403

    conn = call(:get, "/admin/sinks")
    assert conn.status == 200

    assert %{"data" => [%{"id" => "policy-alerts", "kind" => "in_memory_alert_sink"}]} =
             Jason.decode!(conn.resp_body)
  end

  test "alert fail-closed blocks streaming and simulation paths consistently" do
    config =
      unit_policy_config()
      |> Map.put("alert_delivery", %{"capacity" => 0, "on_full" => "fail_closed"})
      |> Map.put("governance", [
        %{
          "action" => "alert_async",
          "contains" => "alert me",
          "id" => "stream-alert",
          "kind" => "request_guard"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    stream =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "alert me", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert stream.status == 429
    assert get_resp_header(stream, "content-type") == ["application/json; charset=utf-8"]

    assert get_in(Jason.decode!(stream.resp_body), ["wardwright", "status"]) ==
             "policy_failed_closed"

    assert call(:post, "/__test/config", config).status == 200

    simulated =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "alert me", role: "user"}],
          model: "unit-model"
        }
      })

    assert simulated.status == 200

    assert get_in(Jason.decode!(simulated.resp_body), ["receipt", "final", "status"]) ==
             "policy_failed_closed"
  end
end
