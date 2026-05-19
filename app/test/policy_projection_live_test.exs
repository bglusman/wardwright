defmodule Wardwright.PolicyProjectionLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint WardwrightWeb.Endpoint

  setup_all do
    original_config = Application.get_env(:wardwright, WardwrightWeb.Endpoint, [])

    endpoint_config =
      Keyword.merge(original_config,
        http: [ip: {127, 0, 0, 1}, port: 0],
        server: false,
        secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))
      )

    Application.put_env(:wardwright, WardwrightWeb.Endpoint, endpoint_config)
    start_supervised!(WardwrightWeb.Endpoint)

    on_exit(fn ->
      Application.put_env(:wardwright, WardwrightWeb.Endpoint, original_config)
    end)

    :ok
  end

  setup do
    original_workspace = Application.get_env(:wardwright, :policy_recipe_workspace_dir)

    workspace_dir = temp_workspace_dir("wardwright-live-default")

    Application.put_env(:wardwright, :policy_recipe_workspace_dir, workspace_dir)

    on_exit(fn ->
      case original_workspace do
        nil -> Application.delete_env(:wardwright, :policy_recipe_workspace_dir)
        value -> Application.put_env(:wardwright, :policy_recipe_workspace_dir, value)
      end
    end)

    Wardwright.reset_config()
    Wardwright.ReceiptStore.clear()
    Wardwright.PolicyScenarioStore.clear()
    Wardwright.PolicyCache.reset()
    :ok
  end

  test "policy projection exposes stable review fields and confidence classes" do
    :ok = put_route_gate_config()
    projection = Wardwright.PolicyProjection.projection("route-privacy")

    assert projection["projection_schema"] == "wardwright.policy_projection.v1"
    assert projection["engine"]["language"] == "structured"
    assert projection["artifact"]["artifact_hash"] =~ "sha256:"
    assert projection["compiled_plan"]["planner"] == "Wardwright.Policy.Plan"
    assert projection["state_machine"]["schema"] == "wardwright.policy_state_machine.v1"
    assert projection["state_machine"]["default_projection"] == true
    assert [%{"id" => "active", "node_ids" => node_ids}] = projection["state_machine"]["states"]

    nodes = projection["phases"] |> Enum.flat_map(& &1["nodes"])
    assert Enum.any?(nodes, &(&1["id"] == "request-policy.private-route-gate"))
    assert Enum.any?(nodes, &(&1["confidence"] == "exact"))
    assert Enum.all?(nodes, &is_binary(&1["node_class"]))
    assert Enum.all?(nodes, &is_binary(get_in(&1, ["annotations", "why"])))
    assert Enum.all?(nodes, &is_binary(get_in(&1, ["annotations", "change_when"])))
    assert "request-policy.private-route-gate" in node_ids
    assert [%{"class" => "ordered"}] = projection["conflicts"]
  end

  test "simulation traces link execution evidence back to projection nodes" do
    projection = Wardwright.PolicyProjection.projection("tts-retry")
    node_ids = projection["phases"] |> Enum.flat_map(& &1["nodes"]) |> MapSet.new(& &1["id"])

    [simulation | _] = Wardwright.PolicyProjection.simulations("tts-retry")

    assert simulation["artifact_hash"] == projection["artifact"]["artifact_hash"]
    assert simulation["verdict"] in ["passed", "failed", "inconclusive"]
    assert Enum.any?(simulation["trace"], &MapSet.member?(node_ids, &1["node_id"]))
    assert Enum.all?(simulation["trace"], &is_binary(&1["state_id"]))
    assert is_map(simulation["receipt_preview"])

    assert projection["state_machine"]["default_projection"] == false
    state_ids = projection["state_machine"]["states"] |> MapSet.new(& &1["id"])

    assert Enum.map(projection["state_machine"]["states"], & &1["id"]) == [
             "observing",
             "guarding",
             "retrying",
             "recording"
           ]

    assert Enum.map(projection["state_machine"]["states"], & &1["model_id"]) == [
             Wardwright.local_model(),
             "none",
             Wardwright.managed_model(),
             "none"
           ]

    assert Enum.map(projection["state_machine"]["simulation_steps"], & &1["state"]) == [
             "observing",
             "guarding",
             "retrying",
             "retrying",
             "recording"
           ]

    assert Enum.all?(
             projection["state_machine"]["simulation_steps"],
             &MapSet.member?(state_ids, &1["state"])
           )
  end

  test "projection simulations prefer persisted reviewed scenarios over fixtures" do
    assert {:ok, _scenario} =
             Wardwright.PolicyScenarioStore.create("tts-retry", %{
               "expected_behavior" => "Retry is requested before any violating bytes are released.",
               "input_summary" => "Reviewed request keeps OldClient split across stream chunks.",
               "pinned" => true,
               "receipt_preview" => %{"final_status" => "simulated"},
               "scenario_id" => "reviewed-split-trigger",
               "source" => "assistant",
               "title" => "Reviewed split trigger",
               "trace" => [
                 %{
                   "detail" => "persisted scenario hit the stream rule",
                   "id" => "r1",
                   "kind" => "match",
                   "label" => "reviewed match",
                   "node_id" => "tts.no-old-client",
                   "phase" => "response.streaming",
                   "severity" => "pass",
                   "state_id" => "guarding"
                 }
               ],
               "verdict" => "passed"
             })

    [simulation] = Wardwright.PolicyProjection.simulations("tts-retry")
    projection = Wardwright.PolicyProjection.projection("tts-retry")

    assert simulation["scenario_id"] == "reviewed-split-trigger"
    assert simulation["scenario_source"] == "persisted"
    assert simulation["source"] == "assistant"
    assert simulation["pinned"] == true
    assert simulation["artifact_hash"] == projection["artifact"]["artifact_hash"]
    assert get_in(simulation, ["trace", Access.at(0), "state_id"]) == "guarding"

    assert Enum.map(projection["state_machine"]["simulation_steps"], & &1["state"]) == [
             "guarding"
           ]
  end

  test "route projection simulation is derived from configured policy plan actions" do
    :ok = put_route_gate_config()
    [simulation] = Wardwright.PolicyProjection.simulations("route-privacy")

    assert simulation["scenario_id"] == "configured-route-policy"
    assert simulation["verdict"] == "passed"

    assert [
             %{
               "action" => "restrict_routes",
               "allowed_targets" => [local_model],
               "rule_id" => "private-route-gate"
             }
           ] = get_in(simulation, ["receipt_preview", "decision", "policy_actions"])

    assert local_model == Wardwright.local_model()

    assert %{"allowed_targets" => [^local_model]} =
             get_in(simulation, ["receipt_preview", "decision", "route_constraints"])
  end

  test "tool governance projection exposes tool phases without enforcing spike semantics" do
    :ok = put_tool_governance_config()

    projection = Wardwright.PolicyProjection.projection("tool-governance")
    [simulation] = Wardwright.PolicyProjection.simulations("tool-governance")

    assert projection["engine"]["engine_id"] == "tool-context-plan"

    assert projection["engine"]["capabilities"]["phases"] == [
             "tool.planning",
             "tool.result_interpreting",
             "tool.loop_governing",
             "receipt.finalized"
           ]

    nodes = projection["phases"] |> Enum.flat_map(& &1["nodes"])

    assert Enum.any?(nodes, fn node ->
             node["id"] == "tool-policy.github-write-tools" and
               node["reads"] == [
                 "request.tools",
                 "request.tool_choice",
                 "message.tool_calls",
                 "decision.tool_context"
               ] and
               node["writes"] == ["tool.allowed", "policy.actions"]
           end)

    assert Enum.any?(nodes, fn node ->
             node["id"] == "tool-policy.repeat-github-tool" and
               node["reads"] == ["decision.tool_context", "policy_cache.session.tool_call"] and
               node["writes"] == ["decision.blocked", "final.status"]
           end)

    assert Enum.any?(nodes, &(&1["id"] == "tool.receipt-context"))
    assert [%{"class" => "ordered", "node_ids" => node_ids}] = projection["conflicts"]
    assert "tool-policy.github-write-tools" in node_ids
    assert "tool-policy.shell-write-tools" in node_ids

    assert simulation["scenario_id"] == "configured-tool-policy"
    assert simulation["verdict"] == "passed"

    assert get_in(simulation, ["receipt_preview", "decision", "tool_context", "primary_tool"]) ==
             %{
               "name" => "create_pull_request",
               "namespace" => "mcp.github",
               "risk_class" => "write",
               "source" => "declared_tool"
             }
  end

  test "LiveView projection workbench renders selected pattern and mode" do
    original_workspace = Application.get_env(:wardwright, :policy_recipe_workspace_dir)

    workspace_dir = temp_workspace_dir("wardwright-live-render")

    Application.put_env(:wardwright, :policy_recipe_workspace_dir, workspace_dir)

    on_exit(fn ->
      case original_workspace do
        nil -> Application.delete_env(:wardwright, :policy_recipe_workspace_dir)
        value -> Application.put_env(:wardwright, :policy_recipe_workspace_dir, value)
      end
    end)

    :ok = put_route_gate_config()
    {:ok, view, html} = live(build_conn(), "/policies/route-privacy/trace_overlay")

    assert html =~ "Private context route gate"
    assert html =~ "Trace details"
    assert html =~ "raw run evidence"
    assert html =~ "Request route plan"
    assert html =~ "Artifact first"
    assert html =~ "Policy nodes"
    assert html =~ "Simulation evidence"
    assert html =~ "Review load"
    assert html =~ "Why this exists"

    connected_html = render(view)

    assert connected_html =~ "Private context route gate"
    assert connected_html =~ "Trace details"
    assert connected_html =~ "Request route plan"
    assert connected_html =~ "Artifact first"
    assert connected_html =~ "Policy nodes"
    assert connected_html =~ "Simulation evidence"
    assert connected_html =~ "State model"
    assert connected_html =~ "Review load"
    assert connected_html =~ "Why this exists"

    assert {:error, {:redirect, %{to: "/policies/route-privacy/effect_matrix/recipe/private-helpdesk-local-gate"}}} =
             view
             |> element("a", "Effect table")
             |> render_click()

    {:ok, matrix_view, _html} =
      live(
        build_conn(),
        "/policies/route-privacy/effect_matrix/recipe/private-helpdesk-local-gate"
      )

    matrix_html = render(matrix_view)

    assert matrix_html =~ "Private context route gate"
    assert matrix_html =~ "Effect table"
    assert matrix_html =~ "writes and actions"
    assert matrix_html =~ "route.allowed_targets"
  end

  test "browser layout loads the LiveView client runtime" do
    conn = get(build_conn(), "/policies/route-privacy/diagram")
    html = html_response(conn, 200)

    assert html =~ ~s(<meta name="csrf-token")
    assert html =~ ~s(src="/vendor/phoenix/phoenix.min.js")
    assert html =~ ~s(src="/vendor/phoenix_live_view/phoenix_live_view.min.js")
    assert html =~ ~s(src="/assets/wardwright_live.js")
  end

  test "workbench rejects remote browser access without an admin token" do
    conn =
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> get("/policies/route-privacy/diagram")

    assert conn.status == 403
    assert %{"error" => %{"code" => "protected_endpoint"}} = Jason.decode!(conn.resp_body)
  end

  test "workbench accepts remote browser access with a configured admin bearer token" do
    previous = Application.get_env(:wardwright, :admin_token)
    Application.put_env(:wardwright, :admin_token, "workbench-review-token")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :admin_token, previous),
        else: Application.delete_env(:wardwright, :admin_token)
    end)

    conn =
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> Plug.Conn.put_req_header("authorization", "Bearer workbench-review-token")
      |> get("/policies/route-privacy/diagram")

    html = html_response(conn, 200)
    assert html =~ "Policy projection graph"
    assert html =~ "Private context route gate"
  end

  test "workbench requires basic auth when a basic auth password is configured" do
    previous = Application.get_env(:wardwright, :basic_auth_password)
    Application.put_env(:wardwright, :basic_auth_password, "workbench-password")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :basic_auth_password, previous),
        else: Application.delete_env(:wardwright, :basic_auth_password)
    end)

    local_rejected = get(build_conn(), "/policies/route-privacy/diagram")
    assert local_rejected.status == 401

    assert Plug.Conn.get_resp_header(local_rejected, "www-authenticate") == [
             ~s(Basic realm="Wardwright", charset="UTF-8")
           ]

    wrong_user =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", basic_auth("operator", "workbench-password"))
      |> get("/policies/route-privacy/diagram")

    assert wrong_user.status == 401

    accepted =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", basic_auth("admin", "workbench-password"))
      |> get("/policies/route-privacy/diagram")

    html = html_response(accepted, 200)
    assert html =~ "Policy projection graph"
    assert html =~ "Private context route gate"
  end

  test "legacy workbench links to the primary workbench for side-by-side operation" do
    {:ok, _view, html} = live(build_conn(), "/policies/tts-retry/diagram")

    assert html =~ ~s(href="/workbench")
    assert html =~ "Legacy Workbench"
    assert html =~ "Use the previous policy projection view."
    refute html =~ "Lustre Workbench"
    refute html =~ "Gleam UI"
  end

  test "model API key management page creates and revokes keys" do
    conn = get(build_conn(), "/admin/model-api-keys")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "<title>Wardwright Model Access</title>"
    assert conn.resp_body =~ "/admin/model-api-keys/socket/websocket"
    refute conn.resp_body =~ "live_socket"

    assert :wardwright@lustre_model_access_test_support.initial_view_contains("Model Access")
    assert :wardwright@lustre_model_access_test_support.initial_view_contains("coding-balanced")
    assert :wardwright@lustre_model_access_test_support.initial_view_contains("Access Policy")
    assert :wardwright@lustre_model_access_test_support.initial_view_contains("Legacy Workbench")

    assert :wardwright@lustre_model_access_test_support.initial_view_contains(
             "No API keys have been created for this model."
           )

    assert :wardwright@lustre_model_access_test_support.creating_key_shows_secret(
             "coding-balanced",
             "local-gateway"
           )

    assert [%{"id" => id, "label" => "local-gateway"}] =
             Wardwright.ModelApiKeyStore.list("coding-balanced")

    assert :wardwright@lustre_model_access_test_support.revoking_key_removes_it(
             "coding-balanced",
             id
           )

    assert Wardwright.ModelApiKeyStore.list("coding-balanced") == []
  end

  test "model API key management page edits keyed and unkeyed access" do
    assert :wardwright@lustre_model_access_test_support.initial_view_contains("Unkeyed")
    assert :wardwright@lustre_model_access_test_support.initial_view_contains("Unkeyed access")
    refute Wardwright.model_requires_api_key?()
    assert Wardwright.unkeyed_model_access() == "public"

    assert :wardwright@lustre_model_access_test_support.saving_access_updates_mode(
             "coding-balanced",
             "false",
             "internal",
             "Model access saved."
           )

    refute Wardwright.model_requires_api_key?()
    assert Wardwright.unkeyed_model_access() == "internal"

    assert :wardwright@lustre_model_access_test_support.saving_access_updates_mode(
             "coding-balanced",
             "true",
             "internal",
             "API key required"
           )

    assert Wardwright.model_requires_api_key?()
    assert Wardwright.unkeyed_model_access() == "internal"

    assert :wardwright@lustre_model_access_test_support.saving_access_updates_mode(
             "coding-balanced",
             "false",
             "public",
             "Unkeyed"
           )

    refute Wardwright.model_requires_api_key?()
    assert Wardwright.unkeyed_model_access() == "public"
  end

  test "model API key management page edits only the selected model" do
    alpha =
      Wardwright.default_config()
      |> Map.put("model_id", "alpha-access")

    beta =
      Wardwright.default_config()
      |> Map.put("model_id", "beta-access")

    assert {:ok, _alpha} = Wardwright.put_config(alpha)
    assert {:ok, _beta} = Wardwright.put_model_config(beta)

    assert :wardwright@lustre_model_access_test_support.initial_view_contains("alpha-access")
    assert :wardwright@lustre_model_access_test_support.initial_view_contains("beta-access")

    assert :wardwright@lustre_model_access_test_support.saving_access_updates_mode(
             "alpha-access",
             "true",
             "internal",
             "Model access saved."
           )

    assert {:ok, alpha_config} = Wardwright.model_config("alpha-access")
    assert {:ok, beta_config} = Wardwright.model_config("beta-access")

    assert Wardwright.model_requires_api_key?(alpha_config)
    assert Wardwright.unkeyed_model_access(alpha_config) == "internal"
    refute Wardwright.model_requires_api_key?(beta_config)
    assert Wardwright.unkeyed_model_access(beta_config) == "public"
  end

  test "LiveView client assets are served without an npm build step" do
    conn = get(build_conn(), "/assets/wardwright_live.js")
    assert response(conn, 200) =~ "new window.LiveView.LiveSocket"

    conn = get(build_conn(), "/vendor/phoenix/phoenix.min.js")
    assert response(conn, 200) =~ "var Phoenix"

    conn = get(build_conn(), "/vendor/phoenix_live_view/phoenix_live_view.min.js")
    assert response(conn, 200) =~ "var LiveView"
  end

  test "LiveView diagram mode renders projection graph from backend facts" do
    {:ok, view, html} = live(build_conn(), "/policies/tts-retry/diagram")

    assert html =~ "Time-travel stream retry"
    assert html =~ "Advanced projection details"
    assert html =~ "Use your agent"
    assert html =~ "/mcp"
    assert html =~ "wardwright tools"
    assert html =~ "wardwright admin"
    assert html =~ "Registered model workbench"
    assert html =~ "Selecting a model leaves example preview"
    assert html =~ "Model Access"
    assert html =~ "href=\"/admin/model-api-keys\""
    assert html =~ "/v1/chat/completions"
    assert html =~ "coding-balanced"
    assert html =~ "wardwright/coding-balanced"
    assert html =~ Wardwright.local_model()
    assert html =~ "Model Authoring Assistant"
    assert html =~ "setup needed"
    assert html =~ "qwen3.6-plus"
    assert html =~ "Tool access"
    assert html =~ "draft tools enabled"
    assert html =~ "Ask agent"
    assert html =~ "Policy Simulator"
    assert html =~ "Policy run map"
    assert html =~ "State and turn model"
    assert html =~ "Playback"
    assert html =~ "Ready: 5 trace events available for playback."
    assert html =~ "waiting at input boundary"
    assert html =~ "Policy projection graph"
    assert html =~ "possible route for this input"
    assert html =~ "already played"
    assert html =~ "conflict"
    assert html =~ "no-old-client"
    assert html =~ "retry arbiter"
    assert html =~ "abort_attempt"
    assert html =~ "retry_with_reminder"
    assert html =~ "Attempt loop"
    assert html =~ "Attempt 1"
    assert html =~ "withheld_and_aborted"
    assert html =~ "Attempt 2"
    assert html =~ "released_after_retry"
    assert html =~ "Use the current client adapter in the migration note."
    refute html =~ "No output is released to the user in this simulated branch"

    connected_html = render(view)

    assert connected_html =~ "regex matched"
    assert connected_html =~ "retry selected"
    assert connected_html =~ "retry stream released"
    assert connected_html =~ "receipt preview"
  end

  test "LiveView workbench model selector drives projection and simulator config" do
    alpha =
      Wardwright.default_config()
      |> Map.put("model_id", "alpha-workbench")

    beta =
      Wardwright.default_config()
      |> Map.put("model_id", "beta-workbench")
      |> Map.put("description", "Beta workbench catches mooing output before release.")
      |> Map.update!("targets", fn [first | rest] ->
        [Map.put(first, "provider_headers", %{"X-Api-Key" => "visible-secret"}) | rest]
      end)
      |> Map.put("stream_rules", [
        %{"action" => "rewrite_chunk", "id" => "beta-moo", "regex" => "\\bmoo+\\b", "replacement" => "[rewritten]"}
      ])

    assert {:ok, _alpha} = Wardwright.put_config(alpha)
    assert {:ok, _beta} = Wardwright.put_model_config(beta)

    beta_hash =
      Wardwright.PolicyProjection.projection("tts-retry", beta)["artifact"]["artifact_hash"]

    {:ok, view, html} = live(build_conn(), "/policies/tts-retry/diagram?model=beta-workbench")

    assert html =~ "Registered model workbench:"
    assert html =~ "<h1>beta-workbench</h1>"
    assert html =~ "Beta workbench catches mooing output before release."
    assert html =~ "<strong>beta-workbench</strong>"
    assert html =~ beta_hash
    assert html =~ "Selected Model Configuration"
    assert html =~ "Show redacted model configuration"
    assert html =~ "Registered model selected"
    assert html =~ "Try this registered model"
    assert html =~ "stream policy triggered"
    assert html =~ "User receives after Wardwright"
    assert html =~ "The model says [rewritten] in a draft answer."
    assert html =~ "Model receives"
    assert html =~ "beta-moo"
    assert html =~ "\\\\bmoo+\\\\b"
    assert html =~ "X-Api-Key"
    assert html =~ "[redacted]"
    refute html =~ "visible-secret"
    assert html =~ "Runtime Visibility"
    assert html =~ "History Cache"
    assert html =~ "alpha-workbench"
    assert html =~ "beta-workbench"
    refute html =~ "Policy run map"
    refute html =~ "State and turn model"
    refute html =~ "Receipt Preview"
    refute html =~ "Selected Node"
    refute html =~ "Review Findings"
    refute html =~ "retry arbiter"
    refute html =~ "Example story"
    refute html =~ "A coding assistant keeps recommending an old client constructor"
    refute html =~ "Choose a registered model"

    changed =
      view
      |> element("#model-turn-editor-form")
      |> render_change(%{
        "model_simulation" => %{
          "model_response" => "ordinary answer",
          "user_input" => "moo from the user"
        }
      })

    assert changed =~ "Model receives this input unchanged."
    assert changed =~ "Released unchanged. The user receives this raw model output."
    assert changed =~ "User receives"
    assert changed =~ "ordinary answer"

    changed =
      view
      |> element("#model-turn-editor-form")
      |> render_submit(%{
        "model_simulation" => %{
          "model_response" => "the model says mooo",
          "user_input" => "ordinary user input"
        }
      })

    assert changed =~ "User receives after Wardwright"
    assert changed =~ "the model says [rewritten]"
    assert changed =~ "beta-moo triggered rewrite_chunk"
    assert changed =~ "response.streaming"

    updated =
      view
      |> element("form.workbench_model_selector")
      |> render_change(%{"workbench_model" => "alpha-workbench"})

    assert updated =~ "Registered model workbench:"
    assert updated =~ "<h1>alpha-workbench</h1>"
    assert updated =~ "<strong>alpha-workbench</strong>"
    assert updated =~ "Registered model selected"
    assert updated =~ "Try this registered model"
    assert updated =~ "Runtime Visibility"
    assert updated =~ "History Cache"
    refute updated =~ "Policy run map"
    refute updated =~ "State and turn model"
    refute updated =~ "Receipt Preview"
    refute updated =~ "Selected Node"
    refute updated =~ "Review Findings"
    refute updated =~ "Example story"

    assert updated =~
             "/policies/stream-rewrite-state/diagram/recipe/credential-redaction-ladder"

    refute updated =~
             "/policies/stream-rewrite-state/diagram/recipe/credential-redaction-ladder?model=alpha-workbench"
  end

  test "registered model simulator includes request governance and route decisions" do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "cow-transform-workbench")
      |> Map.put("version", "request-transform-test")
      |> Map.put("governance", [
        %{
          "action" => "transform",
          "contains" => "moo",
          "id" => "cow-moo-user-reminder",
          "kind" => "request_transform",
          "message" => "mooing user input matched",
          "reminder" => "Include a small ASCII cow, then answer normally."
        }
      ])
      |> Map.put("stream_rules", [])
      |> Map.put("targets", [%{"context_window" => 8192, "model" => "ollama/gemma4:e4b"}])
      |> Map.put("dispatchers", [%{"id" => "dispatcher.cow", "models" => ["ollama/gemma4:e4b"]}])
      |> Map.put("route_root", "dispatcher.cow")

    simulation =
      Wardwright.PolicyProjection.simulate_model_turn(
        "please moo for me",
        "ordinary answer",
        config
      )

    assert get_in(simulation, ["receipt_preview", "decision", "selected_model"]) ==
             "ollama/gemma4:e4b"

    assert [
             %{
               "action" => "transform",
               "reminder_injected" => true,
               "rule_id" => "cow-moo-user-reminder"
             }
           ] = get_in(simulation, ["receipt_preview", "decision", "policy_actions"])

    assert get_in(simulation, ["receipt_preview", "input", "model_received_input"]) =~
             "user: please moo for me"

    assert get_in(simulation, ["receipt_preview", "input", "model_received_input"]) =~
             "system/wardwright_policy_reminder: Include a small ASCII cow"

    assert Enum.any?(simulation["trace"], fn event ->
             event["label"] == "request transform applied" and
               event["detail"] =~ "Include a small ASCII cow"
           end)

    {:ok, _config} = Wardwright.put_model_config(config)
    {:ok, view, html} = live(build_conn(), "/policies/tts-retry/diagram?model=cow-transform-workbench")

    assert html =~ "Try this registered model"

    changed =
      view
      |> element("#model-turn-editor-form")
      |> render_submit(%{
        "model_simulation" => %{
          "model_response" => "plain response",
          "user_input" => "no trigger"
        }
      })

    assert changed =~ "Model receives this input unchanged."
  end

  test "registered model simulator does not pretend stream rules rewrite requests" do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "request-stream-rule-workbench")
      |> Map.put("governance", [])
      |> Map.put("stream_rules", [
        %{
          "action" => "rewrite_chunk",
          "direction" => "request",
          "id" => "literal-pattern",
          "pattern" => "\\bmoo\\b",
          "replacement" => "[literal-pattern]"
        },
        %{
          "action" => "rewrite_chunk",
          "direction" => "request",
          "id" => "regex-moo",
          "regex" => "\\bmoo+\\b",
          "replacement" => "[regex-moo]"
        },
        %{
          "action" => "rewrite_chunk",
          "contains" => "snack",
          "direction" => "request",
          "id" => "literal-contains",
          "replacement" => "[literal-contains]"
        }
      ])

    simulation =
      Wardwright.PolicyProjection.simulate_model_turn(
        "please mooo and bring snack",
        "plain response",
        config
      )

    assert get_in(simulation, ["receipt_preview", "input", "model_received_input"]) =~
             "please mooo and bring snack"

    refute get_in(simulation, ["receipt_preview", "input", "model_received_input"]) =~ "[regex-moo]"
    refute get_in(simulation, ["receipt_preview", "input", "model_received_input"]) =~ "[literal-contains]"

    assert Enum.any?(simulation["trace"], fn event ->
             event["label"] == "simulation coverage gap" and
               event["detail"] =~ "Request-direction stream_rules are not executed"
           end)
  end

  test "registered model simulator reports unsupported coverage gaps loudly" do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "coverage-gap-workbench")
      |> Map.put("structured_output", %{"schema" => %{"type" => "object"}})
      |> Map.put("governance", [
        %{
          "action" => "constrain_tools",
          "id" => "tool-policy",
          "kind" => "tool_sequence",
          "phase" => "tool.using"
        }
      ])

    simulation =
      Wardwright.PolicyProjection.simulate_model_turn(
        "ordinary user input",
        ~s({"status":"ok"}),
        config
      )

    assert Enum.any?(simulation["trace"], fn event ->
             event["label"] == "simulation coverage gap" and
               event["detail"] =~ "Structured-output repair"
           end)

    assert Enum.any?(simulation["trace"], fn event ->
             event["label"] == "simulation coverage gap" and event["detail"] =~ "Tool planning"
           end)
  end

  test "LiveView can save the edited user and model turn as a reusable scenario" do
    {:ok, view, _html} = live(build_conn(), "/policies/tts-retry/diagram")

    view
    |> element("#turn-editor-form")
    |> render_change(%{
      "simulation" => %{
        "model_response" => "The migration used Old\nClient( in a draft.",
        "response_attempts" => %{"2" => "Use the current client adapter in the migration note."},
        "user_input" => "Please mention the old client constructor."
      }
    })

    html =
      view
      |> element("form[phx-submit='save-simulation-scenario']")
      |> render_submit(%{
        "scenario" => %{"pinned" => "true", "title" => "Reviewed old-client split"}
      })

    assert html =~ "Saved Reviewed old-client split."
    assert html =~ "Saved test cases"
    assert html =~ "Reviewed old-client split"

    assert [
             scenario
           ] = Wardwright.PolicyScenarioStore.list("tts-retry")

    assert scenario.title == "Reviewed old-client split"
    assert scenario.pinned
    assert scenario.model_id == "coding-balanced"
    assert scenario.artifact_hash =~ "sha256:"
    assert scenario.turn["user_input"] == "Please mention the old client constructor."
    assert scenario.turn["model_response"] =~ "Old\nClient"

    assert Enum.any?(
             scenario.turn["response_attempts"],
             &(&1["index"] == 2 and &1["model_output"] =~ "current client adapter")
           )

    html =
      view
      |> element("form[phx-submit='select-simulation-input']")
      |> render_submit(%{"simulation_input" => "saved:#{scenario.id}"})

    assert html =~ "Delete selected"

    html =
      view
      |> element("button[phx-click='delete-simulation-scenario']")
      |> render_click()

    assert html =~ "Deleted Reviewed old-client split."
    assert Wardwright.PolicyScenarioStore.list("tts-retry") == []
  end

  test "LiveView authoring agent panel submits to the local fallback without credentials" do
    {:ok, view, html} = live(build_conn(), "/policies/tts-retry/diagram")

    assert html =~ "Model Authoring Assistant"

    response =
      render_submit(view, "authoring-agent-submit", %{
        "authoring_agent" => %{"message" => "Help me tighten this retry model."}
      })

    assert response =~ "You"
    assert response =~ "Wardwright assistant"
    assert response =~ "Help me tighten this retry model."
    assert response =~ "Working..."

    completed =
      eventually_render(
        view,
        "Wardwright&#39;s authoring assistant is installed but not configured"
      )

    assert completed =~ "Wardwright&#39;s authoring assistant is installed but not configured"
    assert completed =~ "simulate_policy"
  end

  test "LiveView authoring agent keeps model drafts reviewable before activation" do
    original_client = Application.get_env(:wardwright, :authoring_agent_client, :unset)
    original_enabled = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED")
    original_api_key = System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY")
    original_route = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    Application.put_env(:wardwright, :authoring_agent_client, __MODULE__.DraftingAuthoringClient)
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")
    System.delete_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    on_exit(fn ->
      case original_client do
        :unset -> Application.delete_env(:wardwright, :authoring_agent_client)
        client -> Application.put_env(:wardwright, :authoring_agent_client, client)
      end

      restore_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", original_enabled)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", original_api_key)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", original_route)
    end)

    {:ok, view, _html} = live(build_conn(), "/policies/tts-retry/diagram")

    render_submit(view, "authoring-agent-submit", %{
      "authoring_agent" => %{"message" => "Make a cow model."}
    })

    completed = eventually_render(view, "Drafts Awaiting Review", 60)

    assert completed =~ "cow-lover-mode"
    assert completed =~ "not active"
    assert completed =~ "Activate draft"
    assert completed =~ "Review and activate the draft from the workbench"
    assert {:error, _message} = Wardwright.model_config("cow-lover-mode")

    activated =
      view
      |> element("button", "Activate draft")
      |> render_click()

    assert activated =~ "Activated cow-lover-mode"
    assert {:ok, config} = Wardwright.model_config("cow-lover-mode")
    assert Wardwright.model_id(config) == "cow-lover-mode"
    assert [%{"action" => "rewrite_chunk", "id" => "cow-art"}] = config["stream_rules"]
  end

  test "LiveView authoring agent reports malformed tool plans without leaking raw JSON" do
    original_client = Application.get_env(:wardwright, :authoring_agent_client, :unset)
    original_enabled = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED")
    original_api_key = System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY")
    original_route = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.MalformedToolPlanAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")
    System.delete_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    on_exit(fn ->
      case original_client do
        :unset -> Application.delete_env(:wardwright, :authoring_agent_client)
        client -> Application.put_env(:wardwright, :authoring_agent_client, client)
      end

      restore_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", original_enabled)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", original_api_key)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", original_route)
    end)

    {:ok, view, _html} = live(build_conn(), "/policies/tts-retry/diagram")

    render_submit(view, "authoring-agent-submit", %{
      "authoring_agent" => %{"message" => "Make a cow model."}
    })

    completed = eventually_render(view, "could not parse it as valid JSON", 60)

    assert completed =~ "No tool was executed"
    refute completed =~ "\"tool_calls\""
    refute completed =~ "\"arguments\""
    refute completed =~ "Drafts Awaiting Review"
  end

  test "LiveView diagram simulation can step through matching rules and state changes" do
    {:ok, view, html} = live(build_conn(), "/policies/tts-retry/diagram")

    assert html =~ "Ready: 5 trace events available for playback."
    assert html =~ "waiting at input boundary"
    assert html =~ "pending"

    stepped =
      view
      |> element("button", "Step")
      |> render_click()

    assert stepped =~ "Step 1 of 5: state observing, response.streaming."
    assert stepped =~ "chunk held"
    assert stepped =~ "active"

    stepped =
      view
      |> element("button", "Step")
      |> render_click()

    assert stepped =~ "Step 2 of 5: state guarding, response.streaming."
    assert stepped =~ "regex matched"
    assert stepped =~ "completed"

    stepped =
      view
      |> element("button", "Step")
      |> render_click()

    assert stepped =~ "Step 3 of 5: state retrying, response.streaming."
    assert stepped =~ "retry selected"

    stepped =
      view
      |> element("button", "Step")
      |> render_click()

    assert stepped =~ "Step 4 of 5: state retrying, response.streaming."
    assert stepped =~ "retry stream released"

    stepped_back =
      view
      |> element("button", "Back")
      |> render_click()

    assert stepped_back =~ "Step 3 of 5: state retrying, response.streaming."
    assert stepped_back =~ "retry selected"

    reset =
      view
      |> element("button", "Reset")
      |> render_click()

    assert reset =~ "Ready: 5 trace events available for playback."
    assert reset =~ "waiting at input boundary"
  end

  test "LiveView diagram simulation can open directly to a reviewed playback step" do
    {:ok, _view, html} = live(build_conn(), "/policies/tts-retry/diagram/step/2")

    assert html =~ "Step 2 of 5: state guarding, response.streaming."
    assert html =~ "regex matched"
    assert html =~ "Client( completes the prohibited span"
    assert html =~ "completed"
    assert html =~ "active"
  end

  test "LiveView diagram simulation controls restart cleanly from the final step" do
    {:ok, view, html} = live(build_conn(), "/policies/tts-retry/diagram/step/5")

    assert html =~ "Step 5 of 5: state recording, receipt.finalized."

    restarted =
      view
      |> element("button", "Step")
      |> render_click()

    assert restarted =~ "Ready: 5 trace events available for playback."
    assert restarted =~ "waiting at input boundary"

    playing =
      view
      |> element("button", "Play")
      |> render_click()

    assert playing =~ "Pause"
  end

  test "LiveView diagram ignores stale playback timer messages" do
    {:ok, view, _html} = live(build_conn(), "/policies/tts-retry/diagram")

    playing =
      view
      |> element("button", "Play")
      |> render_click()

    assert playing =~ "Ready: 5 trace events available for playback."
    assert playing =~ "Pause"

    send(view.pid, {:advance_simulation, make_ref()})
    Process.sleep(20)

    unchanged = render(view)

    assert unchanged =~ "Ready: 5 trace events available for playback."
    assert unchanged =~ "Pause"
    refute unchanged =~ "Step 1 of 5"
  end

  test "LiveView diagram can demonstrate related regex rewrite and state transition" do
    {:ok, _view, html} = live(build_conn(), "/policies/stream-rewrite-state/diagram/step/3")

    assert html =~ "Regex rewrite and state transition"
    assert html =~ "Example catalog"
    assert html =~ "Example scenarios"
    assert html =~ "Examples are read-only previews."
    assert html =~ "Project examples"
    assert html =~ "wardwright.dev/recipes"
    assert html =~ "account redactor"
    assert html =~ "secret transition"
    assert html =~ "rewrite arbiter"
    assert html =~ "Step 3 of 5: state review_required, response.streaming."
    assert html =~ "related secret matched"
    assert html =~ "state_transition"
    assert html =~ "hold_for_review"
  end

  test "LiveView diagram recomputes policy path from editable user and model turn" do
    {:ok, view, html} = live(build_conn(), "/policies/stream-rewrite-state/diagram")

    assert html =~ "Editable turn"
    assert html =~ "Raw user input"
    assert html =~ "Raw model output / stream"
    assert html =~ "User-visible output"
    refute html =~ "Model receives after Wardwright"
    assert html =~ "Relevant examples"
    assert html =~ "Cross-policy probes"
    assert html =~ "review_required"
    assert html =~ "No output is released to the user in this simulated branch"

    changed =
      view
      |> element("form.turn_editor_grid")
      |> render_change(%{
        "simulation" => %{
          "model_response" => "ordinary response text with no matching tokens",
          "user_input" => "Write a neutral update."
        }
      })

    assert changed =~ "Edited stream has no regex match"
    assert changed =~ "stream released"
    assert changed =~ "Ready: 3 trace events available for playback."
    assert changed =~ "ordinary response text with no matching tokens"
    assert changed =~ "Released unchanged. The user receives this raw model output."
    refute changed =~ "User receives after Wardwright"
    refute changed =~ "review hold selected"
  end

  test "LiveView diagram releases unchanged output when edited text no longer matches rewrite rules" do
    {:ok, view, _html} = live(build_conn(), "/policies/stream-rewrite-state/diagram")

    selected =
      view
      |> element("form[phx-change='select-simulation-input']")
      |> render_change(%{"simulation_input" => "rewrite-then-secret"})

    assert selected =~ "No output is released to the user in this simulated branch"

    changed =
      view
      |> element("form.turn_editor_grid")
      |> render_change(%{
        "simulation" => %{
          "history_context" => %{"policy_state" => "observing", "recent_related_secret_matches" => "0"},
          "model_response" => "account {redacted} appears in the answer\n{redacted} follows in the held horizon",
          "user_input" => "Summarize the billing incident without exposing credentials."
        }
      })

    assert changed =~ "Edited stream has no regex match"
    assert changed =~ "stream released"
    assert changed =~ "Released unchanged. The user receives this raw model output."
    assert changed =~ "account {redacted} appears in the answer"
    refute changed =~ "No output is released to the user in this simulated branch"
    refute changed =~ "User-visible output"
  end

  test "LiveView diagram shows before and after boundaries only when policy rewrites them" do
    {:ok, view, html} = live(build_conn(), "/policies/stream-rewrite-state/diagram")

    assert html =~ "Stream: input and output rewrite"
    assert html =~ "Load scenario"
    refute html =~ "Model receives after Wardwright"

    selected =
      view
      |> element("form[phx-change='select-simulation-input']")
      |> render_change(%{"simulation_input" => "input-and-output-rewrite"})

    assert selected =~ "Raw user input"
    assert selected =~ "Model receives after Wardwright"
    assert selected =~ "[private-context omitted]"
    assert selected =~ "Raw model output / stream"
    assert selected =~ "User receives after Wardwright"
    assert selected =~ "account [account-id]"
    assert selected =~ "request context redacted"
    assert selected =~ "alex@example.test"

    submitted =
      view
      |> element("form[phx-submit='select-simulation-input']")
      |> render_submit(%{"simulation_input" => "no-match"})

    assert submitted =~ "Edited stream has no regex match"
    assert submitted =~ "Released unchanged. The user receives this raw model output."
    refute submitted =~ "User receives after Wardwright"
  end

  test "LiveView simulation lets authors edit referenced history that changes behavior" do
    {:ok, view, _html} = live(build_conn(), "/policies/stream-rewrite-state/diagram")

    selected =
      view
      |> element("form[phx-change='select-simulation-input']")
      |> render_change(%{"simulation_input" => "rewrite-only"})

    assert selected =~ "Policy memory used by this run"
    assert selected =~ "Prior related secret matches"
    assert selected =~ "rewritten stream released"
    refute selected =~ "prior related matches read"

    threshold =
      view
      |> element("form[phx-submit='select-simulation-input']")
      |> render_submit(%{"simulation_input" => "history-threshold-escalation"})

    assert threshold =~ "Stream: history threshold escalates"
    assert threshold =~ "Relevant examples"
    assert threshold =~ "History window size"
    assert threshold =~ "3 related secret match"
    assert threshold =~ "review hold selected"

    changed =
      view
      |> element("form.turn_editor_grid")
      |> render_change(%{
        "simulation" => %{
          "history_context" => %{
            "policy_state" => "observing",
            "recent_related_secret_matches" => "3",
            "recent_secret_window_requests" => "5"
          },
          "model_response" => "account acct_4938 appears in the answer with no new token.",
          "user_input" => "Summarize the billing incident without exposing credentials."
        }
      })

    assert changed =~ "prior related matches read"
    assert changed =~ "3 related secret match"
    assert changed =~ "review hold selected"
    assert changed =~ "No output is released to the user in this simulated branch"
  end

  test "LiveView simulation shows state transitions that affect the next turn model" do
    {:ok, view, _html} = live(build_conn(), "/policies/stream-rewrite-state/diagram")

    selected =
      view
      |> element("form[phx-change='select-simulation-input']")
      |> render_change(%{"simulation_input" => "next-turn-review-model"})

    assert selected =~ "Stream: next turn uses review model"
    assert selected =~ "State and turn model"
    assert selected =~ "Turn model: managed/kimi-k2.6"
    assert selected =~ "After this run: review_required uses managed/kimi-k2.6."
    assert selected =~ "history threshold matched"
    assert selected =~ "current stream released"
    assert selected =~ "state change affects subsequent turns"
    assert selected =~ "Released unchanged. The user receives this raw model output."
    refute selected =~ "No output is released to the user in this simulated branch"
  end

  test "LiveView diagram keeps cross-policy scenarios selectable for every policy" do
    {:ok, view, html} = live(build_conn(), "/policies/ambiguous-success/diagram")

    assert html =~ "Artifact: claim without artifact"
    assert html =~ "TTSR: split prohibited span"

    changed =
      view
      |> element("form[phx-change='select-simulation-input']")
      |> render_change(%{"simulation_input" => "split-old-client"})

    assert changed =~ "TTSR: split prohibited span"
    assert changed =~ "Edited input clears missing artifact alert"
    assert changed =~ "no alert"
  end

  test "LiveView recipe source can point at workspace catalogs without changing projection contract" do
    original_workspace = Application.get_env(:wardwright, :policy_recipe_workspace_dir)

    workspace_dir = temp_workspace_dir("wardwright-live-recipes")

    File.mkdir_p!(workspace_dir)

    File.write!(
      Path.join(workspace_dir, "tool-demo.json"),
      Jason.encode!(%{
        "category" => "tool.using",
        "id" => "tool-demo",
        "pattern_id" => "tool-governance",
        "promise" => "Review a locally curated tool policy recipe.",
        "title" => "Workspace tool policy"
      })
    )

    File.write!(
      Path.join(workspace_dir, "unsupported-demo.json"),
      Jason.encode!(%{
        "category" => "policy.future",
        "id" => "unsupported-demo",
        "pattern_id" => "future-policy-engine",
        "promise" => "Exercise a recipe that this build cannot project yet.",
        "title" => "Unsupported future policy"
      })
    )

    Application.put_env(:wardwright, :policy_recipe_workspace_dir, workspace_dir)

    on_exit(fn ->
      case original_workspace do
        nil -> Application.delete_env(:wardwright, :policy_recipe_workspace_dir)
        value -> Application.put_env(:wardwright, :policy_recipe_workspace_dir, value)
      end
    end)

    {:ok, view, html} = live(build_conn(), "/policies/tool-governance/diagram?source=workspace")

    assert html =~ "Project examples"
    assert html =~ workspace_dir
    assert html =~ "Workspace tool policy"
    assert html =~ "1 examples reference unsupported policy patterns for this build."
    refute html =~ "Unsupported future policy"
    assert html =~ "Tool call governance"
    assert html =~ "tool receipt context"

    workspace =
      view
      |> element("form.recipe_source")
      |> render_change(%{"recipe_source" => "built_in"})

    assert workspace =~ "Project examples"
    assert workspace =~ workspace_dir
    assert workspace =~ "Workspace tool policy"
    refute workspace =~ "Built-in examples"

    {:ok, view, _html} = live(build_conn(), "/policies/tool-governance/diagram?source=workspace")

    assert {:error, {:redirect, %{to: "/policies/tool-governance/state_machine/recipe/tool-loop-cost-brake"}}} =
             view
             |> element("a", "State model")
             |> render_click()

    {:ok, _state_view, updated} =
      live(build_conn(), "/policies/tool-governance/state_machine/recipe/tool-loop-cost-brake")

    assert updated =~ "Project examples"
    assert updated =~ "State model"
  end

  test "LiveView default project example source loads committed starter recipes" do
    original_workspace = Application.get_env(:wardwright, :policy_recipe_workspace_dir)

    workspace_dir = temp_workspace_dir("wardwright-live-starter-recipes")

    Application.put_env(:wardwright, :policy_recipe_workspace_dir, workspace_dir)

    on_exit(fn ->
      case original_workspace do
        nil -> Application.delete_env(:wardwright, :policy_recipe_workspace_dir)
        value -> Application.put_env(:wardwright, :policy_recipe_workspace_dir, value)
      end
    end)

    {:ok, view, html} = live(build_conn(), "/policies/route-privacy/diagram")

    assert html =~ "Project examples"
    assert html =~ workspace_dir
    assert html =~ "Route and model composition"
    assert html =~ "Stream repair and session state"
    assert html =~ "Private helpdesk route gate"
    assert html =~ "Context-window dispatcher"
    assert html =~ "Partial alloy context ladder"

    assert active_recipe_link?(html, "private-helpdesk-local-gate")

    assert html =~ "Deprecated SDK stream retry"
    assert html =~ "Keep customer-private helpdesk turns"
    refute html =~ "Built-in examples"

    selected =
      view
      |> element(~s(a[href="/policies/route-privacy/diagram/recipe/context-window-dispatcher"]))
      |> render_click()

    assert active_recipe_link?(selected, "context-window-dispatcher")

    {:ok, _direct_view, direct_html} =
      live(build_conn(), "/policies/route-privacy/diagram/recipe/context-window-dispatcher")

    assert active_recipe_link?(direct_html, "context-window-dispatcher")
    assert direct_html =~ "Example preview:"
    assert direct_html =~ "Choose a registered model"
  end

  test "LiveView recipe selection changes ambiguous-success scenarios" do
    {:ok, _artifact_view, artifact_html} =
      live(build_conn(), "/policies/ambiguous-success/diagram/recipe/done-but-missing-artifact")

    assert artifact_html =~ "Done, but missing artifact"
    assert artifact_html =~ "Artifact: claim without artifact"
    refute artifact_html =~ "JSON: malformed response gets repair feedback"

    {:ok, view, structured_html} =
      live(
        build_conn(),
        "/policies/ambiguous-success/diagram/recipe/structured-output-repair-gate"
      )

    assert structured_html =~ "Structured output repair gate"
    assert structured_html =~ "JSON: malformed response gets repair feedback"
    assert structured_html =~ "retry_with_validation_feedback"
    refute structured_html =~ "Artifact: claim without artifact"

    selected =
      view
      |> element("form[phx-change='select-simulation-input']")
      |> render_change(%{"simulation_input" => "json-valid-alternate-schema"})

    assert selected =~ "JSON: alternate accepted schema"
    assert selected =~ "accepted schema branch"
    assert selected =~ "contract recorded"
    refute selected =~ "missing artifact alert"
  end

  defp active_recipe_link?(html, recipe_id) do
    Regex.match?(
      ~r/<a(?=[^>]*class="active")(?=[^>]*href="\/policies\/route-privacy\/diagram\/recipe\/#{Regex.escape(recipe_id)}")[^>]*>/,
      html
    )
  end

  test "LiveView diagram mode reflects configured route and tool policies" do
    :ok = put_route_gate_config()
    {:ok, _route_view, route_html} = live(build_conn(), "/policies/route-privacy/diagram")

    assert route_html =~ "Private context route gate"
    assert route_html =~ "private-route-gate"
    assert route_html =~ "fallback-route-gate"
    assert route_html =~ "restrict_routes"
    assert route_html =~ "switch_model"
    assert route_html =~ "route"
    assert route_html =~ "Multiple"
    assert route_html =~ "policy"

    :ok = put_tool_governance_config()
    {:ok, _tool_view, tool_html} = live(build_conn(), "/policies/tool-governance/diagram")

    assert tool_html =~ "Tool call governance"
    assert tool_html =~ "github-write-tools"
    assert tool_html =~ "shell-write-tools"
    assert tool_html =~ "repeat-github-tool"
    assert tool_html =~ "constrain_tools"
    assert tool_html =~ "deny_tool"
    assert tool_html =~ "fail_closed"
    assert tool_html =~ "tool receipt context"
  end

  test "LiveView state-machine mode shows default and explicit state projections" do
    :ok = put_route_gate_config()
    {:ok, route_view, route_html} = live(build_conn(), "/policies/route-privacy/state_machine")

    assert route_html =~ "State model"
    assert route_html =~ "State machine transition graph"
    assert route_html =~ "default one-state"
    assert route_html =~ "No explicit transitions"
    assert route_html =~ "Assistant boundary"
    assert route_html =~ "explain_projection"
    assert render(route_view) =~ "request-policy.private-route-gate"

    {:ok, retry_view, retry_html} = live(build_conn(), "/policies/tts-retry/state_machine")

    assert retry_html =~ "explicit stateful"
    assert retry_html =~ "State machine transition graph"
    assert retry_html =~ "Observing"
    assert retry_html =~ "Retrying"
    assert retry_html =~ "Turn model"
    assert retry_html =~ "local/qwen-coder"
    assert retry_html =~ "managed/kimi-k2.6"
    assert render(retry_view) =~ "stream.match"

    {:ok, _stream_view, stream_html} =
      live(build_conn(), "/policies/stream-rewrite-state/state_machine")

    assert stream_html =~ "Turn model"

    assert stream_html =~
             "Same-request retry or fallback reroutes are shown as route-transition events"

    assert stream_html =~ "local/qwen-coder"
    assert stream_html =~ "managed/kimi-k2.6"

    assert stream_html =~
             "Future turns in this session should use the review-capable managed route"

    assert stream_html =~ "Receipt recording does not call a provider model."
  end

  defp put_route_gate_config do
    config =
      Wardwright.default_config()
      |> Map.put("governance", [
        %{
          "action" => "restrict_routes",
          "allowed_targets" => [Wardwright.local_model()],
          "contains" => "private-data-risk",
          "id" => "private-route-gate",
          "kind" => "route_gate",
          "message" => "private context must stay local"
        },
        %{
          "action" => "switch_model",
          "contains" => "force-managed",
          "id" => "fallback-route-gate",
          "kind" => "route_gate",
          "message" => "operator selected managed fallback",
          "target_model" => Wardwright.managed_model()
        }
      ])

    assert {:ok, _config} = Wardwright.put_config(config)
    :ok
  end

  defp put_tool_governance_config do
    config =
      Wardwright.default_config()
      |> Map.put("governance", [
        %{
          "action" => "constrain_tools",
          "id" => "github-write-tools",
          "kind" => "tool_selector",
          "name" => "create_pull_request",
          "namespace" => "mcp.github",
          "risk_class" => "write"
        },
        %{
          "action" => "deny_tool",
          "id" => "shell-write-tools",
          "kind" => "tool_denylist",
          "namespace" => "shell",
          "risk_class" => "irreversible"
        },
        %{
          "action" => "fail_closed",
          "id" => "repeat-github-tool",
          "kind" => "tool_loop_threshold",
          "name" => "create_pull_request",
          "namespace" => "mcp.github",
          "threshold" => 3
        }
      ])

    assert {:ok, _config} = Wardwright.put_config(config)
    :ok
  end

  test "LiveView workbench updates from runtime PubSub visibility events" do
    {:ok, view, html} = live(build_conn(), "/policies/route-privacy/phase_map")

    assert html =~ "Runtime Visibility"
    assert html =~ "History Cache"
    refute html =~ "route.selected"

    assert {:ok, %{"type" => "route.selected"}} =
             Wardwright.Runtime.record_session_event(
               "coding-balanced",
               "2026-05-13.mock",
               "liveview-session",
               "route.selected",
               %{"selected_model" => "mock/liveview"}
             )

    updated = render(view)

    assert updated =~ "route.selected"
    assert updated =~ "liveview-session"
    assert updated =~ "mock/liveview"
  end

  test "LiveView workbench shows bounded policy cache writes as live history" do
    Wardwright.PolicyCache.configure(%{"max_entries" => 4, "recent_limit" => 4})

    {:ok, view, html} = live(build_conn(), "/policies/route-privacy/phase_map")

    assert html =~ "History Cache"
    assert html =~ "0/4"
    refute html =~ "tool_call"

    assert {:ok, _event} =
             Wardwright.PolicyCache.add(%{
               "created_at_unix_ms" => 1,
               "key" => "shell:ls",
               "kind" => "tool_call",
               "scope" => %{"session_id" => "live-history-session"}
             })

    updated = render(view)

    assert updated =~ "1/4"
    assert updated =~ "tool_call"
    assert updated =~ "shell:ls"
    assert updated =~ "live-history-session"
  end

  test "LiveView history cache does not render raw cached text by default" do
    Wardwright.PolicyCache.configure(%{"max_entries" => 4, "recent_limit" => 4})

    {:ok, view, _html} = live(build_conn(), "/policies/route-privacy/phase_map")

    assert {:ok, _event} =
             Wardwright.PolicyCache.add(%{
               "created_at_unix_ms" => 1,
               "key" => "chat_completion",
               "kind" => "request_text",
               "value" => %{"text" => "do not show this private prompt"}
             })

    updated = render(view)

    assert updated =~ "request_text"
    assert updated =~ "chat_completion"
    assert updated =~ "global scope"
    refute updated =~ "do not show this private prompt"
  end

  defp temp_workspace_dir(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(path)
    path
  end

  defp basic_auth(username, password), do: "Basic " <> Base.encode64("#{username}:#{password}")

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp eventually_render(view, expected, attempts \\ 20)

  defp eventually_render(view, expected, attempts) when attempts > 0 do
    html = render(view)

    if html =~ expected do
      html
    else
      Process.sleep(10)
      eventually_render(view, expected, attempts - 1)
    end
  end

  defp eventually_render(view, _expected, 0), do: render(view)

  defmodule DraftingAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:ok,
       Jason.encode!(%{
         "answer" => "Drafted a cow-focused model.",
         "tool_calls" => [
           %{
             "arguments" => %{
               "description" => "Responds normally except when the user sends mooing text.",
               "model_id" => "cow-lover-mode",
               "route" => %{"id" => "dispatcher.cow", "models" => ["ollama/gemma4:e4b"], "type" => "dispatcher"},
               "stream_rules" => [
                 %{
                   "action" => "rewrite_chunk",
                   "id" => "cow-art",
                   "pattern" => "\\bmoo+\\b",
                   "phase" => "response.streaming",
                   "replacement" => "moo\n^__^\n(oo)\\\\_______"
                 }
               ],
               "targets" => [%{"context_window" => 8192, "model" => "ollama/gemma4:e4b"}],
               "version" => "draft-cow"
             },
             "name" => "draft_wardwright_model"
           }
         ]
       })}
    end
  end

  defmodule MalformedToolPlanAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:ok, ~s({"answer":"drafting","tool_calls":[{"name":"draft_wardwright_model","arguments":)}
    end
  end
end
