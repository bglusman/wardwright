defmodule Wardwright.StreamProviderTransportTest do
  use Wardwright.RouterCase

  test "ollama stream targets use provider HTTP chunks for stream policy decisions" do
    base_url = streaming_provider_base_url("/ollama")

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "model" => "ollama/live-test",
          "provider_base_url" => base_url
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "ollama-stream-split-retry",
          "max_retries" => 0,
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

    assert conn.status == 409

    body = JSON.decode!(conn.resp_body)
    stream_policy = get_in(body, ["wardwright", "stream_policy"])

    assert get_in(body, ["wardwright", "status"]) == "stream_policy_retry_required"
    assert stream_policy["released_to_consumer"] == false
    assert stream_policy["released_bytes"] == 0

    assert [
             %{
               "called_provider" => true,
               "mock" => false,
               "provider_status" => "cancelled",
               "status" => "stream_policy_retry_required"
             }
           ] = stream_policy["attempts"]

    assert [
             %{
               "match_scope" => "stream_window",
               "rule_id" => "ollama-stream-split-retry"
             }
           ] = stream_policy["events"]
  end

  test "ollama stream retry_with_reminder injects the reminder into the next provider request" do
    base_url = streaming_provider_base_url("/ollama")

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "model" => "ollama/live-test",
          "provider_base_url" => base_url
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "contains" => "OldClient(",
          "id" => "ollama-stream-reminder-retry",
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
    assert conn.resp_body =~ "NewClient("
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    receipt = Wardwright.ReceiptStore.get(receipt_id)
    stream_policy = get_in(receipt, ["final", "stream_policy"])

    assert stream_policy["retry_count"] == 1
    assert stream_policy["released_to_consumer"] == true
    assert get_in(receipt, ["final", "provider_metadata", "stream_format"]) == "ollama_ndjson"
    assert get_in(receipt, ["final", "provider_metadata", "done"]) == true
    assert get_in(receipt, ["final", "provider_metadata", "done_reason"]) == "stop"
    assert get_in(receipt, ["final", "provider_metadata", "prompt_eval_count"]) == 4

    assert get_in(receipt, ["attempts", Access.at(0), "provider_metadata", "done_reason"]) ==
             "stop"

    assert [
             %{"released_to_consumer" => false, "status" => "stream_policy_retry_required"},
             %{"released_to_consumer" => true, "status" => "completed"}
           ] = stream_policy["attempts"]

    assert Enum.any?(stream_policy["events"], fn event ->
             event["type"] == "attempt.retry_requested" and
               event["rule_id"] == "ollama-stream-reminder-retry" and
               event["reminder"] == "Use NewClient instead." and
               event["reminder_injected"] == true
           end)
  end

  test "ollama stream targets release bounded safe bytes before cancelling on a later trigger" do
    base_url = streaming_provider_base_url("/ollama")

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "model" => "ollama/live-test",
          "provider_base_url" => base_url
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "block",
          "contains" => "OldClient(",
          "horizon_bytes" => byte_size("OldClient("),
          "id" => "ollama-bounded-stream-block"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "stream safe prefix code", role: "user"}],
        model: "unit-model",
        stream: true
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "safe prefix"
    assert conn.resp_body =~ "stream_policy_blocked"
    refute conn.resp_body =~ "OldClient("

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    stream_policy =
      receipt_id |> Wardwright.ReceiptStore.get() |> get_in(["final", "stream_policy"])

    assert stream_policy["status"] == "stream_policy_blocked"
    assert stream_policy["released_bytes"] > 0

    assert [
             %{
               "called_provider" => true,
               "mock" => false,
               "provider_status" => provider_status
             }
           ] = stream_policy["attempts"]

    assert provider_status in ["cancelled", "provider_error", "completed"]
  end

  test "openai-compatible stream targets parse SSE deltas from provider HTTP chunks" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
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

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    assert conn.resp_body =~ "hello "
    assert conn.resp_body =~ "world"

    indexes =
      conn.resp_body
      |> String.split("\n\n", trim: true)
      |> Enum.map(&(&1 |> String.trim_leading("data:") |> String.trim()))
      |> Enum.reject(&(&1 == "[DONE]"))
      |> Enum.map(&JSON.decode!/1)
      |> Enum.map(&get_in(&1, ["choices", Access.at(0), "index"]))

    assert indexes == [0, 0]

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["attempts", Access.at(0), "called_provider"]) == true
    assert get_in(receipt, ["attempts", Access.at(0), "mock"]) == false
    assert get_in(receipt, ["final", "stream_policy", "released_to_consumer"]) == true
    assert get_in(receipt, ["final", "provider_metadata", "stream_format"]) == "openai_sse"
    assert get_in(receipt, ["final", "provider_metadata", "finish_reason"]) == "stop"
    assert get_in(receipt, ["final", "provider_metadata", "done"]) == true
    assert get_in(receipt, ["final", "provider_metadata", "usage", "total_tokens"]) == 5

    assert get_in(receipt, ["attempts", Access.at(0), "provider_metadata", "finish_reason"]) ==
             "stop"
  end

  test "openai-compatible stream targets preserve tool-call deltas from provider SSE chunks" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "prepare a pull request", role: "user"}],
        model: "unit-model",
        stream: true,
        tool_choice: "auto",
        tools: [%{function: %{name: "create_pull_request", parameters: %{type: "object"}}, type: "function"}]
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream"]
    refute conn.resp_body =~ "hello "
    refute conn.resp_body =~ "world"

    tool_call_deltas =
      conn.resp_body
      |> sse_json_payloads()
      |> Enum.map(&get_in(&1, ["choices", Access.at(0), "delta", "tool_calls"]))
      |> Enum.reject(&is_nil/1)

    assert [
             [
               %{
                 "function" => %{"arguments" => "", "name" => "create_pull_request"},
                 "id" => "call_stream_1",
                 "index" => 0,
                 "type" => "function"
               }
             ],
             [
               %{
                 "function" => %{"arguments" => ~s({"title":"Streamed tools"})},
                 "index" => 0
               }
             ]
           ] = tool_call_deltas

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["final", "stream_policy", "status"]) == "completed"
    assert get_in(receipt, ["final", "provider_metadata", "stream_format"]) == "openai_sse"
    assert get_in(receipt, ["final", "provider_metadata", "finish_reason"]) == "tool_calls"

    assert get_in(receipt, ["final", "provider_metadata", "preserved_delta_fields"]) == [
             "tool_calls"
           ]
  end

  test "openai-compatible targets forward tool request fields and preserve provider tool calls" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [
          %{content: "prepare a pull request", role: "user"},
          %{
            content: nil,
            role: "assistant",
            tool_calls: [%{function: %{arguments: "{}", name: "create_pull_request"}, id: "call_1", type: "function"}]
          },
          %{content: "created", role: "tool", tool_call_id: "call_1"}
        ],
        model: "unit-model",
        tool_choice: "auto",
        tools: [%{function: %{name: "create_pull_request", parameters: %{type: "object"}}, type: "function"}]
      })

    assert conn.status == 200

    body = JSON.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "completed"
    assert get_in(body, ["wardwright", "provider_error"]) == nil

    assert get_in(body, ["choices", Access.at(0), "finish_reason"]) == "tool_calls"

    assert [
             %{
               "function" => %{"arguments" => ~s({"title":"Forwarded tools"}), "name" => "create_pull_request"},
               "id" => "call_forwarded_1",
               "type" => "function"
             }
           ] = get_in(body, ["choices", Access.at(0), "message", "tool_calls"])

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["attempts", Access.at(0), "called_provider"]) == true

    assert get_in(receipt, ["decision", "tool_context", "schema"]) ==
             "wardwright.tool_context.v1"

    assert get_in(receipt, ["decision", "tool_context", "phase"]) == "result_interpretation"
    assert get_in(receipt, ["decision", "tool_context", "tool_call_id"]) == "call_1"
    assert get_in(receipt, ["decision", "tool_context", "confidence"]) == "exact"

    assert get_in(receipt, [
             "decision",
             "tool_context",
             "primary_tool",
             "name"
           ]) == "create_pull_request"

    assert get_in(receipt, [
             "decision",
             "tool_context",
             "primary_tool",
             "source"
           ]) == "assistant_tool_call"

    assert get_in(receipt, ["attempts", Access.at(0), "provider_error"]) == nil
    assert get_in(receipt, ["final", "provider_metadata", "finish_reason"]) == "tool_calls"
    assert get_in(receipt, ["final", "provider_metadata", "usage", "total_tokens"]) == 5
  end

  test "tool mediation can hide agent-declared tools before the provider sees them" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("tool_mediation", %{
        "mode" => "patch",
        "rules" => [
          %{
            "action" => "hide",
            "id" => "hide-pr-creation",
            "match" => %{"name" => "create_pull_request"}
          }
        ]
      })

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [
          %{content: "prepare a pull request", role: "user"},
          %{
            content: nil,
            role: "assistant",
            tool_calls: [%{function: %{arguments: "{}", name: "create_pull_request"}, id: "call_1", type: "function"}]
          },
          %{content: "created", role: "tool", tool_call_id: "call_1"}
        ],
        model: "unit-model",
        tool_choice: "auto",
        tools: [%{function: %{name: "create_pull_request", parameters: %{type: "object"}}, type: "function"}]
      })

    assert conn.status == 200

    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) == "openai-compatible text response"
    refute get_in(body, ["choices", Access.at(0), "message", "tool_calls"])

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    mediation = get_in(receipt, ["final", "provider_metadata", "wardwright_tool_mediation"])

    assert mediation["schema"] == "wardwright.tool_mediation.v1"

    assert [%{"action" => "hide", "id" => "hide-pr-creation", "matched_tools" => ["create_pull_request"]}] =
             mediation["applied_rules"]

    assert [%{"declared_by" => "agent", "name" => "create_pull_request", "type" => "function"}] =
             Enum.map(mediation["original_tools"], &Map.take(&1, ["declared_by", "name", "type"]))

    assert mediation["provider_visible_tools"] == []
  end

  test "tool mediation observe mode does not patch provider-visible tools" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("tool_mediation", %{
        "mode" => "observe",
        "rules" => [
          %{
            "action" => "hide",
            "id" => "observe-only-hide",
            "match" => %{"name" => "create_pull_request"}
          }
        ]
      })

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [
          %{content: "prepare a pull request", role: "user"},
          %{
            content: nil,
            role: "assistant",
            tool_calls: [%{function: %{arguments: "{}", name: "create_pull_request"}, id: "call_1", type: "function"}]
          },
          %{content: "created", role: "tool", tool_call_id: "call_1"}
        ],
        model: "unit-model",
        tool_choice: "auto",
        tools: [%{function: %{name: "create_pull_request", parameters: %{type: "object"}}, type: "function"}]
      })

    assert conn.status == 200

    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "tool_calls", Access.at(0), "function", "name"]) ==
             "create_pull_request"

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    refute get_in(receipt, ["final", "provider_metadata", "wardwright_tool_mediation"])
  end

  test "tool mediation can augment Wardwright-hosted tools before provider choice" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("server_tools", [%{"name" => "wardwright_policy_cache_status"}])
      |> Map.put("tool_mediation", %{
        "rules" => [
          %{
            "action" => "augment",
            "description_append" => "Only call this when policy-cache status is directly relevant.",
            "id" => "policy-cache-context",
            "match" => %{"name" => "wardwright_policy_cache_status"}
          }
        ]
      })

    assert call(:post, "/__test/config", config).status == 200

    assert {:ok, _event} =
             Wardwright.PolicyCache.add(%{
               "created_at_unix_ms" => 1,
               "key" => "browser:read",
               "kind" => "tool_call",
               "scope" => %{"session_id" => "server-tool-mediation"}
             })

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "check Wardwright policy cache status", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    mediation = get_in(receipt, ["final", "provider_metadata", "wardwright_tool_mediation"])

    assert [%{"action" => "augment", "id" => "policy-cache-context"}] =
             Enum.map(mediation["applied_rules"], &Map.take(&1, ["action", "id"]))

    assert [%{"declared_by" => "wardwright", "name" => "wardwright_policy_cache_status"}] =
             Enum.map(mediation["provider_visible_tools"], &Map.take(&1, ["declared_by", "name"]))

    [original] = mediation["original_tools"]
    [visible] = mediation["provider_visible_tools"]
    assert original["schema_hash"] != visible["schema_hash"]

    assert [server_tool] = get_in(receipt, ["final", "provider_metadata", "wardwright_server_tools"])
    assert server_tool["name"] == "wardwright_policy_cache_status"
    assert server_tool["status"] == "completed"
  end

  test "openai-compatible targets use the Wardwright-hosted server-tool framework for registered tools" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("server_tools", [%{"name" => "wardwright_policy_cache_status"}])

    assert call(:post, "/__test/config", config).status == 200

    assert {:ok, _event} =
             Wardwright.PolicyCache.add(%{
               "created_at_unix_ms" => 1,
               "key" => "browser:read",
               "kind" => "tool_call",
               "scope" => %{"session_id" => "server-tool-smoke"}
             })

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "check Wardwright policy cache status", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200

    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) ==
             "Wardwright server tool status was observed."

    assert get_in(body, ["choices", Access.at(0), "finish_reason"]) == "stop"

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert [server_tool] = get_in(receipt, ["final", "provider_metadata", "wardwright_server_tools"])
    assert server_tool["call_id"] == "call_wardwright_status_1"
    assert server_tool["execution_location"] == "wardwright"
    assert server_tool["name"] == "wardwright_policy_cache_status"
    assert server_tool["status"] == "completed"
    assert server_tool["visibility_level"] == "local_verified"
    assert get_in(server_tool, ["result_metadata", "entry_count"]) >= 1
    assert get_in(server_tool, ["result_metadata", "topology"]) == "catalog_per_session_tables"

    assert get_in(receipt, ["final", "provider_metadata", "wardwright_server_tool_first_finish_reason"]) == "tool_calls"
  end

  test "openai-compatible targets run configured Dune server tools with model arguments" do
    base_url = streaming_provider_base_url("/openai")
    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("server_tools", [
        %{
          "description" => "Echo a value through a trusted local Dune server function.",
          "engine" => "dune",
          "name" => "dune_echo_tool",
          "parameters" => %{
            "additionalProperties" => false,
            "properties" => %{"value" => %{"type" => "string"}},
            "type" => "object"
          },
          "source" => ~S(%{"echo" => input["value"]})
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "use the Dune echo server tool", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200

    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) ==
             "Wardwright Dune server tool result was observed."

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert [server_tool] = get_in(receipt, ["final", "provider_metadata", "wardwright_server_tools"])
    assert server_tool["call_id"] == "call_dune_echo_tool_1"
    assert server_tool["engine"] == "dune"
    assert server_tool["execution_location"] == "wardwright"
    assert server_tool["name"] == "dune_echo_tool"
    assert server_tool["status"] == "completed"
    assert server_tool["visibility_level"] == "local_verified"
    assert get_in(server_tool, ["result_metadata", "echo"]) == "from-model"
  end

  test "openai-compatible targets run trusted BEAM module server tools loaded from path" do
    base_url = streaming_provider_base_url("/openai")
    module_name = "WardwrightBeamReverseTool#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "#{module_name}.exs")

    File.write!(path, """
    defmodule #{module_name} do
      @behaviour Wardwright.ServerTools.Behaviour

      def spec do
        %{
          "description" => "Reverse text through a trusted local BEAM module.",
          "name" => "beam_reverse_tool",
          "parameters" => %{
            "additionalProperties" => false,
            "properties" => %{"text" => %{"type" => "string"}},
            "type" => "object"
          }
        }
      end

      def run(%{"text" => text}, _context), do: {:ok, %{"reversed" => String.reverse(text)}}
      def run(_arguments, _context), do: {:error, "text is required"}
    end
    """)

    System.put_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS", "1")
    System.put_env("WARDWRIGHT_TEST_OPENAI_KEY", "test-openai-key")

    on_exit(fn ->
      File.rm(path)
      System.delete_env("WARDWRIGHT_TEST_OPENAI_KEY")
      System.delete_env("WARDWRIGHT_ALLOW_TEST_CREDENTIALS")
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "context_window" => 256,
          "credential_env" => "WARDWRIGHT_TEST_OPENAI_KEY",
          "model" => "openai-compatible/live-test",
          "provider_base_url" => base_url,
          "provider_kind" => "openai-compatible"
        }
      ])
      |> Map.put("governance", [])
      |> Map.put("server_tools", [
        %{
          "engine" => "beam_module",
          "module" => module_name,
          "name" => "beam_reverse_tool",
          "path" => path
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "use the BEAM reverse server tool", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200

    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) ==
             "Wardwright BEAM server tool result was observed."

    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert [server_tool] = get_in(receipt, ["final", "provider_metadata", "wardwright_server_tools"])
    assert server_tool["call_id"] == "call_beam_reverse_tool_1"
    assert server_tool["engine"] == "beam_module"
    assert server_tool["execution_location"] == "wardwright"
    assert server_tool["name"] == "beam_reverse_tool"
    assert server_tool["status"] == "completed", inspect(server_tool)
    assert server_tool["visibility_level"] == "local_verified"
    assert get_in(server_tool, ["result_metadata", "reversed"]) == "desserts"
  end

  defp sse_json_payloads(body) do
    body
    |> String.split("\n\n", trim: true)
    |> Enum.flat_map(fn event ->
      event
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.flat_map(fn
        "data:" <> data -> [String.trim(data)]
        _line -> []
      end)
    end)
    |> Enum.reject(&(&1 == "[DONE]"))
    |> Enum.map(&JSON.decode!/1)
  end
end
