defmodule Wardwright.PublicApiTest do
  use Wardwright.RouterCase

  test "lists flat and prefixed public models" do
    conn = call(:get, "/v1/models")
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert Enum.map(body["data"], & &1["id"]) == ["coding-balanced", "wardwright/coding-balanced"]
  end

  test "public synthetic model discovery omits policy internals" do
    config =
      unit_policy_config()
      |> Map.put("prompt_transforms", %{"preamble" => "private operator prompt"})
      |> Map.put("governance", [
        %{"id" => "internal-policy", "kind" => "request_guard", "contains" => "secret marker"}
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn = call(:get, "/v1/synthetic/models")
    assert conn.status == 200

    [model] = Jason.decode!(conn.resp_body)["data"]
    assert model["id"] == "unit-model"
    assert model["active_version"] == "unit-version"
    assert model["route_type"] == "dispatcher"

    refute Map.has_key?(model, "governance")
    refute Map.has_key?(model, "prompt_transforms")
    refute Map.has_key?(model, "route_graph")
    refute Map.has_key?(model, "structured_output")
  end

  test "admin synthetic model endpoint keeps full policy record behind protection" do
    config =
      unit_policy_config()
      |> Map.put("prompt_transforms", %{"preamble" => "private operator prompt"})

    assert call(:post, "/__test/config", config).status == 200

    rejected = call(:get, "/admin/synthetic-models", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    local = call(:get, "/admin/synthetic-models")
    assert local.status == 200

    [model] = Jason.decode!(local.resp_body)["data"]
    assert model["prompt_transforms"] == %{"preamble" => "private operator prompt"}
    assert is_list(model["governance"])
    assert is_map(model["route_graph"])
  end

  test "protected model access endpoint lists agent endpoints and provider raw models" do
    config =
      unit_policy_config()
      |> Map.put("synthetic_model", Wardwright.synthetic_model())
      |> Map.put("version", Wardwright.synthetic_version())
      |> Map.put("targets", [
        %{
          "model" => Wardwright.local_model(),
          "context_window" => Wardwright.local_context_window(),
          "provider_base_url" => "https://user:secret@example.test/v1?api_key=do-not-leak"
        },
        %{
          "model" => Wardwright.managed_model(),
          "context_window" => Wardwright.managed_context_window()
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    rejected = call(:get, "/admin/model-access", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    local = call(:get, "/admin/model-access")
    assert local.status == 200

    body = Jason.decode!(local.resp_body)

    assert body["service"]["openai_base_url"] =~ "/v1"
    assert body["service"]["chat_completions_url"] =~ "/v1/chat/completions"
    assert body["service"]["mcp_url"] =~ "/mcp"
    assert body["service"]["tools_command"] == "wardwright tools"

    [model] = body["synthetic_models"]
    assert model["id"] == "coding-balanced"
    assert "coding-balanced" in model["agent_model_ids"]
    assert "wardwright/coding-balanced" in model["agent_model_ids"]

    raw_models = Enum.map(body["provider_models"], & &1["target_model_id"])
    assert Wardwright.local_model() in raw_models
    assert Wardwright.managed_model() in raw_models

    local_provider =
      Enum.find(body["provider_models"], &(&1["target_model_id"] == Wardwright.local_model()))

    assert local_provider["base_url"] == "https://example.test/v1"
    assert local_provider["credential_source"] == "none"
    refute local.resp_body =~ "secret"
    refute local.resp_body =~ "do-not-leak"
  end

  test "protected policy authoring API exposes projection and tool contracts" do
    rejected = call(:get, "/v1/policy-authoring/tools", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    tools = call(:get, "/v1/policy-authoring/tools")
    assert tools.status == 200

    tool_names =
      tools.resp_body |> Jason.decode!() |> Map.fetch!("data") |> Enum.map(& &1["name"])

    assert "explain_projection" in tool_names
    assert "simulate_policy" in tool_names
    assert "list_dune_snippets" in tool_names
    assert "evaluate_dune_snippet" in tool_names
    assert "draft_synthetic_model" in tool_names
    assert "activate_synthetic_model" in tool_names
    assert "record_scenario" in tool_names
    assert "import_receipt_scenario" in tool_names
    assert "export_regression_pack" in tool_names
    assert "apply_scenario_retention" in tool_names
    assert "propose_rule_change" in tool_names
    assert "validate_policy_artifact" in tool_names

    projection = call(:get, "/v1/policy-authoring/projections/tts-retry")
    assert projection.status == 200

    body = Jason.decode!(projection.resp_body)
    assert get_in(body, ["projection", "state_machine", "initial_state"]) == "observing"

    simulations = call(:get, "/v1/policy-authoring/simulations/tts-retry")
    assert simulations.status == 200

    assert [%{"artifact_hash" => "sha256:" <> _hash}] =
             Jason.decode!(simulations.resp_body)["data"]

    missing = call(:get, "/v1/policy-authoring/projections/not-real")
    assert missing.status == 404
  end

  test "protected policy authoring API lists and evaluates Dune snippets" do
    rejected = call(:get, "/v1/policy-authoring/dune-snippets", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    listed = call(:get, "/v1/policy-authoring/dune-snippets")
    assert listed.status == 200

    snippets = Jason.decode!(listed.resp_body)["data"]
    assert Enum.any?(snippets, &(&1["id"] == "tool.browser-before-shell"))

    registry_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "snippet_id" => "tool.browser-before-shell",
        "input" => %{
          "tool_name" => "shell.exec",
          "recent_tools" => ["browser.open"]
        }
      })

    assert registry_eval.status == 200
    registry_body = Jason.decode!(registry_eval.resp_body)
    assert get_in(registry_body, ["result", "policy_status"]) == "ok"
    assert get_in(registry_body, ["result", "policy_result", "action"]) == "allow_tool"

    ad_hoc_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "source" => """
        %{"action" => "block", "reason" => input["reason"]}
        """,
        "input" => %{"reason" => "operator test"}
      })

    assert ad_hoc_eval.status == 200

    assert get_in(Jason.decode!(ad_hoc_eval.resp_body), ["result", "policy_result", "reason"]) ==
             "operator test"

    missing = call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{})
    assert missing.status == 400
  end

  test "protected policy authoring API drafts and activates synthetic models" do
    draft_body = %{
      "synthetic_model" => "support-router",
      "version" => "draft-test",
      "targets" => [
        %{"model" => "local/small", "context_window" => 1024},
        %{"model" => "managed/large", "context_window" => 128_000}
      ],
      "route" => %{
        "type" => "dispatcher",
        "id" => "dispatcher.context-fit",
        "models" => ["local/small", "managed/large"]
      },
      "stream_rules" => [
        %{
          "id" => "redact-ticket",
          "pattern" => "ticket_[0-9]+",
          "action" => "rewrite_chunk",
          "replacement" => "ticket_[redacted]"
        }
      ]
    }

    rejected =
      call(
        :post,
        "/v1/policy-authoring/synthetic-models/draft",
        draft_body,
        [],
        {203, 0, 113, 10}
      )

    assert rejected.status == 403

    draft = call(:post, "/v1/policy-authoring/synthetic-models/draft", draft_body)
    assert draft.status == 200

    draft_payload = Jason.decode!(draft.resp_body)
    assert get_in(draft_payload, ["artifact", "synthetic_model"]) == "support-router"
    assert get_in(draft_payload, ["artifact", "route_root"]) == "dispatcher.context-fit"

    assert get_in(draft_payload, ["access", "model_ids"]) == [
             "support-router",
             "wardwright/support-router"
           ]

    assert get_in(draft_payload, ["validation", "errors"]) == []

    activated = call(:post, "/v1/policy-authoring/synthetic-models", draft_body)
    assert activated.status == 201

    assert %{"data" => [%{"id" => "support-router"}, %{"id" => "wardwright/support-router"}]} =
             call(:get, "/v1/models").resp_body |> Jason.decode!()
  end

  test "protected policy authoring API proposes rule changes without applying them" do
    alloy_config =
      unit_policy_config()
      |> Map.put("route_root", "alloy.primary")
      |> Map.put("dispatchers", [])
      |> Map.put("alloys", [
        %{
          "id" => "alloy.primary",
          "strategy" => "deterministic_all",
          "constituents" => ["tiny/model", "medium/model"]
        }
      ])

    assert call(:post, "/__test/config", alloy_config).status == 200

    body = %{
      "operation" => "append_rule",
      "collection" => "governance",
      "rule" => %{
        "id" => "block-unreviewed-prod",
        "kind" => "request_guard",
        "action" => "block",
        "contains" => "deploy prod"
      }
    }

    proposal = call(:post, "/v1/policy-authoring/propose-rule-change", body)
    assert proposal.status == 200

    payload = Jason.decode!(proposal.resp_body)
    assert get_in(payload, ["proposal", "applied"]) == false
    assert get_in(payload, ["proposal", "operation"]) == "append_rule"
    assert get_in(payload, ["proposal", "rule_id"]) == "block-unreviewed-prod"
    assert get_in(payload, ["validation", "errors"]) == []
    assert get_in(payload, ["artifact", "route_root"]) == "alloy.primary"
    assert get_in(payload, ["artifact", "alloys", Access.at(0), "id"]) == "alloy.primary"

    proposed_rules = get_in(payload, ["artifact", "governance"])
    assert Enum.any?(proposed_rules, &(&1["id"] == "block-unreviewed-prod"))

    current_rules = Wardwright.current_config()["governance"]
    refute Enum.any?(current_rules, &(&1["id"] == "block-unreviewed-prod"))
  end

  test "protected policy authoring API proposes replace and remove rule operations" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "id" => "ambiguous-success",
          "kind" => "request_guard",
          "action" => "escalate",
          "contains" => "looks done",
          "message" => "completion claim needs artifact"
        },
        %{
          "id" => "prod-guard",
          "kind" => "request_guard",
          "action" => "block",
          "contains" => "deploy prod"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    replace =
      call(:post, "/v1/policy-authoring/propose-rule-change", %{
        "operation" => "replace_rule",
        "collection" => "governance",
        "rule_id" => "prod-guard",
        "rule" => %{
          "id" => "prod-guard",
          "kind" => "request_guard",
          "action" => "escalate",
          "contains" => "deploy prod",
          "message" => "Production deploys require operator review"
        }
      })

    assert replace.status == 200
    replaced = Jason.decode!(replace.resp_body)
    assert get_in(replaced, ["proposal", "change", "matched_count"]) == 1
    assert get_in(replaced, ["proposal", "applied"]) == false

    assert Enum.find(replaced["artifact"]["governance"], &(&1["id"] == "prod-guard"))[
             "action"
           ] == "escalate"

    assert Enum.find(Wardwright.current_config()["governance"], &(&1["id"] == "prod-guard"))[
             "action"
           ] == "block"

    remove =
      call(:post, "/v1/policy-authoring/propose-rule-change", %{
        "operation" => "remove_rule",
        "collection" => "governance",
        "rule_id" => "ambiguous-success"
      })

    assert remove.status == 200
    removed = Jason.decode!(remove.resp_body)
    assert get_in(removed, ["proposal", "change", "after_count"]) == 1
    assert get_in(removed, ["proposal", "applied"]) == false
    refute Enum.any?(removed["artifact"]["governance"], &(&1["id"] == "ambiguous-success"))

    assert Enum.any?(
             Wardwright.current_config()["governance"],
             &(&1["id"] == "ambiguous-success")
           )
  end

  test "protected policy authoring API persists scenarios for simulation evidence" do
    rejected =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{}, [], {203, 0, 113, 10})

    assert rejected.status == 403

    scenario = %{
      "scenario_id" => "api-reviewed-trigger",
      "title" => "API reviewed trigger",
      "source" => "user",
      "pinned" => true,
      "input_summary" => "A reviewed stream scenario stores the split trigger.",
      "expected_behavior" => "The stream retry rule fires before release.",
      "verdict" => "passed",
      "trace" => [
        %{
          "id" => "api-1",
          "phase" => "response.streaming",
          "node_id" => "tts.no-old-client",
          "kind" => "match",
          "label" => "persisted trace",
          "detail" => "scenario came from the authoring API",
          "severity" => "pass",
          "state_id" => "guarding"
        }
      ],
      "receipt_preview" => %{"final_status" => "simulated"}
    }

    created = call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => scenario})
    assert created.status == 201

    created_body = Jason.decode!(created.resp_body)
    assert get_in(created_body, ["scenario", "scenario_id"]) == "api-reviewed-trigger"
    assert get_in(created_body, ["scenario", "scenario_source"]) == "persisted"

    listed = call(:get, "/v1/policy-authoring/scenarios/tts-retry")
    assert listed.status == 200
    assert [%{"scenario_id" => "api-reviewed-trigger"}] = Jason.decode!(listed.resp_body)["data"]

    simulations = call(:get, "/v1/policy-authoring/simulations/tts-retry")
    assert simulations.status == 200

    assert [
             %{
               "scenario_id" => "api-reviewed-trigger",
               "scenario_source" => "persisted",
               "artifact_hash" => "sha256:" <> _hash
             }
           ] = Jason.decode!(simulations.resp_body)["data"]

    malformed = call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"trace" => []})
    assert malformed.status == 400

    invalid_state =
      put_in(scenario, ["trace", Access.at(0), "state_id"], "not-a-state")

    invalid_state_conn =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => invalid_state})

    assert invalid_state_conn.status == 400
    assert get_in(Jason.decode!(invalid_state_conn.resp_body), ["error", "message"]) =~ "state_id"

    invalid_trace =
      put_in(scenario, ["trace", Access.at(0), "label"], "")

    invalid_trace_conn =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => invalid_trace})

    assert invalid_trace_conn.status == 400

    assert get_in(Jason.decode!(invalid_trace_conn.resp_body), ["error", "message"]) =~
             "trace event"

    invalid_source =
      Map.put(scenario, "source", "not-reviewed")

    invalid_source_conn =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => invalid_source})

    assert invalid_source_conn.status == 400

    assert get_in(Jason.decode!(invalid_source_conn.resp_body), ["error", "message"]) =~
             "source"

    missing = call(:post, "/v1/policy-authoring/scenarios/not-real", %{"scenario" => scenario})
    assert missing.status == 404
  end

  test "protected policy authoring API imports receipts as live replay scenarios" do
    receipt = %{
      "receipt_id" => "receipt_import_1",
      "created_at" => 1_800_000_123,
      "synthetic_model" => "unit-model",
      "synthetic_version" => "2026-05-13.mock",
      "final" => %{
        "status" => "completed",
        "stream_policy" => %{
          "status" => "completed",
          "retry_count" => 1,
          "released_to_consumer" => true,
          "events" => [
            %{
              "type" => "stream_policy.triggered",
              "rule_id" => "tts.no-old-client",
              "action" => "retry_with_reminder"
            },
            %{
              "type" => "attempt.retry_requested",
              "rule_id" => "tts.retry-arbiter",
              "retry_count" => 1
            }
          ]
        }
      }
    }

    Wardwright.ReceiptStore.insert(receipt)

    rejected =
      call(
        :post,
        "/v1/policy-authoring/scenarios/tts-retry/from-receipt/receipt_import_1",
        %{},
        [],
        {203, 0, 113, 10}
      )

    assert rejected.status == 403

    imported =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry/from-receipt/receipt_import_1", %{
        "source" => "assistant",
        "title" => "Imported retry receipt"
      })

    assert imported.status == 201

    scenario = Jason.decode!(imported.resp_body)["scenario"]
    assert scenario["scenario_id"] == "receipt-receipt_import_1"
    assert scenario["source"] == "live_replay"
    assert scenario["pinned"] == true
    assert get_in(scenario, ["receipt_preview", "receipt_id"]) == "receipt_import_1"

    assert Enum.map(scenario["trace"], & &1["state_id"]) == [
             "guarding",
             "retrying"
           ]

    missing_receipt =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry/from-receipt/not-real", %{})

    assert missing_receipt.status == 404
  end

  test "protected policy authoring API exports pinned scenarios and prunes unpinned records" do
    pinned = scenario_fixture("pinned-regression", true)
    old_unpinned = scenario_fixture("old-unpinned", false, "2026-05-01T00:00:00Z")
    new_unpinned = scenario_fixture("new-unpinned", false, "2026-05-02T00:00:00Z")

    assert call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => pinned}).status ==
             201

    assert call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => old_unpinned}).status ==
             201

    assert call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => new_unpinned}).status ==
             201

    rejected_export =
      call(
        :get,
        "/v1/policy-authoring/scenarios/tts-retry/regression-export",
        nil,
        [],
        {203, 0, 113, 10}
      )

    assert rejected_export.status == 403

    export = call(:get, "/v1/policy-authoring/scenarios/tts-retry/regression-export")
    assert export.status == 200

    export_body = Jason.decode!(export.resp_body)
    assert export_body["schema"] == "wardwright.policy_regression_pack.v1"
    assert export_body["scenario_count"] == 1
    assert [%{"scenario_id" => "pinned-regression", "pinned" => true}] = export_body["scenarios"]

    exunit_export =
      call(:get, "/v1/policy-authoring/scenarios/tts-retry/regression-export?format=exunit")

    assert exunit_export.status == 200
    assert [content_type] = get_resp_header(exunit_export, "content-type")
    assert content_type =~ "text/plain"
    assert {:ok, _quoted} = Code.string_to_quoted(exunit_export.resp_body)
    assert [{module, _bytecode}] = Code.compile_string(exunit_export.resp_body)
    assert module.regression_pack()["scenario_count"] == 1
    assert :ok = module.validate_pack!()

    unsupported_export =
      call(:get, "/v1/policy-authoring/scenarios/tts-retry/regression-export?format=stream_data")

    assert unsupported_export.status == 400

    assert get_in(Jason.decode!(unsupported_export.resp_body), ["error", "code"]) ==
             "invalid_regression_export_format"

    retention =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry/retention", %{
        "max_unpinned" => 1
      })

    assert retention.status == 200

    retention_body = Jason.decode!(retention.resp_body)
    assert retention_body["schema"] == "wardwright.policy_scenario_retention.v1"
    assert retention_body["pruned_count"] == 1
    assert retention_body["remaining_unpinned_count"] == 1
    assert retention_body["pruned_scenario_ids"] == ["old-unpinned"]

    listed = call(:get, "/v1/policy-authoring/scenarios/tts-retry")
    assert listed.status == 200

    scenario_ids =
      listed.resp_body
      |> Jason.decode!()
      |> Map.fetch!("data")
      |> Enum.map(& &1["scenario_id"])

    assert scenario_ids == ["new-unpinned", "pinned-regression"]

    invalid_retention =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry/retention", %{
        "max_unpinned" => -1
      })

    assert invalid_retention.status == 400
  end

  test "protected policy validation reports errors and explicit review gaps" do
    rejected =
      call(:post, "/v1/policy-authoring/validate", %{}, [], {203, 0, 113, 10})

    assert rejected.status == 403

    current = call(:post, "/v1/policy-authoring/validate", %{})
    assert current.status == 200

    current_body = Jason.decode!(current.resp_body)
    assert current_body["schema"] == "wardwright.policy_validation.v1"
    assert current_body["source"] == "current_config"
    assert current_body["verdict"] in ["valid", "needs_review"]
    assert Enum.any?(current_body["coverage_gaps"], &(&1["path"] == "scenarios"))

    invalid_artifact =
      unit_policy_config()
      |> Map.put("targets", [
        %{"model" => "tiny/model", "context_window" => 8},
        %{"model" => "tiny/model", "context_window" => 32}
      ])
      |> Map.put("dispatchers", [%{"id" => "dispatcher.good", "models" => ["tiny/model"]}])
      |> Map.put("route_root", "missing.selector")

    invalid = call(:post, "/v1/policy-authoring/validate", %{"artifact" => invalid_artifact})
    assert invalid.status == 200

    body = Jason.decode!(invalid.resp_body)
    assert body["source"] == "submitted"
    assert body["verdict"] == "invalid"
    assert Enum.any?(body["errors"], &(&1["message"] =~ "duplicate target tiny/model"))
    assert Enum.any?(body["errors"], &(&1["path"] == "route_root"))

    malformed_selector =
      unit_policy_config()
      |> Map.put("dispatchers", "not-a-list")

    malformed = call(:post, "/v1/policy-authoring/validate", %{"artifact" => malformed_selector})
    assert malformed.status == 200

    malformed_body = Jason.decode!(malformed.resp_body)
    assert malformed_body["verdict"] == "invalid"
    assert Enum.any?(malformed_body["errors"], &(&1["path"] == "dispatchers"))
  end

  test "chat completion records caller headers and selected model" do
    request = %{
      model: "wardwright/coding-balanced",
      messages: [%{role: "user", content: "hello"}],
      metadata: %{consuming_agent_id: "body-agent"}
    }

    conn =
      :post
      |> call("/v1/chat/completions", request, [{"x-wardwright-agent-id", "header-agent"}])

    assert conn.status == 200
    assert get_resp_header(conn, "x-wardwright-selected-model") == ["local/qwen-coder"]
    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["caller", "consuming_agent_id"]) == %{
             "value" => "header-agent",
             "source" => "header"
           }
  end

  test "simulation can select the managed model for large prompts" do
    request = %{
      request: %{
        model: "coding-balanced",
        messages: [%{role: "user", content: String.duplicate("x", 140_000)}]
      }
    }

    conn = call(:post, "/v1/synthetic/simulate", request)
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert get_in(body, ["receipt", "decision", "selected_model"]) == "managed/kimi-k2.6"
  end

  defp scenario_fixture(id, pinned, created_at \\ nil) do
    [
      {"scenario_id", id},
      {"title", "Scenario #{id}"},
      {"source", "user"},
      {"pinned", pinned},
      {"input_summary", "Input for #{id}."},
      {"expected_behavior", "The stream retry rule remains linked to guarding."},
      {"verdict", "passed"},
      {"trace",
       [
         %{
           "id" => "#{id}-trace",
           "phase" => "response.streaming",
           "node_id" => "tts.no-old-client",
           "kind" => "match",
           "label" => "persisted trace",
           "detail" => "scenario fixture",
           "severity" => "pass",
           "state_id" => "guarding"
         }
       ]},
      {"created_at", created_at}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
