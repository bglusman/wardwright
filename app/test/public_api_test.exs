defmodule Wardwright.PublicApiTest do
  use Wardwright.RouterCase

  test "lists flat and prefixed public models" do
    conn = call(:get, "/v1/models")
    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)
    assert Enum.map(body["data"], & &1["id"]) == ["coding-balanced", "wardwright/coding-balanced"]
  end

  test "full-session gateway receipts create replayable debugger transcripts" do
    session_id = "real-debug-session-#{System.unique_integer([:positive])}"

    config =
      unit_policy_config()
      |> Map.put("vcr", %{"mode" => "full_session"})
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["Real transcript response."],
          "context_window" => 256,
          "model" => "canned/real-debug",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("dispatchers", [
        %{"id" => "dispatcher.real-debug", "models" => ["canned/real-debug"]}
      ])
      |> Map.put("route_root", "dispatcher.real-debug")

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        "messages" => [%{"content" => "record this real gateway session", "role" => "user"}],
        "metadata" => %{"run_id" => "run-#{session_id}", "session_id" => session_id},
        "model" => "unit-model"
      })

    assert conn.status == 200
    assert [receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")

    assert {:ok, transcript} = WardwrightWeb.CounterfactualReplay.transcript(session_id)
    assert transcript["recording_scope"] == "replayable_session"

    assert Enum.map(transcript["events"], & &1["type"]) == [
             "gateway.request",
             "route.selected",
             "model.response",
             "receipt.finalized"
           ]

    assert Enum.any?(transcript["events"], fn event ->
             event["type"] == "model.response" and
               event["fork_point"] == true and
               event["content_preview"] == "Real transcript response."
           end)

    assert Enum.any?(transcript["events"], fn event ->
             event["type"] == "receipt.finalized" and event["receipt_id"] == receipt_id
           end)

    assert {true, message, ^session_id, fork_point, events} =
             WardwrightWeb.ControlDebuggerData.load_transcript_for_receipt(receipt_id)

    assert message =~ "Loaded 4 trace event(s)"
    assert fork_point =~ "#{session_id}:#{receipt_id}:3"

    assert Enum.any?(events, fn {_cursor, _sequence, type, label, detail, recommendation} ->
             type == "model.response" and
               label == "Model response" and
               detail =~ "Real transcript response." and
               recommendation =~ "before the response is validated or repaired"
           end)
  end

  test "full-session transcript store failures do not fail gateway requests" do
    session_id = "unwritable-debug-session-#{System.unique_integer([:positive])}"
    blocked_store_path = temp_workspace_dir("wardwright-blocked-transcript-store")
    previous_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)

    File.write!(blocked_store_path, "not a directory")
    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, blocked_store_path)

    on_exit(fn ->
      restore_env(:counterfactual_transcript_store_dir, previous_store_dir)
      File.rm_rf!(blocked_store_path)
    end)

    config =
      unit_policy_config()
      |> Map.put("vcr", %{"mode" => "full_session"})
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["Transcript store is unavailable, but the gateway should answer."],
          "context_window" => 256,
          "model" => "canned/unwritable-debug",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("dispatchers", [
        %{"id" => "dispatcher.unwritable-debug", "models" => ["canned/unwritable-debug"]}
      ])
      |> Map.put("route_root", "dispatcher.unwritable-debug")

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        "messages" => [%{"content" => "record even when transcript storage is down", "role" => "user"}],
        "metadata" => %{"run_id" => "run-#{session_id}", "session_id" => session_id},
        "model" => "unit-model"
      })

    assert conn.status == 200
    assert [_receipt_id] = get_resp_header(conn, "x-wardwright-receipt-id")
    assert {:error, _reason} = WardwrightWeb.CounterfactualReplay.transcript(session_id)
  end

  test "unkeyed internal models are hidden from public model discovery and external chat" do
    config =
      unit_policy_config()
      |> Map.put("requires_api_key", false)
      |> Map.put("auth", %{"unkeyed_model_access" => "internal"})

    assert call(:post, "/__test/config", config).status == 200

    assert [] = call(:get, "/v1/models").resp_body |> JSON.decode!() |> Map.fetch!("data")

    assert [] =
             call(:get, "/v1/wardwright/models").resp_body
             |> JSON.decode!()
             |> Map.fetch!("data")

    rejected =
      call(:post, "/v1/chat/completions", %{
        "messages" => [%{"content" => "hello", "role" => "user"}],
        "model" => "unit-model"
      })

    assert rejected.status == 403
    assert get_in(JSON.decode!(rejected.resp_body), ["error", "type"]) == "forbidden"
    assert get_in(JSON.decode!(rejected.resp_body), ["error", "code"]) == "model_internal"
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
    assert get_in(JSON.decode!(missing.resp_body), ["error", "type"]) == "unauthorized"
    assert get_in(JSON.decode!(missing.resp_body), ["error", "code"]) == "model_api_key_required"

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

    [model] = JSON.decode!(conn.resp_body)["data"]
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

    [model] = JSON.decode!(conn.resp_body)["data"]
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

    [model] = JSON.decode!(local.resp_body)["data"]
    assert model["prompt_transforms"] == %{"preamble" => "private operator prompt"}
    assert model["model_definition_version"] == 1
    assert is_list(model["governance"])
    assert is_map(model["route_graph"])

    wardwright_models = call(:get, "/admin/wardwright-models")
    assert wardwright_models.status == 200

    assert get_in(JSON.decode!(wardwright_models.resp_body), ["data", Access.at(0), "id"]) ==
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

    body = JSON.decode!(local.resp_body)

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

  test "protected model access endpoint exposes sanitized server tool configuration" do
    config =
      unit_policy_config()
      |> Map.put("model_id", "server-tool-access")
      |> Map.put("targets", [
        %{
          "context_window" => 8192,
          "model" => "openai/tool-capable-test",
          "provider_base_url" => "https://example.com/v1",
          "provider_kind" => "openai-compatible"
        },
        %{"context_window" => 4096, "model" => "local/mock-toolless"}
      ])
      |> Map.put("dispatchers", [
        %{
          "id" => "dispatcher.server-tools",
          "models" => ["openai/tool-capable-test", "local/mock-toolless"]
        }
      ])
      |> Map.put("route_root", "dispatcher.server-tools")
      |> Map.put("server_tools", [
        %{"name" => "wardwright_policy_cache_status"},
        %{
          "input" => %{"tenant" => "synthetic"},
          "limits" => %{"max_heap_size" => 1_000_000, "max_reductions" => 10_000, "timeout_ms" => 500},
          "name" => "synthetic_dune_tool",
          "parameters" => %{
            "properties" => %{
              "query" => %{"type" => "string"}
            },
            "type" => "object"
          },
          "source" => "fn private_dune_source() { \"do-not-expose-source\" }"
        },
        %{
          "engine" => "beam_module",
          "module" => "Wardwright.Test.Tool",
          "name" => "synthetic_beam_tool",
          "path" => "/Users/example/private/server_tool.exs"
        },
        %{
          "enabled" => false,
          "name" => "disabled_dune_tool",
          "source" => "%{\"disabled\" => true}"
        }
      ])
      |> Map.put("tool_mediation", %{
        "mode" => "patch",
        "rules" => [
          %{"action" => "augment", "id" => "unify-search", "match" => %{"name" => "search"}}
        ]
      })

    assert call(:post, "/__test/config", config).status == 200

    local = call(:get, "/admin/model-access")
    assert local.status == 200
    body = JSON.decode!(local.resp_body)

    [model] = body["wardwright_models"]
    assert model["id"] == "server-tool-access"
    assert get_in(model, ["tool_mediation", "mode"]) == "patch"
    assert get_in(model, ["tool_mediation", "rule_count"]) == 1
    assert get_in(model, ["tool_advertisement", "mode"]) == "intersection"
    assert get_in(model, ["tool_advertisement", "guaranteed_server_tools"]) == 0
    assert get_in(model, ["tool_advertisement", "conditional_server_tools"]) == 3

    assert Enum.map(model["server_tools"], & &1["name"]) == [
             "wardwright_policy_cache_status",
             "synthetic_dune_tool",
             "synthetic_beam_tool",
             "disabled_dune_tool"
           ]

    dune_tool = Enum.find(model["server_tools"], &(&1["name"] == "synthetic_dune_tool"))
    assert dune_tool["source"] == "dune_source"
    assert dune_tool["parameter_keys"] == ["query"]
    assert dune_tool["input_keys"] == ["tenant"]

    assert dune_tool["limits"] == %{
             "max_heap_size" => 1_000_000,
             "max_reductions" => 10_000,
             "timeout_ms" => 500
           }

    beam_tool = Enum.find(model["server_tools"], &(&1["name"] == "synthetic_beam_tool"))
    assert beam_tool["source"] == "beam_path"

    disabled_tool = Enum.find(model["server_tools"], &(&1["name"] == "disabled_dune_tool"))
    assert disabled_tool["enabled"] == false
    refute local.resp_body =~ "do-not-expose-source"
    refute local.resp_body =~ "/Users/example/private"
    refute local.resp_body =~ "server_tool.exs"

    targets = Map.new(model["server_tool_targets"], &{&1["model"], &1})
    assert targets["openai/tool-capable-test"]["support"] == "tool-capable"
    assert targets["local/mock-toolless"]["support"] == "no-tool-injection"
  end

  test "server tool model-level toggles preserve runtime disabled tools in config" do
    config =
      unit_policy_config()
      |> Map.put("model_id", "server-tool-toggle")
      |> Map.put("server_tools", [
        %{"name" => "wardwright_policy_cache_status"},
        %{
          "enabled" => false,
          "name" => "disabled_dune_tool",
          "source" => "%{\"disabled\" => true}"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    assert {true, "Server tool wardwright_policy_cache_status disabled."} =
             WardwrightWeb.LustreModelAccessData.toggle_server_tool(
               "server-tool-toggle",
               "wardwright_policy_cache_status",
               false
             )

    assert {:ok, config} = Wardwright.model_config("server-tool-toggle")
    assert [%{"enabled" => false, "name" => "wardwright_policy_cache_status"}, _] = config["server_tools"]

    assert {true, "Server tool disabled_dune_tool enabled."} =
             WardwrightWeb.LustreModelAccessData.toggle_server_tool(
               "server-tool-toggle",
               "disabled_dune_tool",
               true
             )

    assert {:ok, config} = Wardwright.model_config("server-tool-toggle")

    enabled_tool = Enum.find(config["server_tools"], &(&1["name"] == "disabled_dune_tool"))
    assert enabled_tool["name"] == "disabled_dune_tool"
    refute enabled_tool["enabled"] == false
  end

  test "protected policy authoring API exposes projection and tool contracts" do
    rejected = call(:get, "/v1/policy-authoring/tools", nil, [], {203, 0, 113, 10})
    assert rejected.status == 403

    tools = call(:get, "/v1/policy-authoring/tools")
    assert tools.status == 200

    tool_names =
      tools.resp_body |> JSON.decode!() |> Map.fetch!("data") |> Enum.map(& &1["name"])

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
    assert "list_control_debugger_examples" in tool_names
    assert "record_control_debugger_example" in tool_names
    assert "load_control_debugger_trace" in tool_names
    assert "replay_control_debugger_cursor" in tool_names
    assert "fork_control_debugger_cursor" in tool_names
    assert "save_control_debugger_evidence" in tool_names
    assert "export_regression_pack" in tool_names
    assert "apply_scenario_retention" in tool_names
    assert "propose_rule_change" in tool_names
    assert "validate_policy_artifact" in tool_names

    projection = call(:get, "/v1/policy-authoring/projections/tts-retry")
    assert projection.status == 200

    body = JSON.decode!(projection.resp_body)
    assert get_in(body, ["projection", "state_machine", "initial_state"]) == "observing"

    simulations = call(:get, "/v1/policy-authoring/simulations/tts-retry")
    assert simulations.status == 200

    assert [%{"artifact_hash" => "sha256:" <> _hash}] =
             JSON.decode!(simulations.resp_body)["data"]

    missing = call(:get, "/v1/policy-authoring/projections/not-real")
    assert missing.status == 404
  end

  test "protected control debugger API records loads replays forks and saves selected trace evidence" do
    examples = call(:get, "/v1/policy-authoring/control-debugger/examples")
    assert examples.status == 200
    assert Enum.any?(JSON.decode!(examples.resp_body)["data"], &(&1["id"] == "read-before-edit"))

    recorded = call(:post, "/v1/policy-authoring/control-debugger/examples/read-before-edit/record", %{})
    assert recorded.status == 201
    recording = JSON.decode!(recorded.resp_body)

    receipt_id = recording["receipt_id"]
    session_id = get_in(recording, ["facts", "Original session"])
    cursor = get_in(recording, ["facts", "Fork cursor"])

    assert receipt_id =~ "rcpt_"
    assert session_id =~ "session_"
    assert cursor =~ "#{session_id}:"

    loaded =
      call(:post, "/v1/policy-authoring/control-debugger/traces/load", %{
        "receipt_id" => receipt_id
      })

    assert loaded.status == 200
    trace = JSON.decode!(loaded.resp_body)
    assert trace["session_id"] == session_id
    assert trace["suggested_fork_cursor"] == cursor

    selected = Enum.find(trace["events"], &(&1["cursor"] == cursor))
    assert selected["label"] == "Tool call: edit_file"
    assert selected["recommendation"] =~ "edit_file ran before read_file"

    replayed =
      call(:post, "/v1/policy-authoring/control-debugger/traces/replay-cursor", %{
        "session_id" => session_id,
        "trace_cursor" => cursor
      })

    assert replayed.status == 200
    replay = JSON.decode!(replayed.resp_body)
    assert replay["provider_called"] == false
    assert get_in(replay, ["facts", "Provider called"]) == "no"

    forked =
      call(:post, "/v1/policy-authoring/control-debugger/traces/fork-cursor", %{
        "policy_overlay" => %{"id" => "api-read-before-edit", "requires_prior_read_for" => ["edit_file"]},
        "session_id" => session_id,
        "trace_cursor" => cursor
      })

    assert forked.status == 200
    fork = JSON.decode!(forked.resp_body)
    assert fork["provider_called"] == false
    assert get_in(fork, ["facts", "Comparison accepted"]) == "yes"
    assert get_in(fork, ["facts", "Applied rules"]) == "api-read-before-edit"

    saved =
      call(:post, "/v1/policy-authoring/control-debugger/traces/save-evidence", %{
        "pattern_id" => "tool-governance",
        "session_id" => session_id,
        "title" => "API read-before-edit trace evidence",
        "trace_cursor" => cursor
      })

    assert saved.status == 201
    saved_body = JSON.decode!(saved.resp_body)
    assert saved_body["pattern_id"] == "tool-governance"
    assert get_in(saved_body, ["scenario", "source"]) == "live_replay"
    assert get_in(saved_body, ["scenario", "receipt_preview", "trace_cursor"]) == cursor

    missing_cursor =
      call(:post, "/v1/policy-authoring/control-debugger/traces/save-evidence", %{
        "pattern_id" => "tool-governance",
        "session_id" => session_id
      })

    assert missing_cursor.status == 400
    assert get_in(JSON.decode!(missing_cursor.resp_body), ["error", "message"]) == "trace_cursor is required"
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

    snippets = JSON.decode!(listed.resp_body)["data"]
    assert Enum.any?(snippets, &(&1["id"] == "tool.browser-before-shell"))

    registry_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"recent_tools" => ["browser.open"], "tool_name" => "shell.exec"},
        "snippet_id" => "tool.browser-before-shell"
      })

    assert registry_eval.status == 200
    registry_body = JSON.decode!(registry_eval.resp_body)
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

    assert get_in(JSON.decode!(ad_hoc_eval.resp_body), ["result", "policy_result", "reason"]) ==
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
    first_session_body = JSON.decode!(first_session_eval.resp_body)
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
    second_session_body = JSON.decode!(second_session_eval.resp_body)
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
    assert get_in(JSON.decode!(saved.resp_body), ["snippet", "origin"]) == "workspace"

    relisted = call(:get, "/v1/policy-authoring/dune-snippets")

    assert Enum.any?(JSON.decode!(relisted.resp_body)["data"], fn snippet ->
             snippet["id"] == "workspace.block-risk" and snippet["origin"] == "workspace"
           end)

    saved_eval =
      call(:post, "/v1/policy-authoring/dune-snippets/evaluate", %{
        "input" => %{"risk" => "high"},
        "snippet_id" => "workspace.block-risk"
      })

    assert saved_eval.status == 200

    assert get_in(JSON.decode!(saved_eval.resp_body), ["result", "policy_result", "action"]) ==
             "block"

    delete_saved = call(:delete, "/v1/policy-authoring/dune-snippets/workspace.block-risk")
    assert delete_saved.status == 200
    assert JSON.decode!(delete_saved.resp_body)["deleted"] == true

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

    draft_payload = JSON.decode!(draft.resp_body)
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
      |> JSON.decode!()
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
      |> JSON.decode!()
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
      |> JSON.decode!()

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

    payload = JSON.decode!(proposal.resp_body)
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
    replaced = JSON.decode!(replace.resp_body)
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
    removed = JSON.decode!(remove.resp_body)
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

    created_body = JSON.decode!(created.resp_body)
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
           ] = JSON.decode!(listed.resp_body)["data"]

    deleted = call(:delete, "/v1/policy-authoring/scenarios/tts-retry/api-reviewed-trigger")
    assert deleted.status == 200

    assert get_in(JSON.decode!(deleted.resp_body), ["scenario", "scenario_id"]) ==
             "api-reviewed-trigger"

    assert %{"data" => []} =
             call(:get, "/v1/policy-authoring/scenarios/tts-retry").resp_body
             |> JSON.decode!()

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
           ] = JSON.decode!(simulations.resp_body)["data"]

    malformed = call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"trace" => []})
    assert malformed.status == 400

    invalid_state =
      put_in(scenario, ["trace", Access.at(0), "state_id"], "not-a-state")

    invalid_state_conn =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => invalid_state})

    assert invalid_state_conn.status == 400
    assert get_in(JSON.decode!(invalid_state_conn.resp_body), ["error", "message"]) =~ "state_id"

    invalid_trace =
      put_in(scenario, ["trace", Access.at(0), "label"], "")

    invalid_trace_conn =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => invalid_trace})

    assert invalid_trace_conn.status == 400

    assert get_in(JSON.decode!(invalid_trace_conn.resp_body), ["error", "message"]) =~
             "trace event"

    invalid_source =
      Map.put(scenario, "source", "not-reviewed")

    invalid_source_conn =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry", %{"scenario" => invalid_source})

    assert invalid_source_conn.status == 400

    assert get_in(JSON.decode!(invalid_source_conn.resp_body), ["error", "message"]) =~
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

    scenario = JSON.decode!(imported.resp_body)["scenario"]
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

  test "protected policy authoring API maps receipt imports to stream rewrite states" do
    receipt = %{
      "created_at" => 1_800_000_124,
      "final" => %{
        "status" => "completed",
        "stream_policy" => %{
          "events" => [],
          "released_to_consumer" => true,
          "retry_count" => 0,
          "status" => "completed"
        }
      },
      "model_id" => "unit-model",
      "model_version" => "2026-05-13.mock",
      "receipt_id" => "receipt_import_stream_1"
    }

    Wardwright.ReceiptStore.insert(receipt)

    imported =
      call(
        :post,
        "/v1/policy-authoring/scenarios/stream-rewrite-state/from-receipt/receipt_import_stream_1",
        %{"title" => "Imported stream receipt"}
      )

    assert imported.status == 201

    scenario = JSON.decode!(imported.resp_body)["scenario"]
    assert scenario["scenario_id"] == "receipt-receipt_import_stream_1"
    assert Enum.map(scenario["trace"], & &1["state_id"]) == ["recording"]
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

    export_body = JSON.decode!(export.resp_body)
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

    assert get_in(JSON.decode!(unsupported_export.resp_body), ["error", "code"]) ==
             "invalid_regression_export_format"

    retention =
      call(:post, "/v1/policy-authoring/scenarios/tts-retry/retention", %{
        "max_unpinned" => 1
      })

    assert retention.status == 200

    retention_body = JSON.decode!(retention.resp_body)
    assert retention_body["schema"] == "wardwright.policy_scenario_retention.v1"
    assert retention_body["pruned_count"] == 1
    assert retention_body["remaining_unpinned_count"] == 1
    assert retention_body["pruned_scenario_ids"] == ["old-unpinned"]

    listed = call(:get, "/v1/policy-authoring/scenarios/tts-retry")
    assert listed.status == 200

    scenario_ids =
      listed.resp_body
      |> JSON.decode!()
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

    current_body = JSON.decode!(current.resp_body)
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

    body = JSON.decode!(invalid.resp_body)
    assert body["source"] == "submitted"
    assert body["verdict"] == "invalid"
    assert Enum.any?(body["errors"], &(&1["message"] =~ "duplicate target tiny/model"))
    assert Enum.any?(body["errors"], &(&1["path"] == "route_root"))

    malformed_selector =
      unit_policy_config()
      |> Map.put("dispatchers", "not-a-list")

    malformed = call(:post, "/v1/policy-authoring/validate", %{"artifact" => malformed_selector})
    assert malformed.status == 200

    malformed_body = JSON.decode!(malformed.resp_body)
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

    nested_body = JSON.decode!(nested.resp_body)
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
    nested_forced_body = JSON.decode!(nested_forced.resp_body)

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
    invalid_allowed_body = JSON.decode!(invalid_allowed.resp_body)

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

    body = JSON.decode!(conn.resp_body)
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

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)
end
