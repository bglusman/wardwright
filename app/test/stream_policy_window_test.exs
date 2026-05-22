defmodule Wardwright.StreamPolicyWindowTest do
  use Wardwright.RouterCase

  test "stream policy rewrites matched chunks before release and records receipt evidence" do
    config =
      unit_policy_config()
      |> Map.put("stream_rules", [
        %{
          "action" => "rewrite_chunk",
          "contains" => "OldClient(",
          "id" => "deprecated-client",
          "replacement" => "NewClient("
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        metadata: %{"mock_stream_chunks" => ["use OldClient(", "arg) now"]},
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert conn.resp_body =~ "NewClient("
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["final", "stream_trigger_count"]) == 1
    assert get_in(receipt, ["final", "stream_policy_action"]) == "rewrite_chunk"
    assert get_in(receipt, ["final", "stream_policy", "released_to_consumer"]) == true

    assert [
             %{
               "action" => "rewrite_chunk",
               "chunk_index" => 0,
               "rule_id" => "deprecated-client"
             }
           ] = get_in(receipt, ["final", "stream_policy", "events"])
  end

  test "stream policy block returns fail-closed JSON instead of SSE" do
    config =
      unit_policy_config()
      |> Map.put("stream_rules", [
        %{
          "action" => "block",
          "id" => "secret-stream",
          "regex" => "secret-[0-9]+"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        metadata: %{"mock_stream_chunks" => ["safe prefix ", "secret-123"]},
        model: "unit-model",
        stream: true
      })

    assert conn.status == 422
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "stream_policy_blocked"
    assert get_in(body, ["wardwright", "selected_model"]) == "tiny/model"
    assert get_in(body, ["wardwright", "stream_policy", "released_to_consumer"]) == false
    assert get_in(body, ["wardwright", "stream_policy", "generated_bytes"]) > 0
    assert get_in(body, ["wardwright", "stream_policy", "held_bytes"]) > 0
    assert get_in(body, ["wardwright", "stream_policy", "released_bytes"]) == 0

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["final", "stream_policy", "released_to_consumer"]) == false
    assert get_in(receipt, ["final", "stream_policy", "released_bytes"]) == 0

    assert get_in(receipt, ["final", "stream_policy", "events", Access.at(0), "rule_id"]) ==
             "secret-stream"
  end

  test "stream policy detects terminal regex matches split across chunks before release" do
    config =
      unit_policy_config()
      |> Map.put("stream_rules", [
        %{
          "action" => "block",
          "id" => "split-secret-stream",
          "regex" => "secret-[0-9]+"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        metadata: %{"mock_stream_chunks" => ["safe prefix sec", "ret-123 suffix"]},
        model: "unit-model",
        stream: true
      })

    assert conn.status == 422
    refute conn.resp_body =~ "text/event-stream"

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "stream_policy_blocked"
    assert get_in(body, ["wardwright", "stream_policy", "released_to_consumer"]) == false
    assert get_in(body, ["wardwright", "stream_policy", "trigger_count"]) == 1
    assert get_in(body, ["wardwright", "stream_policy", "released_bytes"]) == 0

    assert [
             %{
               "action" => "block",
               "chunk_index" => 1,
               "match_scope" => "stream_window",
               "rule_id" => "split-secret-stream"
             }
           ] = get_in(body, ["wardwright", "stream_policy", "events"])
  end

  test "stream policy retry split-window matches keep pre-trigger bytes unreleased" do
    config =
      unit_policy_config()
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "split-retry-unreleased",
          "max_retries" => 0,
          "reminder" => "Use NewClient instead."
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        metadata: %{"mock_stream_chunks" => ["safe prefix Old", "Client(arg)"]},
        model: "unit-model",
        stream: true
      })

    assert conn.status == 409

    body = JSON.decode!(conn.resp_body)
    stream_policy = get_in(body, ["wardwright", "stream_policy"])

    assert stream_policy["released_to_consumer"] == false
    assert stream_policy["released_bytes"] == 0
    assert stream_policy["held_bytes"] > 0

    assert [
             %{
               "released_bytes" => 0,
               "released_to_consumer" => false,
               "status" => "stream_policy_retry_required"
             }
           ] = stream_policy["attempts"]
  end

  test "stream policy bounded horizon releases old safe bytes while retaining split triggers" do
    result =
      Wardwright.Policy.Stream.evaluate(
        ["safe prefix that can release ", "Old", "Client(arg) now"],
        [
          %{
            "action" => "block",
            "contains" => "OldClient(",
            "horizon_bytes" => byte_size("OldClient("),
            "id" => "bounded-deprecated-client"
          }
        ]
      )

    assert result.status == "stream_policy_blocked"
    assert result.released_bytes > 0
    assert result.held_bytes > byte_size("OldClient(")
    assert result.blocked_bytes == result.held_bytes

    released = Enum.join(result.chunks)
    assert released != ""
    refute released =~ "Old"
    refute released =~ "Client("

    assert [
             %{
               "action" => "block",
               "match_scope" => "stream_window",
               "rule_id" => "bounded-deprecated-client"
             }
           ] = result.events
  end

  test "stream policy trigger events include literal match offsets across split chunks" do
    result =
      Wardwright.Policy.Stream.evaluate(
        ["abc Old", "Client("],
        [
          %{
            "action" => "block",
            "contains" => "OldClient(",
            "horizon_bytes" => byte_size("OldClient("),
            "id" => "offset-split-literal"
          }
        ]
      )

    assert result.status == "stream_policy_blocked"

    assert [
             %{
               "action" => "block",
               "chunk_end_byte" => 14,
               "chunk_index" => 1,
               "chunk_start_byte" => 7,
               "match_end_byte" => 14,
               "match_kind" => "literal",
               "match_scope" => "stream_window",
               "match_start_byte" => 4,
               "rule_id" => "offset-split-literal",
               "stream_window_end_byte" => 14,
               "stream_window_start_byte" => 0,
               "type" => "stream_policy.triggered"
             }
           ] = result.events
  end

  test "stream policy trigger events include regex match offsets across split chunks" do
    result =
      Wardwright.Policy.Stream.evaluate(
        ["abc Old", "Client("],
        [
          %{
            "action" => "block",
            "horizon_bytes" => byte_size("OldClient("),
            "id" => "offset-split-regex",
            "regex" => "OldClient\\("
          }
        ]
      )

    assert result.status == "stream_policy_blocked"

    assert [
             %{
               "action" => "block",
               "chunk_end_byte" => 14,
               "chunk_index" => 1,
               "chunk_start_byte" => 7,
               "match_end_byte" => 14,
               "match_kind" => "regex",
               "match_scope" => "stream_window",
               "match_start_byte" => 4,
               "rule_id" => "offset-split-regex",
               "stream_window_end_byte" => 14,
               "stream_window_start_byte" => 0,
               "type" => "stream_policy.triggered"
             }
           ] = result.events
  end

  test "stream policy offsets stay coherent after earlier rewrites change byte length" do
    result =
      Wardwright.Policy.Stream.evaluate(
        ["ABC", "TAIL"],
        [
          %{
            "action" => "rewrite_chunk",
            "contains" => "ABC",
            "id" => "length-changing-rewrite",
            "replacement" => "LONGER-REPLACEMENT"
          },
          %{
            "action" => "block",
            "contains" => "REPLACEMENTTAIL",
            "id" => "post-rewrite-window"
          }
        ]
      )

    assert result.status == "stream_policy_blocked"

    assert [
             %{
               "match_end_byte" => 3,
               "match_scope" => "chunk",
               "match_start_byte" => 0,
               "rule_id" => "length-changing-rewrite"
             },
             %{
               "chunk_end_byte" => 22,
               "chunk_start_byte" => 18,
               "match_end_byte" => 22,
               "match_scope" => "stream_window",
               "match_start_byte" => 7,
               "rule_id" => "post-rewrite-window",
               "stream_window_end_byte" => 22,
               "stream_window_start_byte" => 0
             }
           ] = result.events
  end
end
