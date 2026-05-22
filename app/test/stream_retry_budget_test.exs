defmodule Wardwright.StreamRetryBudgetTest do
  use Wardwright.RouterCase

  test "stream policy retry budget exhaustion keeps violating bytes unreleased" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 256, "model" => "large/model"}
      ])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "deprecated-client-budget",
          "max_retries" => 1,
          "reminder" => "Use NewClient instead."
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        metadata: %{"mock_stream_attempt_chunks" => [["use OldClient(", "arg) now"], ["still OldClient(", "arg) now"]]},
        model: "unit-model",
        stream: true
      })

    assert conn.status == 409
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "stream_policy_retry_required"
    assert get_in(body, ["wardwright", "stream_policy", "released_to_consumer"]) == false
    refute conn.resp_body =~ "data:"

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    stream_policy = get_in(receipt, ["final", "stream_policy"])

    assert stream_policy["retry_count"] == 1
    assert stream_policy["max_retries"] == 1
    assert stream_policy["released_to_consumer"] == false
    assert stream_policy["held_bytes"] > 0
    assert stream_policy["generated_bytes"] > 0
    assert stream_policy["released_bytes"] == 0

    assert [
             %{
               "generated_bytes" => first_attempt_bytes,
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             },
             %{
               "generated_bytes" => second_attempt_bytes,
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             }
           ] = stream_policy["attempts"]

    assert first_attempt_bytes > 0
    assert second_attempt_bytes > 0
  end

  test "stream policy retry budgets are scoped to the triggered rule" do
    config =
      unit_policy_config()
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "deprecated-client-no-retry",
          "max_retries" => 0,
          "reminder" => "Use NewClient instead."
        },
        %{
          "action" => "retry_with_reminder",
          "contains" => "OtherClient(",
          "id" => "unrelated-generous-retry",
          "max_retries" => 3,
          "reminder" => "Use ThirdClient instead."
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

    assert conn.status == 409
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["wardwright", "stream_policy", "max_retries"]) == 0
    assert get_in(body, ["wardwright", "stream_policy", "retry_count"]) == 0
    assert get_in(body, ["wardwright", "stream_policy", "released_to_consumer"]) == false

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert [
             %{
               "action" => "retry_with_reminder",
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             }
           ] = get_in(receipt, ["final", "stream_policy", "attempts"])
  end

  test "stream retry fails closed when reminder injection exceeds the selected context window" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_attempt_chunks" => [["use OldClient(", "arg) now"], ["use NewClient(", "arg) now"]],
          "context_window" => 8,
          "model" => "tiny-stream/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "oversized-reminder-retry",
          "max_retries" => 1,
          "reminder" => String.duplicate("Use NewClient instead. ", 20)
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "small", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 422
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    refute conn.resp_body =~ "data:"
    refute conn.resp_body =~ "NewClient("

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "stream_policy_retry_context_exceeded"

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    stream_policy =
      receipt_id |> Wardwright.ReceiptStore.get() |> get_in(["final", "stream_policy"])

    assert stream_policy["status"] == "stream_policy_retry_context_exceeded"
    assert stream_policy["retry_count"] == 0

    assert [
             %{
               "provider_status" => "cancelled",
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             }
           ] = stream_policy["attempts"]

    assert Enum.any?(stream_policy["events"], fn event ->
             event["type"] == "attempt.retry_context_exceeded" and
               event["selected_model"] == "tiny-stream/model" and
               event["context_window"] == 8 and
               event["estimated_prompt_tokens"] > 8
           end)
  end

  test "stream retry reroutes before release when reminder exceeds first selected context" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_attempt_chunks" => [["use OldClient(", "arg) now"]],
          "context_window" => 8,
          "model" => "tiny-stream/model",
          "provider_kind" => "canned_sequence"
        },
        %{
          "canned_stream_attempt_chunks" => [[], ["use NewClient(", "arg) now"]],
          "context_window" => 256,
          "model" => "large-stream/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "reroute-reminder-retry",
          "max_retries" => 1,
          "reminder" => String.duplicate("Use NewClient instead. ", 4)
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "small", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert get_resp_header(conn, "x-wardwright-selected-model") == ["large-stream/model"]
    assert conn.resp_body =~ "NewClient("
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    assert get_in(receipt, ["attempts", Access.at(0), "model"]) == "large-stream/model"
    assert get_in(receipt, ["final", "selected_model"]) == "large-stream/model"

    assert [
             %{
               "estimated_prompt_tokens" => estimated_prompt_tokens,
               "from_context_window" => 8,
               "from_model" => "tiny-stream/model",
               "phase" => "stream_retry",
               "reason" => "retry_prompt_exceeded_selected_context",
               "to_context_window" => 256,
               "to_model" => "large-stream/model"
             }
           ] = get_in(receipt, ["final", "route_transitions"])

    assert estimated_prompt_tokens > 8

    stream_policy = get_in(receipt, ["final", "stream_policy"])

    assert stream_policy["status"] == "completed"
    assert stream_policy["retry_count"] == 1

    assert [
             %{
               "released_to_consumer" => false,
               "selected_model" => "tiny-stream/model",
               "status" => "stream_policy_retry_required"
             },
             %{
               "released_to_consumer" => true,
               "selected_model" => "large-stream/model",
               "status" => "completed"
             }
           ] = stream_policy["attempts"]

    assert Enum.any?(stream_policy["events"], fn event ->
             event["type"] == "attempt.retry_rerouted" and
               event["from_selected_model"] == "tiny-stream/model" and
               event["selected_model"] == "large-stream/model" and
               event["estimated_prompt_tokens"] > 8
           end)
  end
end
