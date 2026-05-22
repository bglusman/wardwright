defmodule Wardwright.HistoryPolicyTest do
  use Wardwright.RouterCase

  test "history threshold policy reads only configured cache scope" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 8, "recent_limit" => 8})
      |> Map.put("governance", [
        %{
          "action" => "escalate",
          "cache_key" => "shell:ls",
          "cache_kind" => "tool_call",
          "cache_scope" => "session_id",
          "id" => "repeat-tool",
          "kind" => "history_threshold",
          "severity" => "warning",
          "threshold" => 2
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    assert call(:post, "/v1/policy-cache/events", %{
             key: "shell:ls",
             kind: "tool_call",
             scope: %{session_id: "session-a"}
           }).status == 201

    assert call(:post, "/v1/policy-cache/events", %{
             key: "shell:ls",
             kind: "tool_call",
             scope: %{session_id: "session-b"}
           }).status == 201

    miss =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{request: %{messages: [%{content: "hello", role: "user"}], model: "unit-model"}},
        [{"x-wardwright-session-id", "session-a"}]
      )

    assert miss.status == 200
    assert get_in(JSON.decode!(miss.resp_body), ["receipt", "final", "alert_count"]) == 0

    assert call(:post, "/v1/policy-cache/events", %{
             key: "shell:ls",
             kind: "tool_call",
             scope: %{session_id: "session-a"}
           }).status == 201

    hit =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{request: %{messages: [%{content: "hello", role: "user"}], model: "unit-model"}},
        [{"x-wardwright-session-id", "session-a"}]
      )

    body = JSON.decode!(hit.resp_body)
    assert get_in(body, ["receipt", "final", "alert_count"]) == 1

    assert get_in(body, ["receipt", "decision", "policy_actions", Access.at(0), "history_count"]) ==
             2
  end

  test "history threshold can count normalized tool context from current session requests" do
    cache_key = "mcp.github:create_pull_request:planning"

    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 8, "recent_limit" => 8})
      |> Map.put("governance", [
        %{
          "action" => "escalate",
          "cache_key" => cache_key,
          "cache_kind" => "tool_call",
          "cache_scope" => "session_id",
          "id" => "repeat-pr-tool",
          "kind" => "history_threshold",
          "severity" => "warning",
          "threshold" => 1
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{
          request: %{
            messages: [%{content: "open a pull request", role: "user"}],
            metadata: %{
              tool_context: %{
                phase: "planning",
                primary_tool: %{name: "create_pull_request", namespace: "mcp.github", risk_class: "write"},
                tool_call_id: "call_1"
              }
            },
            model: "unit-model"
          }
        },
        [{"x-wardwright-session-id", "session-tools"}]
      )

    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "final", "alert_count"]) == 1

    assert get_in(body, ["receipt", "decision", "policy_actions", Access.at(0), "history_count"]) ==
             1

    assert [%{"key" => ^cache_key, "kind" => "tool_call", "value" => value}] =
             Wardwright.PolicyCache.recent(
               %{"kind" => "tool_call", "scope" => %{"session_id" => "session-tools"}},
               10
             )

    assert value["tool_call_id"] == "call_1"
    assert get_in(value, ["primary_tool", "namespace"]) == "mcp.github"
  end

  test "history threshold uses safe defaults for blank operator-facing fields" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 8, "recent_limit" => 8})
      |> Map.put("governance", [
        %{
          "action" => "annotate",
          "cache_key" => "shell:ls",
          "cache_kind" => "tool_call",
          "cache_scope" => "session_id",
          "id" => "repeat-tool",
          "kind" => "history_threshold",
          "message" => "",
          "severity" => "",
          "threshold" => 0
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    assert call(:post, "/v1/policy-cache/events", %{
             key: "shell:ls",
             kind: "tool_call",
             scope: %{session_id: "session-a"}
           }).status == 201

    conn =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{request: %{messages: [%{content: "hello", role: "user"}], model: "unit-model"}},
        [{"x-wardwright-session-id", "session-a"}]
      )

    action =
      get_in(JSON.decode!(conn.resp_body), [
        "receipt",
        "decision",
        "policy_actions",
        Access.at(0)
      ])

    assert action["message"] == "policy cache threshold matched"
    assert action["severity"] == "info"
    assert action["threshold"] == 1
    assert action["history_count"] == 1
  end

  test "history regex threshold uses automatically recorded request text inside session scope" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 8, "recent_limit" => 8})
      |> Map.put("governance", [
        %{
          "action" => "alert_async",
          "cache_key" => "chat_completion",
          "cache_kind" => "request_text",
          "cache_scope" => "session_id",
          "id" => "dangerous-shell-history",
          "kind" => "history_regex_threshold",
          "pattern" => "rm\\s+-rf",
          "severity" => "critical",
          "threshold" => 1
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    miss =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{request: %{messages: [%{content: "hello", role: "user"}], model: "unit-model"}},
        [{"x-wardwright-session-id", "session-a"}]
      )

    assert get_in(JSON.decode!(miss.resp_body), ["receipt", "final", "alert_count"]) == 0

    hit =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{
          request: %{
            messages: [%{content: "please run rm -rf /tmp/demo", role: "user"}],
            model: "unit-model"
          }
        },
        [{"x-wardwright-session-id", "session-a"}]
      )

    receipt = JSON.decode!(hit.resp_body)["receipt"]
    assert get_in(receipt, ["final", "alert_count"]) == 1
    assert [%{"outcome" => "queued"}] = get_in(receipt, ["final", "alert_delivery"])

    isolated =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{request: %{messages: [%{content: "hello", role: "user"}], model: "unit-model"}},
        [{"x-wardwright-session-id", "session-b"}]
      )

    assert get_in(JSON.decode!(isolated.resp_body), ["receipt", "final", "alert_count"]) == 0
  end
end
