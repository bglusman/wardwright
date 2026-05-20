defmodule Wardwright.PublicApiTest do
  use Wardwright.RouterCase

  test "lists flat and prefixed public models" do
    conn = call(:get, "/v1/models")
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert Enum.map(body["data"], & &1["id"]) == ["coding-balanced", "wardwright/coding-balanced"]
  end

  test "unkeyed internal models are hidden from public model discovery and external chat" do
    config =
      unit_policy_config()
      |> Map.put("requires_api_key", false)
      |> Map.put("auth", %{"unkeyed_model_access" => "internal"})

    assert call(:post, "/__test/config", config).status == 200

    assert [] = call(:get, "/v1/models").resp_body |> Jason.decode!() |> Map.fetch!("data")

    assert [] =
             call(:get, "/v1/wardwright/models").resp_body
             |> Jason.decode!()
             |> Map.fetch!("data")

    rejected =
      call(:post, "/v1/chat/completions", %{
        "messages" => [%{"content" => "hello", "role" => "user"}],
        "model" => "unit-model"
      })

    assert rejected.status == 403
    assert get_in(Jason.decode!(rejected.resp_body), ["error", "type"]) == "forbidden"
    assert get_in(Jason.decode!(rejected.resp_body), ["error", "code"]) == "model_internal"
  end

  test "keyed models require valid model-scoped API keys" do
    config = unit_policy_config() |> Map.put("requires_api_key", true)
    assert call(:post, "/__test/config", config).status == 200

    missing =
      call(:post, "/v1/chat/completions", %{
        "messages" => [%{"content" => "hello", "role" => "user"}],
        "model" => "unit-model"
      })

    assert missing.status == 401
    assert get_in(Jason.decode!(missing.resp_body), ["error", "type"]) == "unauthorized"
    assert get_in(Jason.decode!(missing.resp_body), ["error", "code"]) == "model_api_key_required"

    {:ok, created} = Wardwright.ModelApiKeyStore.create("unit-model", "test-client")

    accepted =
      call(
        :post,
        "/v1/chat/completions",
        %{
          "messages" => [%{"content" => "hello", "role" => "user"}],
          "model" => "unit-model"
        },
        [{"authorization", "Bearer #{created["key"]}"}]
      )

    assert accepted.status == 200

    assert :ok = Wardwright.ModelApiKeyStore.revoke(created["id"])

    revoked =
      call(
        :post,
        "/v1/chat/completions",
        %{
          "messages" => [%{"content" => "hello", "role" => "user"}],
          "model" => "unit-model"
        },
        [{"authorization", "Bearer #{created["key"]}"}]
      )

    assert revoked.status == 401
  end

  test "model serving does not require basic auth when the model is public" do
    previous = Application.get_env(:wardwright, :basic_auth_password)
    Application.put_env(:wardwright, :basic_auth_password, "operator-password")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :basic_auth_password, previous),
        else: Application.delete_env(:wardwright, :basic_auth_password)
    end)

    config =
      unit_policy_config()
      |> Map.put("requires_api_key", false)
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(
        :post,
        "/v1/chat/completions",
        %{
          "messages" => [%{"content" => "hello", "role" => "user"}],
          "model" => "unit-model"
        },
        [],
        {203, 0, 113, 10}
      )

    assert conn.status == 200
  end

  test "public Wardwright model discovery omits policy internals" do
    config =
      unit_policy_config()
      |> Map.put("prompt_transforms", %{"preamble" => "private operator prompt"})
      |> Map.put("governance", [
        %{"contains" => "secret marker", "id" => "internal-policy", "kind" => "request_guard"}
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn = call(:get, "/v1/wardwright/models")
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

  test "public Wardwright model discovery uses middleware terminology" do
    config = unit_policy_config()
    assert call(:post, "/__test/config", config).status == 200

    conn = call(:get, "/v1/wardwright/models")
    assert conn.status == 200

    [model] = Jason.decode!(conn.resp_body)["data"]
    assert model["id"] == "unit-model"
    assert model["model_id"] == "unit-model"
    assert model["public_model_id"] == "unit-model"
  end

  test "admin Wardwright model endpoint keeps full policy record behind protection" do
    config =
      unit_policy_config()
      |> Map.put("prompt_transforms", %{"preamble" => "private operator prompt"})

    assert call(:post, "/__test/config", config).status == 200

    rejected = call(:get, "/admin/wardwright-models", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    local = call(:get, "/admin/wardwright-models")
    assert local.status == 200

    [model] = Jason.decode!(local.resp_body)["data"]
    assert model["prompt_transforms"] == %{"preamble" => "private operator prompt"}
    assert model["model_definition_version"] == 1
    assert is_list(model["governance"])
    assert is_map(model["route_graph"])

    wardwright_models = call(:get, "/admin/wardwright-models")
    assert wardwright_models.status == 200

    assert get_in(Jason.decode!(wardwright_models.resp_body), ["data", Access.at(0), "id"]) ==
             model["id"]
  end

  test "protected model access endpoint lists agent endpoints and provider raw models" do
    config =
      unit_policy_config()
      |> Map.put("model_id", Wardwright.model_id())
      |> Map.put("version", Wardwright.model_version())
      |> Map.put("targets", [
        %{
          "context_window" => Wardwright.local_context_window(),
          "model" => Wardwright.local_model(),
          "provider_base_url" => "https://user:secret@example.test/v1?api_key=do-not-leak"
        },
        %{
          "context_window" => Wardwright.managed_context_window(),
          "model" => Wardwright.managed_model()
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
    assert body["service"]["admin_command"] == "wardwright admin"
    assert body["service"]["tools_command"] == "wardwright tools"

    [model] = body["wardwright_models"]
    assert model["id"] == "coding-balanced"
    assert "coding-balanced" in model["agent_model_ids"]
    assert "wardwright/coding-balanced" in model["agent_model_ids"]
    refute Map.has_key?(body, "model_ids")

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
    assert "save_dune_snippet" in tool_names
    assert "delete_dune_snippet" in tool_names
    assert "draft_wardwright_model" in tool_names
    assert "activate_wardwright_model" in tool_names
    assert "record_scenario" in tool_names
    assert "delete_scenario" in tool_names
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
    original_workspace = Application.get_env(:wardwright, :dune_snippet_workspace_dir)
    workspace_dir = temp_workspace_dir("wardwright-api-dune-snippets")
    Application.put_env(:wardwright, :dune_snippet_workspace_dir, workspace_dir)

    on_exit(fn ->
      File.rm_rf!(workspace_dir)

      case original_workspace do
        nil -> Application.delete_env(:wardwright, :dune_snippet_workspace_dir)
        value -> Application.put_env(:wardwright, :dune_snippet_workspace_dir, value)
      end
    end)

    rejected = call(:get, "/v1/policy-authoring/dune-snippets", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    listed = call(:get, "/v1/policy-authoring/dune-snippets")
    assert listed.status == 200

    snippets = Jason.decode!(listed.resp_body)["data"]
    assert Enum.any?(snippets, &(&1["id"] == "tool.browser-before-shell"))

    registry_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"recent_tools" => ["browser.open"], "tool_name" => "shell.exec"},
        "snippet_id" => "tool.browser-before-shell"
      })

    assert registry_eval.status == 200
    registry_body = Jason.decode!(registry_eval.resp_body)
    assert get_in(registry_body, ["result", "policy_status"]) == "ok"
    assert get_in(registry_body, ["result", "policy_result", "action"]) == "allow_tool"

    ad_hoc_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"reason" => "operator test"},
        "source" => """
        %{"action" => "block", "reason" => input["reason"]}
        """
      })

    assert ad_hoc_eval.status == 200

    assert get_in(Jason.decode!(ad_hoc_eval.resp_body), ["result", "policy_result", "reason"]) ==
             "operator test"

    session_id = "api-session-#{System.unique_integer([:positive])}"

    session = %{
      "model_id" => "api-model",
      "session_id" => session_id,
      "version" => "api-version"
    }

    first_session_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"event" => "first"},
        "session" => session,
        "source" => """
        events = [input["event"]]
        %{"action" => "allow", "count" => Enum.count(events)}
        """
      })

    assert first_session_eval.status == 200
    first_session_body = Jason.decode!(first_session_eval.resp_body)
    assert first_session_body["session"]["status"] == "new"
    assert get_in(first_session_body, ["result", "policy_result", "count"]) == 1

    second_session_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"event" => "second"},
        "session" => session,
        "source" => """
        events = [input["event"] | events]
        %{"action" => "allow", "count" => Enum.count(events)}
        """
      })

    assert second_session_eval.status == 200
    second_session_body = Jason.decode!(second_session_eval.resp_body)
    assert second_session_body["session"]["status"] == "reused"
    assert get_in(second_session_body, ["result", "policy_result", "count"]) == 2

    saved =
      call(:post, "/v1/policy-authoring/dune-snippets", %{
        "description" => "Block requests marked as high risk.",
        "example_input" => %{"risk" => "high"},
        "id" => "workspace.block-risk",
        "phase" => "request.review",
        "source" => """
        if input["risk"] == "high" do
          %{"action" => "block", "reason" => "high risk"}
        else
          %{"action" => "allow", "reason" => "low risk"}
        end
        """,
        "title" => "Workspace risk blocker"
      })

    assert saved.status == 201
    assert get_in(Jason.decode!(saved.resp_body), ["snippet", "origin"]) == "workspace"

    relisted = call(:get, "/v1/policy-authoring/dune-snippets")

    assert Enum.any?(Jason.decode!(relisted.resp_body)["data"], fn snippet ->
             snippet["id"] == "workspace.block-risk" and snippet["origin"] == "workspace"
           end)

    saved_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"risk" => "high"},
        "snippet_id" => "workspace.block-risk"
      })

    assert saved_eval.status == 200

    assert get_in(Jason.decode!(saved_eval.resp_body), ["result", "policy_result", "action"]) ==
             "block"

    delete_saved = call(:delete, "/v1/policy-authoring/dune-snippets/workspace.block-risk")
    assert delete_saved.status == 200
    assert Jason.decode!(delete_saved.resp_body)["deleted"] == true

    missing = call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{})
    assert missing.status == 400
  end

  test "protected policy authoring API drafts and activates Wardwright models" do
    draft_body = %{
      "model_id" => "support-router",
      "route" => %{
        "id" => "dispatcher.context-fit",
        "models" => ["local/small", "managed/large"],
        "type" => "dispatcher"
      },
      "stream_rules" => [
        %{
          "action" => "rewrite_chunk",
          "id" => "redact-ticket",
          "pattern" => "ticket_[0-9]+",
          "replacement" => "ticket_[redacted]"
        }
      ],
      "targets" => [
        %{"context_window" => 1024, "model" => "local/small"},
        %{"context_window" => 128_000, "model" => "managed/large"}
      ],
      "version" => "draft-test"
    }

    rejected =
      call(
        :post,
        "/v1/policy-authoring/wardwright-models/draft",
        draft_body,
        [],
        {203, 0, 113, 10}
      )

    assert rejected.status == 403

    draft = call(:post, "/v1/policy-authoring/wardwright-models/draft", draft_body)
    assert draft.status == 200

    draft_payload = Jason.decode!(draft.resp_body)
    assert get_in(draft_payload, ["artifact", "model_id"]) == "support-router"
    assert get_in(draft_payload, ["artifact", "route_root"]) == "dispatcher.context-fit"

    assert get_in(draft_payload, ["access", "model_ids"]) == [
             "support-router",
             "wardwright/support-router"
           ]

    assert get_in(draft_payload, ["validation", "errors"]) == []

    activated = call(:post, "/v1/policy-authoring/wardwright-models", draft_body)
    assert activated.status == 201

    model_ids =
      :get
      |> call("/v1/models")
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()
      |> Map.fetch!("data")
      |> Enum.map(& &1["id"])

    assert "coding-balanced" in model_ids
    assert "wardwright/coding-balanced" in model_ids
    assert "support-router" in model_ids
    assert "wardwright/support-router" in model_ids
  end

  test "multiple activated Wardwright models are callable with isolated routes and sessions" do
    alpha =
      unit_policy_config()
      |> Map.put("model_id", "alpha-router")
      |> Map.put("version", "alpha-v1")
      |> Map.put("targets", [
        %{"context_window" => 64, "model" => "alpha/small"},
        %{"context_window" => 256, "model" => "alpha/large"}
      ])

    beta =
      unit_policy_config()
      |> Map.put("model_id", "beta-router")
      |> Map.put("version", "beta-v1")
      |> Map.put("targets", [
        %{"context_window" => 512, "model" => "beta/only"}
      ])

    assert {:ok, _alpha} = Wardwright.put_model_config(alpha)
    assert {:ok, _beta} = Wardwright.put_model_config(beta)

    model_ids =
      :get
      |> call("/v1/models")
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()
      |> Map.fetch!("data")
      |> Enum.map(& &1["id"])

    assert "alpha-router" in model_ids
    assert "beta-router" in model_ids

    alpha_conn =
      call(
        :post,
        "/v1/chat/completions",
        %{"messages" => [%{"content" => "hi", "role" => "user"}], "model" => "alpha-router"},
        [{"x-wardwright-session-id", "alpha-session"}]
      )

    beta_conn =
      call(
        :post,
        "/v1/chat/completions",
        %{"messages" => [%{"content" => "hi", "role" => "user"}], "model" => "beta-router"},
        [{"x-wardwright-session-id", "beta-session"}]
      )

    assert alpha_conn.status == 200
    assert beta_conn.status == 200
    assert get_resp_header(alpha_conn, "x-wardwright-selected-model") == ["alpha/small"]
    assert get_resp_header(beta_conn, "x-wardwright-selected-model") == ["beta/only"]

    status =
      :get
      |> call("/admin/runtime")
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()

    assert Enum.any?(
             status["models"],
             &(&1["model_id"] == "alpha-router" and &1["version"] == "alpha-v1")
           )

    assert Enum.any?(
             status["models"],
             &(&1["model_id"] == "beta-router" and &1["version"] == "beta-v1")
           )

    assert Enum.any?(
             status["sessions"],
             &(&1["model_id"] == "alpha-router" and &1["session_id"] == "alpha-session")
           )

    assert Enum.any?(
             status["sessions"],
             &(&1["model_id"] == "beta-router" and &1["session_id"] == "beta-session")
           )
  end

  test "protected policy authoring API proposes rule changes without applying them" do
    alloy_config =
      unit_policy_config()
      |> Map.put("route_root", "alloy.primary")
      |> Map.put("dispatchers", [])
      |> Map.put("alloys", [
        %{
          "constituents" => ["tiny/model", "medium/model"],
          "id" => "alloy.primary",
          "strategy" => "deterministic_all"
        }
      ])

    assert call(:post, "/__test/config", alloy_config).status == 200

    body = %{
      "collection" => "governance",
      "operation" => "append_rule",
      "rule" => %{
        "action" => "block",
        "contains" => "deploy prod",
        "id" => "block-unreviewed-prod",
        "kind" => "request_guard"
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
          "action" => "escalate",
          "contains" => "looks done",
          "id" => "ambiguous-success",
          "kind" => "request_guard",
          "message" => "completion claim needs artifact"
        },
        %{
          "action" => "block",
          "contains" => "deploy prod",
          "id" => "prod-guard",
          "kind" => "request_guard"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    replace =
      call(:post, "/v1/policy-authoring/propose-rule-change", %{
        "collection" => "governance",
        "operation" => "replace_rule",
        "rule" => %{
          "action" => "escalate",
          "contains" => "deploy prod",
          "id" => "prod-guard",
          "kind" => "request_guard",
          "message" => "Production deploys require operator review"
        },
        "rule_id" => "prod-guard"
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
        "collection" => "governance",
        "operation" => "remove_rule",
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
      "artifact_hash" => "sha256:api-reviewed-artifact",
      "expected_behavior" => "The stream retry rule fires before release.",
      "input_summary" => "A reviewed stream scenario stores the split trigger.",
      "model_id" => "coding-balanced",
      "pinned" => true,
      "receipt_preview" => %{"final_status" => "simulated"},
      "scenario_id" => "api-reviewed-trigger",
      "source" => "user",
      "title" => "API reviewed trigger",
      "trace" => [
        %{
          "detail" => "scenario came from the authoring API",
          "id" => "api-1",
          "kind" => "match",
          "label" => "persisted trace",
          "node_id" => "tts.no-old-client",
          "phase" => "response.streaming",
          "severity" => "pass",
          "state_id" => "guarding"
        }
      ],
      "turn" => %{
        "history_context" => %{"policy_state" => "observing"},
        "model_response" => "avoid Old\nClient( in released output",
        "response_attempts" => [
          %{"index" => 1, "model_output" => "avoid Old\nClient( in released output"},
          %{"index" => 2, "model_output" => "Use the current client adapter."}
        ],
        "user_input" => "Show the migration note."
      },
      "verdict" => "passed"
    }

    created = call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => scenario})
    assert created.status == 201

    created_body = Jason.decode!(created.resp_body)
    assert get_in(created_body, ["scenario", "scenario_id"]) == "api-reviewed-trigger"
    assert get_in(created_body, ["scenario", "scenario_source"]) == "persisted"
    assert get_in(created_body, ["scenario", "model_id"]) == "coding-balanced"
    assert get_in(created_body, ["scenario", "artifact_hash"]) == "sha256:api-reviewed-artifact"
    assert get_in(created_body, ["scenario", "turn", "model_response"]) =~ "Old\nClient"

    assert Enum.any?(
             get_in(created_body, ["scenario", "turn", "response_attempts"]),
             &(&1["index"] == 2 and &1["model_output"] =~ "current client")
           )

    listed = call(:get, "/v1/policy-authoring/scenarios/tts-retry")
    assert listed.status == 200

    assert [
             %{
               "scenario_id" => "api-reviewed-trigger",
               "turn" => %{"user_input" => "Show the migration note."}
             }
           ] = Jason.decode!(listed.resp_body)["data"]

    deleted = call(:delete, "/v1/policy-authoring/scenarios/tts-retry/api-reviewed-trigger")
    assert deleted.status == 200

    assert get_in(Jason.decode!(deleted.resp_body), ["scenario", "scenario_id"]) ==
             "api-reviewed-trigger"

    assert %{"data" => []} =
             call(:get, "/v1/policy-authoring/scenarios/tts-retry").resp_body
             |> Jason.decode!()

    assert call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => scenario}).status ==
             201

    simulations = call(:get, "/v1/policy-authoring/simulations/tts-retry")
    assert simulations.status == 200

    assert [
             %{
               "artifact_hash" => "sha256:" <> _hash,
               "scenario_id" => "api-reviewed-trigger",
               "scenario_source" => "persisted"
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
      "created_at" => 1_800_000_123,
      "final" => %{
        "status" => "completed",
        "stream_policy" => %{
          "events" => [
            %{"action" => "retry_with_reminder", "rule_id" => "tts.no-old-client", "type" => "stream_policy.triggered"},
            %{"retry_count" => 1, "rule_id" => "tts.retry-arbiter", "type" => "attempt.retry_requested"}
          ],
          "released_to_consumer" => true,
          "retry_count" => 1,
          "status" => "completed"
        }
      },
      "model_id" => "unit-model",
      "model_version" => "2026-05-13.mock",
      "receipt_id" => "receipt_import_1"
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
    assert [%{"pinned" => true, "scenario_id" => "pinned-regression"}] = export_body["scenarios"]

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
        %{"context_window" => 8, "model" => "tiny/model"},
        %{"context_window" => 32, "model" => "tiny/model"}
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

    nested_bad_route =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "artifact" => %{
            "dispatchers" => [%{"id" => "other-route", "models" => ["local/final"]}],
            "model_id" => "broken-child",
            "route_root" => "missing-route",
            "targets" => [%{"context_window" => 4_096, "model" => "local/final"}],
            "version" => "unit-version"
          },
          "context_window" => 4_096,
          "model" => "broken-child",
          "target_kind" => "wardwright_model"
        }
      ])
      |> Map.put("route_root", "outer-route")
      |> Map.put("dispatchers", [
        %{"id" => "outer-route", "models" => ["broken-child"]}
      ])

    nested = call(:post, "/v1/policy-authoring/validate", %{"artifact" => nested_bad_route})
    assert nested.status == 200

    nested_body = Jason.decode!(nested.resp_body)
    assert nested_body["verdict"] == "invalid"

    assert Enum.any?(
             nested_body["errors"],
             &(&1["path"] == "model_graph" and
                 &1["message"] =~ "model target broken-child: route_root")
           )

    nested_forced_provider =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "artifact" => %{
            "dispatchers" => [%{"id" => "child-route", "models" => ["local/final"]}],
            "model_id" => "child-router",
            "route_root" => "child-route",
            "targets" => [%{"context_window" => 4_096, "model" => "local/final"}],
            "version" => "unit-version"
          },
          "context_window" => 4_096,
          "model" => "child-router",
          "target_kind" => "wardwright_model"
        }
      ])
      |> Map.put("route_root", "outer-route")
      |> Map.put("dispatchers", [
        %{"id" => "outer-route", "models" => ["child-router"]}
      ])
      |> Map.put("governance", [
        %{
          "action" => "switch_model",
          "id" => "force-child-provider",
          "kind" => "route_gate",
          "target_model" => "local/final"
        },
        %{
          "action" => "restrict_routes",
          "allowed_targets" => ["local"],
          "id" => "allow-child-provider-prefix",
          "kind" => "route_gate"
        }
      ])

    nested_forced =
      call(:post, "/v1/policy-authoring/validate", %{"artifact" => nested_forced_provider})

    assert nested_forced.status == 200
    nested_forced_body = Jason.decode!(nested_forced.resp_body)

    refute Enum.any?(
             nested_forced_body["errors"],
             &(&1["path"] == "governance.allowed_targets")
           )

    invalid_allowed_tools =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "allowed_tools" => [%{"namespace" => "review"}],
          "id" => "missing-tool-name",
          "kind" => "allowed_tools"
        }
      ])

    invalid_allowed = call(:post, "/v1/policy-authoring/validate", %{"artifact" => invalid_allowed_tools})
    assert invalid_allowed.status == 200
    invalid_allowed_body = Jason.decode!(invalid_allowed.resp_body)

    assert invalid_allowed_body["verdict"] == "invalid"

    assert Enum.any?(
             invalid_allowed_body["errors"],
             &(&1["path"] == "governance.phase" and &1["message"] =~ "requires phase")
           )

    assert Enum.any?(
             invalid_allowed_body["errors"],
             &(&1["path"] == "governance.allowed_tools[].name")
           )
  end

  test "chat completion records caller headers and selected model" do
    request = %{
      messages: [%{content: "hello", role: "user"}],
      metadata: %{consuming_agent_id: "body-agent"},
      model: "wardwright/coding-balanced"
    }

    conn =
      :post
      |> call("/v1/chat/completions", request, [{"x-wardwright-agent-id", "header-agent"}])

    assert conn.status == 200
    assert get_resp_header(conn, "x-wardwright-selected-model") == ["local/qwen-coder"]
    [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    receipt = Wardwright.ReceiptStore.get(receipt_id)

    assert get_in(receipt, ["caller", "consuming_agent_id"]) == %{
             "source" => "header",
             "value" => "header-agent"
           }
  end

  test "simulation can select the managed model for large prompts" do
    request = %{
      request: %{
        messages: [%{content: String.duplicate("x", 140_000), role: "user"}],
        model: "coding-balanced"
      }
    }

    conn = call(:post, "/v1/wardwright/simulate", request)
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
           "detail" => "scenario fixture",
           "id" => "#{id}-trace",
           "kind" => "match",
           "label" => "persisted trace",
           "node_id" => "tts.no-old-client",
           "phase" => "response.streaming",
           "severity" => "pass",
           "state_id" => "guarding"
         }
       ]},
      {"created_at", created_at}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp temp_workspace_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end
end
