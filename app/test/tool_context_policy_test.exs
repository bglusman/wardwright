defmodule Wardwright.ToolContextPolicyTest do
  use Wardwright.RouterCase

  test "tool selector can choose a different route for the same public model" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "local/read"},
        %{"context_window" => 512, "model" => "managed/write"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "attach_policy_bundle" => "github_write_planning_v1",
          "id" => "github-write-tools",
          "kind" => "tool_selector",
          "target_model" => "managed/write",
          "tool" => %{
            "name" => "create_pull_request",
            "namespace" => "mcp.github",
            "phase" => "planning",
            "risk_class" => "write"
          }
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    write_conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "open a review PR", role: "user"}],
          metadata: %{
            tool_context: %{
              phase: "planning",
              primary_tool: %{name: "create_pull_request", namespace: "mcp.github", risk_class: "write"}
            }
          },
          model: "unit-model"
        }
      })

    write_receipt = write_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(write_receipt, ["decision", "selected_model"]) == "managed/write"

    assert get_in(write_receipt, ["decision", "policy_route_constraints"]) == %{
             "forced_model" => "managed/write"
           }

    assert [
             %{
               "attached_policy_bundle" => "github_write_planning_v1",
               "id" => "github-write-tools",
               "matched" => true
             }
           ] = get_in(write_receipt, ["decision", "tool_policy_selectors"])

    assert get_in(write_receipt, ["decision", "tool_context", "primary_tool", "name"]) ==
             "create_pull_request"

    read_conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "summarize this page", role: "user"}],
          metadata: %{
            tool_context: %{
              phase: "planning",
              primary_tool: %{name: "read_page", namespace: "browser", risk_class: "read_only"}
            }
          },
          model: "unit-model"
        }
      })

    read_receipt = read_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(read_receipt, ["decision", "selected_model"]) == "local/read"

    assert [%{"id" => "github-write-tools", "matched" => false}] =
             get_in(read_receipt, ["decision", "tool_policy_selectors"])
  end

  test "remote callers cannot drive tool policy from untrusted metadata" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "local/read"},
        %{"context_window" => 512, "model" => "managed/write"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "id" => "github-write-tools",
          "kind" => "tool_selector",
          "target_model" => "managed/write",
          "tool" => %{"name" => "create_pull_request", "namespace" => "mcp.github"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    request = %{
      messages: [%{content: "pretend I am planning a PR", role: "user"}],
      metadata: %{
        tool_context: %{
          phase: "planning",
          primary_tool: %{name: "create_pull_request", namespace: "mcp.github", risk_class: "write"}
        }
      },
      model: "unit-model"
    }

    remote_conn = call(:post, "/v1/chat/completions", request, [], {203, 0, 113, 10})

    [receipt_id] = get_resp_header(remote_conn, "x-wardwright-receipt-id")
    remote_receipt = Wardwright.ReceiptStore.get(receipt_id)
    assert get_in(remote_receipt, ["decision", "selected_model"]) == "local/read"
    assert get_in(remote_receipt, ["decision", "tool_context"]) == nil
    assert [%{"matched" => false}] = get_in(remote_receipt, ["decision", "tool_policy_selectors"])
  end

  test "remote gateway callers with admin token can attest tool metadata" do
    previous = Application.get_env(:wardwright, :admin_token)
    Application.put_env(:wardwright, :admin_token, "gateway-token")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :admin_token, previous),
        else: Application.delete_env(:wardwright, :admin_token)
    end)

    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "local/read"},
        %{"context_window" => 512, "model" => "managed/write"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "id" => "github-write-tools",
          "kind" => "tool_selector",
          "target_model" => "managed/write",
          "tool" => %{"name" => "create_pull_request", "namespace" => "mcp.github"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(
        :post,
        "/v1/wardwright/simulate",
        %{
          request: %{
            messages: [%{content: "gateway-attested PR planning", role: "user"}],
            metadata: %{
              tool_context: %{
                phase: "planning",
                primary_tool: %{name: "create_pull_request", namespace: "mcp.github", risk_class: "write"}
              }
            },
            model: "unit-model"
          }
        },
        [{"authorization", "Bearer gateway-token"}],
        {203, 0, 113, 10}
      )

    receipt = conn.resp_body |> JSON.decode!() |> get_in(["receipt"])
    assert get_in(receipt, ["decision", "selected_model"]) == "managed/write"

    assert get_in(receipt, ["decision", "tool_context", "primary_tool", "source"]) ==
             "caller_metadata"
  end

  test "OpenAI tool_choice is normalized and can drive route constraints" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "local/qwen"},
        %{"context_window" => 512, "model" => "managed/kimi"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "restrict_routes",
          "allowed_targets" => ["managed"],
          "id" => "ticket-writes-managed",
          "kind" => "tool_selector",
          "tool" => %{"name" => "create_ticket", "namespace" => "openai.function"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "file this incident", role: "user"}],
          model: "unit-model",
          tool_choice: %{function: %{name: "create_ticket"}, type: "function"},
          tools: [
            %{
              function: %{name: "create_ticket", parameters: %{properties: %{title: %{type: "string"}}, type: "object"}},
              type: "function"
            }
          ]
        }
      })

    receipt = conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(receipt, ["decision", "selected_model"]) == "managed/kimi"

    assert get_in(receipt, ["decision", "policy_route_constraints"]) == %{
             "allowed_targets" => ["managed"]
           }

    assert get_in(receipt, ["decision", "tool_context", "primary_tool", "source"]) ==
             "tool_choice"

    assert get_in(receipt, [
             "decision",
             "tool_context",
             "available_tools",
             Access.at(0),
             "schema_hash"
           ]) =~ "sha256:"

    receipt_id = receipt["receipt_id"]

    list_conn =
      call(:get, "/v1/receipts?tool_namespace=openai.function&tool_name=create_ticket")

    assert %{"data" => [%{"receipt_id" => ^receipt_id, "tool_name" => "create_ticket"}]} =
             JSON.decode!(list_conn.resp_body)
  end

  test "tool loop threshold uses bounded session history without raw tool payloads" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 8, "recent_limit" => 8})
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "local/read"},
        %{"context_window" => 512, "model" => "managed/write"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "cache_scope" => "session_id",
          "id" => "repeat-github-write",
          "kind" => "tool_loop_threshold",
          "target_model" => "managed/write",
          "threshold" => 2,
          "tool" => %{"name" => "create_pull_request", "namespace" => "mcp.github"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    request = %{
      messages: [%{content: "open the same PR", role: "user"}],
      metadata: %{
        session_id: "session-tool-loop",
        tool_context: %{
          phase: "planning",
          primary_tool: %{name: "create_pull_request", namespace: "mcp.github", risk_class: "write"}
        }
      },
      model: "unit-model"
    }

    first = call(:post, "/v1/wardwright/simulate", %{request: request})
    first_receipt = first.resp_body |> JSON.decode!() |> get_in(["receipt"])
    assert get_in(first_receipt, ["decision", "selected_model"]) == "local/read"
    refute get_in(first_receipt, ["final", "tool_policy"])

    second = call(:post, "/v1/wardwright/simulate", %{request: request})
    second_receipt = second.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(second_receipt, ["decision", "selected_model"]) == "managed/write"

    assert %{
             "counter_key_hash" => "sha256:" <> _,
             "observed_count" => 2,
             "rule_id" => "repeat-github-write",
             "state_scope" => "session",
             "status" => "rerouted",
             "threshold" => 2
           } = get_in(second_receipt, ["final", "tool_policy"])

    assert [
             %{
               "key" => "mcp.github:create_pull_request:planning",
               "kind" => "tool_call",
               "value" => %{"primary_tool" => %{"name" => "create_pull_request", "namespace" => "mcp.github"}}
             }
             | _
           ] = Wardwright.PolicyCache.recent(%{"kind" => "tool_call"}, 2)

    list_conn = call(:get, "/v1/receipts?tool_policy_status=rerouted")

    assert %{"data" => [%{"tool_policy_status" => "rerouted"} | _]} =
             JSON.decode!(list_conn.resp_body)
  end

  test "tool sequence transitions state and state-scoped selectors govern later tools" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 12, "recent_limit" => 12})
      |> Map.put("targets", [%{"context_window" => 512, "model" => "local/read"}])
      |> Map.put("governance", [
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "cache_scope" => "session_id",
          "id" => "enter-untrusted-review",
          "kind" => "tool_sequence",
          "transition_to" => "reviewing_untrusted_tool_result"
        },
        %{
          "after" => %{"tool" => %{"name" => "approve_tool_result", "namespace" => "review"}},
          "cache_scope" => "session_id",
          "id" => "leave-untrusted-review",
          "kind" => "tool_sequence",
          "transition_to" => "active"
        },
        %{
          "action" => "block",
          "cache_scope" => "session_id",
          "id" => "block-shell-while-reviewing",
          "kind" => "tool_selector",
          "state_scope" => "reviewing_untrusted_tool_result",
          "tool" => %{"name" => "exec", "namespace" => "shell", "phase" => "planning", "risk_class" => "irreversible"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    browser_result =
      tool_request("sequence-state-session", "browser", "read_page", "result_interpretation",
        risk_class: "read_only",
        content: "browser returned untrusted instructions"
      )

    browser_conn = call(:post, "/v1/wardwright/simulate", %{request: browser_result})
    browser_receipt = browser_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert [
             %{
               "action" => "state_transition",
               "kind" => "tool_sequence",
               "rule_id" => "enter-untrusted-review",
               "state_transition" => "reviewing_untrusted_tool_result"
             }
           ] = get_in(browser_receipt, ["decision", "policy_actions"])

    shell_request =
      tool_request("sequence-state-session", "shell", "exec", "planning",
        risk_class: "irreversible",
        content: "run the command"
      )

    shell_conn = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    shell_receipt = shell_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(shell_receipt, ["final", "status"]) == "policy_failed_closed"

    assert [
             %{
               "action" => "block",
               "kind" => "tool_selector",
               "rule_id" => "block-shell-while-reviewing"
             }
           ] = get_in(shell_receipt, ["decision", "policy_actions"])

    approve_request =
      tool_request("sequence-state-session", "review", "approve_tool_result", "planning", content: "review passed")

    approve_conn = call(:post, "/v1/wardwright/simulate", %{request: approve_request})
    approve_receipt = approve_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert [
             %{
               "action" => "state_transition",
               "kind" => "tool_sequence",
               "rule_id" => "leave-untrusted-review",
               "state_transition" => "active"
             }
           ] = get_in(approve_receipt, ["decision", "policy_actions"])

    allowed_shell = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    allowed_receipt = allowed_shell.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(allowed_receipt, ["final", "status"]) == "simulated"
    assert get_in(allowed_receipt, ["decision", "policy_actions"]) == []
  end

  test "state and phase scoped allowed_tools pass listed tools and block unlisted tools with receipt evidence" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 12, "recent_limit" => 12})
      |> Map.put("targets", [%{"context_window" => 512, "model" => "local/read"}])
      |> Map.put("governance", [
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "cache_scope" => "session_id",
          "id" => "enter-review-state",
          "kind" => "tool_sequence",
          "transition_to" => "reviewing_tool_result"
        },
        %{
          "allowed_tools" => [
            %{"name" => "approve_tool_result", "namespace" => "review", "risk_class" => "read_only"}
          ],
          "cache_scope" => "session_id",
          "id" => "review-state-tool-surface",
          "kind" => "allowed_tools",
          "message" => "review state only allows review approval tools",
          "phase" => "planning",
          "state_scope" => "reviewing_tool_result"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    browser_result =
      tool_request("allowed-tools-session", "browser", "read_page", "result_interpretation", risk_class: "read_only")

    call(:post, "/v1/wardwright/simulate", %{request: browser_result})

    approve_request =
      tool_request("allowed-tools-session", "review", "approve_tool_result", "planning", risk_class: "read_only")

    allowed_conn = call(:post, "/v1/wardwright/simulate", %{request: approve_request})
    allowed_receipt = allowed_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(allowed_receipt, ["final", "status"]) == "simulated"
    assert get_in(allowed_receipt, ["decision", "policy_actions"]) == []

    shell_request =
      tool_request("allowed-tools-session", "shell", "exec", "planning", risk_class: "irreversible")

    blocked_conn = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    blocked_receipt = blocked_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(blocked_receipt, ["final", "status"]) == "policy_failed_closed"

    assert [
             %{
               "action" => "block",
               "allowed_tool_phase" => "planning",
               "blocked_tools" => [%{"name" => "exec", "namespace" => "shell", "risk_class" => "irreversible"}],
               "kind" => "allowed_tools",
               "rule_id" => "review-state-tool-surface",
               "state_scope" => "reviewing_tool_result"
             }
           ] = get_in(blocked_receipt, ["decision", "policy_actions"])

    assert get_in(blocked_receipt, [
             "decision",
             "policy_actions",
             Access.at(0),
             "allowed_tools",
             Access.at(0)
           ]) == %{"name" => "approve_tool_result", "namespace" => "review", "risk_class" => "read_only"}

    assert get_in(blocked_receipt, [
             "decision",
             "policy_actions",
             Access.at(0),
             "tool_context",
             "primary_tool",
             "name"
           ]) == "exec"
  end

  test "tool sequence enforces before-after windows and reset tool events" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 12, "recent_limit" => 12})
      |> Map.put("targets", [%{"context_window" => 512, "model" => "local/read"}])
      |> Map.put("governance", [
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "cache_scope" => "session_id",
          "id" => "browser-before-shell",
          "kind" => "tool_sequence",
          "then" => %{
            "action" => "block",
            "tool" => %{"name" => "exec", "namespace" => "shell", "phase" => "planning", "risk_class" => "irreversible"}
          },
          "until" => %{"tool" => %{"name" => "approve_tool_result", "namespace" => "review"}},
          "within" => %{"turns" => 1}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    browser_result =
      tool_request("sequence-direct-session", "browser", "read_page", "result_interpretation", risk_class: "read_only")

    shell_request =
      tool_request("sequence-direct-session", "shell", "exec", "planning", risk_class: "irreversible")

    call(:post, "/v1/wardwright/simulate", %{request: browser_result})
    blocked_shell = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    blocked_receipt = blocked_shell.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(blocked_receipt, ["final", "status"]) == "policy_failed_closed"

    assert [
             %{
               "action" => "block",
               "kind" => "tool_sequence",
               "rule_id" => "browser-before-shell",
               "sequence_after_key" => "browser:read_page:result_interpretation"
             }
           ] = get_in(blocked_receipt, ["decision", "policy_actions"])

    review_reset =
      tool_request("sequence-reset-session", "review", "approve_tool_result", "planning")

    reset_browser =
      tool_request("sequence-reset-session", "browser", "read_page", "result_interpretation", risk_class: "read_only")

    reset_shell =
      tool_request("sequence-reset-session", "shell", "exec", "planning", risk_class: "irreversible")

    call(:post, "/v1/wardwright/simulate", %{request: reset_browser})
    call(:post, "/v1/wardwright/simulate", %{request: review_reset})
    reset_conn = call(:post, "/v1/wardwright/simulate", %{request: reset_shell})
    reset_receipt = reset_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(reset_receipt, ["final", "status"]) == "simulated"
    assert get_in(reset_receipt, ["decision", "policy_actions"]) == []

    expired_browser =
      tool_request("sequence-expired-session", "browser", "read_page", "result_interpretation", risk_class: "read_only")

    unrelated_tool =
      tool_request("sequence-expired-session", "browser", "search", "planning", risk_class: "read_only")

    expired_shell =
      tool_request("sequence-expired-session", "shell", "exec", "planning", risk_class: "irreversible")

    call(:post, "/v1/wardwright/simulate", %{request: expired_browser})
    call(:post, "/v1/wardwright/simulate", %{request: unrelated_tool})
    expired_conn = call(:post, "/v1/wardwright/simulate", %{request: expired_shell})
    expired_receipt = expired_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(expired_receipt, ["final", "status"]) == "simulated"
    assert get_in(expired_receipt, ["decision", "policy_actions"]) == []
  end

  test "tool sequence enforces wall-clock windows through ms and milliseconds aliases" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 16, "recent_limit" => 16})
      |> Map.put("targets", [%{"context_window" => 512, "model" => "local/read"}])
      |> Map.put("governance", [
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "cache_scope" => "session_id",
          "id" => "recent-browser-before-shell-ms",
          "kind" => "tool_sequence",
          "then" => %{"action" => "block", "tool" => %{"name" => "exec", "namespace" => "shell", "phase" => "planning"}},
          "within" => %{"ms" => 2_000}
        },
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "cache_scope" => "session_id",
          "id" => "stale-browser-before-shell-milliseconds",
          "kind" => "tool_sequence",
          "then" => %{
            "action" => "block",
            "tool" => %{"name" => "write", "namespace" => "filesystem", "phase" => "planning"}
          },
          "within" => %{"milliseconds" => 1}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    recent_browser =
      tool_request("sequence-recent-ms-session", "browser", "read_page", "result_interpretation",
        risk_class: "read_only"
      )

    recent_shell =
      tool_request("sequence-recent-ms-session", "shell", "exec", "planning", risk_class: "irreversible")

    call(:post, "/v1/wardwright/simulate", %{request: recent_browser})
    recent_conn = call(:post, "/v1/wardwright/simulate", %{request: recent_shell})
    recent_receipt = recent_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(recent_receipt, ["final", "status"]) == "policy_failed_closed"

    assert [
             %{
               "action" => "block",
               "kind" => "tool_sequence",
               "rule_id" => "recent-browser-before-shell-ms"
             }
           ] = get_in(recent_receipt, ["decision", "policy_actions"])

    stale_browser =
      tool_request("sequence-stale-ms-session", "browser", "read_page", "result_interpretation",
        risk_class: "read_only"
      )

    stale_write =
      tool_request("sequence-stale-ms-session", "filesystem", "write", "planning", risk_class: "irreversible")

    call(:post, "/v1/wardwright/simulate", %{request: stale_browser})
    Process.sleep(10)
    stale_conn = call(:post, "/v1/wardwright/simulate", %{request: stale_write})
    stale_receipt = stale_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(stale_receipt, ["final", "status"]) == "simulated"
    assert get_in(stale_receipt, ["decision", "policy_actions"]) == []
  end

  test "tool sequence resets when an until state is recorded after the prior event" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 16, "recent_limit" => 16})
      |> Map.put("targets", [%{"context_window" => 512, "model" => "local/read"}])
      |> Map.put("governance", [
        %{
          "after" => %{"tool" => %{"name" => "approve_tool_result", "namespace" => "review"}},
          "cache_scope" => "session_id",
          "id" => "mark-tool-result-reviewed",
          "kind" => "tool_sequence",
          "transition_to" => "reviewed_untrusted_tool_result"
        },
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "cache_scope" => "session_id",
          "id" => "browser-before-shell-until-reviewed-state",
          "kind" => "tool_sequence",
          "then" => %{"action" => "block", "tool" => %{"name" => "exec", "namespace" => "shell", "phase" => "planning"}},
          "until" => %{"state" => "reviewed_untrusted_tool_result"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    browser_result =
      tool_request(
        "sequence-until-state-session",
        "browser",
        "read_page",
        "result_interpretation",
        risk_class: "read_only"
      )

    shell_request =
      tool_request("sequence-until-state-session", "shell", "exec", "planning", risk_class: "irreversible")

    review_approval =
      tool_request("sequence-until-state-session", "review", "approve_tool_result", "planning",
        content: "review passed"
      )

    call(:post, "/v1/wardwright/simulate", %{request: browser_result})
    blocked_conn = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    blocked_receipt = blocked_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(blocked_receipt, ["final", "status"]) == "policy_failed_closed"

    assert [
             %{
               "action" => "block",
               "kind" => "tool_sequence",
               "rule_id" => "browser-before-shell-until-reviewed-state"
             }
           ] = get_in(blocked_receipt, ["decision", "policy_actions"])

    review_conn = call(:post, "/v1/wardwright/simulate", %{request: review_approval})
    review_receipt = review_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert [
             %{
               "action" => "state_transition",
               "kind" => "tool_sequence",
               "rule_id" => "mark-tool-result-reviewed",
               "state_transition" => "reviewed_untrusted_tool_result"
             }
           ] = get_in(review_receipt, ["decision", "policy_actions"])

    reset_conn = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    reset_receipt = reset_conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(reset_receipt, ["final", "status"]) == "simulated"
    assert get_in(reset_receipt, ["decision", "policy_actions"]) == []
  end

  test "tool sequence accepts direct before tool when then only names the action" do
    config =
      unit_policy_config()
      |> Map.put("policy_cache", %{"max_entries" => 12, "recent_limit" => 12})
      |> Map.put("targets", [%{"context_window" => 512, "model" => "local/read"}])
      |> Map.put("governance", [
        %{
          "after" => %{"tool" => %{"namespace" => "browser", "phase" => "result_interpretation"}},
          "before" => %{
            "tool" => %{"name" => "exec", "namespace" => "shell", "phase" => "planning", "risk_class" => "irreversible"}
          },
          "cache_scope" => "session_id",
          "id" => "browser-before-shell-alias",
          "kind" => "tool_sequence",
          "then" => %{"action" => "block"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    browser_result =
      tool_request(
        "sequence-before-alias-session",
        "browser",
        "read_page",
        "result_interpretation",
        risk_class: "read_only"
      )

    shell_request =
      tool_request("sequence-before-alias-session", "shell", "exec", "planning", risk_class: "irreversible")

    call(:post, "/v1/wardwright/simulate", %{request: browser_result})
    conn = call(:post, "/v1/wardwright/simulate", %{request: shell_request})
    receipt = conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(receipt, ["final", "status"]) == "policy_failed_closed"

    assert [
             %{
               "action" => "block",
               "kind" => "tool_sequence",
               "rule_id" => "browser-before-shell-alias",
               "sequence_after_key" => "browser:read_page:result_interpretation"
             }
           ] = get_in(receipt, ["decision", "policy_actions"])
  end

  test "assistant tool calls produce redacted hashes instead of raw arguments" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "local/read"},
        %{"context_window" => 512, "model" => "managed/write"}
      ])
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "id" => "shell-write",
          "kind" => "tool_selector",
          "target_model" => "managed/write",
          "tool" => %{"name" => "run_shell", "namespace" => "openai.function"}
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [
            %{content: "prepare the command", role: "user"},
            %{
              content: nil,
              role: "assistant",
              tool_calls: [
                %{
                  function: %{arguments: ~s({"command":"echo secret-token-123"}), name: "run_shell"},
                  id: "call_secret",
                  type: "function"
                }
              ]
            }
          ],
          model: "unit-model"
        }
      })

    receipt = conn.resp_body |> JSON.decode!() |> get_in(["receipt"])

    assert get_in(receipt, ["decision", "selected_model"]) == "managed/write"
    assert get_in(receipt, ["decision", "tool_context", "argument_hash"]) =~ "sha256:"
    refute inspect(receipt) =~ "secret-token-123"

    [event | _] = Wardwright.PolicyCache.recent(%{"kind" => "tool_call"}, 1)
    assert get_in(event, ["value", "primary_tool", "name"]) == "run_shell"
    refute inspect(event) =~ "secret-token-123"
  end

  defp tool_request(session_id, namespace, name, phase, opts \\ []) do
    %{
      messages: [%{content: Keyword.get(opts, :content, "#{namespace}.#{name}"), role: "user"}],
      metadata: %{
        session_id: session_id,
        tool_context: %{
          phase: phase,
          primary_tool: %{name: name, namespace: namespace, risk_class: Keyword.get(opts, :risk_class, "unknown")}
        }
      },
      model: "unit-model"
    }
  end
end
