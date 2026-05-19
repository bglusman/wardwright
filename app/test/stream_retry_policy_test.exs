defmodule Wardwright.StreamRetryPolicyTest do
  use Wardwright.RouterCase

  alias Wardwright.Runtime.Events

  test "stream policy retry_with_reminder restarts generation before release" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 256, "model" => "large/model"}
      ])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "deprecated-client-retry",
          "max_retries" => 1,
          "reminder" => "Use NewClient instead."
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        metadata: %{"mock_stream_attempt_chunks" => [["use OldClient(", "arg) now"], ["use NewClient(", "arg) now"]]},
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "NewClient("
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    stream_policy = get_in(receipt, ["final", "stream_policy"])

    assert stream_policy["status"] == "completed"
    assert stream_policy["retry_count"] == 1
    assert stream_policy["max_retries"] == 1
    assert stream_policy["released_to_consumer"] == true
    assert stream_policy["released_bytes"] > 0
    assert stream_policy["held_bytes"] == 0

    assert [
             %{
               "generated_bytes" => generated_bytes,
               "held_bytes" => held_bytes,
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             },
             %{"released_to_consumer" => true, "status" => "completed"}
           ] = stream_policy["attempts"]

    assert held_bytes > 0
    assert generated_bytes > 0

    assert [
             %{
               "action" => "retry_with_reminder",
               "rule_id" => "deprecated-client-retry",
               "type" => "stream_policy.triggered"
             },
             %{
               "reminder" => "Use NewClient instead.",
               "retry_count" => 1,
               "rule_id" => "deprecated-client-retry",
               "type" => "attempt.retry_requested"
             }
           ] = stream_policy["events"]
  end

  test "stream policy retry calls the selected provider again before releasing bytes" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_attempt_chunks" => [["use Old", "Client(arg) now"], ["use NewClient(", "arg) now"]],
          "context_window" => 256,
          "model" => "canned/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "deprecated-client-provider-retry",
          "max_retries" => 1,
          "reminder" => "Use NewClient instead."
        }
      ])

    assert :ok = Events.subscribe(Events.topic(:models))
    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "NewClient("
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    stream_policy =
      receipt_id |> Wardwright.ReceiptStore.get() |> get_in(["final", "stream_policy"])

    assert stream_policy["status"] == "completed"
    assert stream_policy["retry_count"] == 1
    assert stream_policy["released_to_consumer"] == true

    assert [
             %{
               "attempt_index" => 0,
               "called_provider" => true,
               "mock" => false,
               "provider_status" => "cancelled",
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             },
             %{
               "attempt_index" => 1,
               "called_provider" => true,
               "mock" => false,
               "provider_status" => "completed",
               "released_to_consumer" => true,
               "status" => "completed"
             }
           ] = stream_policy["attempts"]

    assert_receive {:wardwright_runtime_event, "runtime:models",
                    %{
                      "model" => "canned/model",
                      "provider_id" => "canned",
                      "stream" => true,
                      "type" => "provider.attempt.started"
                    }}

    assert_receive {:wardwright_runtime_event, "runtime:models",
                    %{
                      "model" => "canned/model",
                      "provider_id" => "canned",
                      "status" => "cancelled",
                      "type" => "provider.attempt.finished"
                    }}

    assert_receive {:wardwright_runtime_event, "runtime:models",
                    %{
                      "model" => "canned/model",
                      "provider_id" => "canned",
                      "stream" => true,
                      "type" => "provider.attempt.started"
                    }}

    assert_receive {:wardwright_runtime_event, "runtime:models",
                    %{
                      "model" => "canned/model",
                      "provider_id" => "canned",
                      "status" => "completed",
                      "type" => "provider.attempt.finished"
                    }}
  end
end
