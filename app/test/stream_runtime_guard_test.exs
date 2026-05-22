defmodule Wardwright.StreamRuntimeGuardTest do
  use Wardwright.RouterCase

  test "bounded stream runtime releases safe provider bytes before a later block" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_chunks" => ["safe prefix that can release ", "Old", "Client(arg) now"],
          "context_window" => 256,
          "model" => "canned/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "block",
          "contains" => "OldClient(",
          "horizon_bytes" => byte_size("OldClient("),
          "id" => "bounded-runtime-block"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "safe prefix"
    assert conn.resp_body =~ "stream_policy_blocked"
    refute conn.resp_body =~ "Old"
    refute conn.resp_body =~ "Client("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    stream_policy =
      receipt_id |> Wardwright.ReceiptStore.get() |> get_in(["final", "stream_policy"])

    assert stream_policy["status"] == "stream_policy_blocked"
    assert stream_policy["released_to_consumer"] == false
    assert stream_policy["released_bytes"] > 0
    assert stream_policy["held_bytes"] > 0

    assert [
             %{
               "called_provider" => true,
               "mock" => false,
               "released_bytes" => released_bytes,
               "status" => "stream_policy_blocked"
             }
           ] = stream_policy["attempts"]

    assert released_bytes > 0
  end

  test "bounded stream runtime skips retry once safe bytes have already reached SSE client" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_chunks" => ["safe prefix that can release ", "Old", "Client(arg) now"],
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
          "horizon_bytes" => byte_size("OldClient("),
          "id" => "bounded-runtime-retry",
          "max_retries" => 1,
          "reminder" => "Use NewClient instead."
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "safe prefix"
    assert conn.resp_body =~ "stream_policy_retry_skipped_after_release"
    refute conn.resp_body =~ "Old"
    refute conn.resp_body =~ "Client("
    refute conn.resp_body =~ "NewClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    stream_policy =
      receipt_id |> Wardwright.ReceiptStore.get() |> get_in(["final", "stream_policy"])

    assert stream_policy["status"] == "stream_policy_retry_skipped_after_release"
    assert stream_policy["retry_count"] == 0
    assert stream_policy["max_retries"] == 1
    assert stream_policy["released_to_consumer"] == false
    assert stream_policy["released_bytes"] > 0

    assert [
             %{
               "provider_status" => "cancelled",
               "released_bytes" => released_bytes,
               "status" => "stream_policy_retry_required"
             }
           ] = stream_policy["attempts"]

    assert released_bytes > 0

    assert Enum.any?(stream_policy["events"], fn event ->
             event["type"] == "attempt.retry_skipped_after_release" and
               event["reason"] == "response_already_started" and
               event["rule_id"] == "bounded-runtime-retry" and
               event["released_bytes"] > 0
           end)
  end

  test "bounded stream runtime terminates SSE when provider fails after safe release" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_chunks" => ["safe prefix before provider error "],
          "canned_stream_error" => "wardwright stream failure",
          "context_window" => 256,
          "model" => "canned/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "block",
          "contains" => "OldClient(",
          "horizon_bytes" => 1,
          "id" => "bounded-runtime-pass-through"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "safe prefix"
    assert conn.resp_body =~ "provider_error"
    assert conn.resp_body =~ "data: [DONE]"

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["final", "status"]) == "provider_error"
    assert get_in(receipt, ["final", "provider_error"]) == "wardwright stream failure"
  end

  test "provider runtime drains queued chunks after policy halt" do
    parent = self()

    task =
      Task.async(fn ->
        target = %{"model" => "test/provider", "provider_timeout_ms" => 1_000}

        result =
          Wardwright.ProviderRuntime.stream_each(
            target,
            %{},
            fn emit ->
              Enum.each(1..50, fn index -> emit.("chunk #{index}") end)
              send(parent, :provider_emitted_chunks)
              Process.sleep(50)
              {:ok, :done}
            end,
            0,
            fn _chunk, acc -> {:halt, acc + 1} end
          )

        Process.sleep(10)
        {result, Process.info(self(), :messages)}
      end)

    assert {{{:halted, :cancelled}, 1}, {:messages, []}} = Task.await(task)
    assert_receive :provider_emitted_chunks
  end

  test "mock stream cancellation is recorded as mock without provider call" do
    request = %{"model" => "unit-model", "stream" => true}

    {provider, acc} =
      Wardwright.stream_selected_model_each(
        "missing/model",
        request,
        [],
        fn chunk, acc ->
          {:halt, acc ++ [chunk]}
        end,
        unit_policy_config()
      )

    assert provider.status == "cancelled"
    assert provider.called_provider == false
    assert provider.mock == true
    assert acc == ["Mock Wardwright stream "]
  end

  test "stream rewrite rules can match across provider chunk boundaries" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_stream_chunks" => ["call Old", "Client(arg) now"],
          "context_window" => 256,
          "model" => "canned/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "rewrite_chunk",
          "contains" => "OldClient(",
          "id" => "deprecated-client-provider-rewrite",
          "replacement" => "NewClient("
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert conn.resp_body =~ "NewClient("
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    stream_policy =
      receipt_id |> Wardwright.ReceiptStore.get() |> get_in(["final", "stream_policy"])

    assert stream_policy["released_to_consumer"] == true

    assert [
             %{
               "action" => "rewrite_chunk",
               "attempt_index" => 0,
               "called_provider" => true,
               "generated_bytes" => generated_bytes,
               "mock" => false,
               "provider_status" => "completed",
               "released_bytes" => released_bytes,
               "released_to_consumer" => true,
               "rewritten_bytes" => rewritten_bytes,
               "status" => "completed",
               "trigger_count" => 1
             }
           ] = stream_policy["attempts"]

    assert generated_bytes > 0
    assert released_bytes > 0
    assert rewritten_bytes > 0

    assert [
             %{
               "action" => "rewrite_chunk",
               "chunk_index" => 1,
               "match_scope" => "stream_window",
               "rule_id" => "deprecated-client-provider-rewrite"
             }
           ] = stream_policy["events"]
  end

  test "stream provider timeouts fail closed without emitting SSE bytes" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_delay_ms" => 25,
          "canned_stream_chunks" => ["late stream"],
          "context_window" => 256,
          "model" => "slow-stream/model",
          "provider_kind" => "canned_sequence",
          "provider_timeout_ms" => 1
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 502
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    refute conn.resp_body =~ "data:"

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "provider_error"
    assert get_in(body, ["wardwright", "provider_error"]) =~ "provider timed out after 1ms"

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()
    stream_policy = get_in(receipt, ["final", "stream_policy"])

    assert stream_policy["released_to_consumer"] == false

    assert [
             %{
               "called_provider" => true,
               "mock" => false,
               "provider_error" => provider_error,
               "provider_status" => "provider_error",
               "status" => "provider_error"
             }
           ] = stream_policy["attempts"]

    assert provider_error =~ "provider timed out after 1ms"
  end

  test "stream latency budget fails closed before releasing over-held provider bytes" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_delay_ms" => 15,
          "canned_stream_chunks" => ["held", " later"],
          "context_window" => 256,
          "model" => "slow-hold/model",
          "provider_kind" => "canned_sequence",
          "provider_timeout_ms" => 1_000
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "block",
          "contains" => "OldClient(",
          "horizon_bytes" => byte_size("OldClient("),
          "id" => "slow-held-window",
          "max_hold_ms" => 1
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 422
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    refute conn.resp_body =~ "data:"

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "stream_policy_latency_exceeded"

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()
    stream_policy = get_in(receipt, ["final", "stream_policy"])

    assert stream_policy["status"] == "stream_policy_latency_exceeded"
    assert stream_policy["released_to_consumer"] == false
    assert stream_policy["released_bytes"] == 0
    assert stream_policy["max_hold_ms"] == 1
    assert stream_policy["max_observed_hold_ms"] >= 1

    assert [
             %{
               "max_hold_ms" => 1,
               "provider_status" => "cancelled",
               "released_to_consumer" => false,
               "status" => "stream_policy_latency_exceeded"
             }
           ] = stream_policy["attempts"]

    assert Enum.any?(stream_policy["events"], fn event ->
             event["type"] == "stream_policy.latency_exceeded" and
               event["max_hold_ms"] == 1 and
               event["observed_hold_ms"] >= 1
           end)
  end
end
