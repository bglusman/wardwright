defmodule WardwrightWeb.WorkbenchTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

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
    Wardwright.reset_config()
    :ok
  end

  test "workbench route mounts the server component runtime" do
    conn = get(build_conn(), "/workbench")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "<title>Wardwright Workbench</title>"
    assert conn.resp_body =~ "/vendor/lustre/lustre-server-component.mjs"
    assert conn.resp_body =~ "/vendor/cytoscape/cytoscape.min.js"
    assert conn.resp_body =~ "/assets/wardwright_state_graph.js"
    assert conn.resp_body =~ "/workbench/socket/websocket"
    refute conn.resp_body =~ "Wardwright Lustre Workbench Spike"
  end

  test "root route opens the primary workbench" do
    conn = get(build_conn(), "/")

    assert html_response(conn, 200) =~ "<title>Wardwright Workbench</title>"
    assert conn.resp_body =~ "/workbench/socket/websocket"
  end

  test "old spike workbench route remains available during the transition" do
    conn = get(build_conn(), "/spikes/lustre-workbench")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "/spikes/lustre-workbench/socket/websocket"
  end

  test "graph renderer lab compares the hand-laid and browser-rendered toy graphs" do
    conn = get(build_conn(), "/spikes/graph-renderer-lab")

    assert html_response(conn, 200) =~ "Graph renderer lab"
    assert conn.resp_body =~ "Hand-laid baseline"
    assert conn.resp_body =~ "Cytoscape-style renderer"
    assert conn.resp_body =~ "/vendor/cytoscape/cytoscape.min.js"
    assert conn.resp_body =~ "Streaming retry policy"
    assert conn.resp_body =~ "Model route composition"
    assert conn.resp_body =~ "tts.no-old-client"
  end

  test "vendored Cytoscape renderer asset is served locally for the graph lab" do
    conn = get(build_conn(), "/vendor/cytoscape/cytoscape.min.js")

    assert response(conn, 200) =~ "cytoscape"
  end

  test "workbench route marks a protected browser session for websocket reuse" do
    previous = Application.get_env(:wardwright, :basic_auth_password)
    Application.put_env(:wardwright, :basic_auth_password, "workbench-password")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :basic_auth_password, previous),
        else: Application.delete_env(:wardwright, :basic_auth_password)
    end)

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", basic_auth("admin", "workbench-password"))
      |> get("/workbench")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert Plug.Conn.get_session(conn, :wardwright_protected_access) == true
  end

  test "client runtime is served for the server component" do
    conn = get(build_conn(), "/vendor/lustre/lustre-server-component.mjs")

    assert response(conn, 200) =~ "customElements.define"
  end

  test "Cytoscape state graph renderer is served for the workbench" do
    conn = get(build_conn(), "/assets/wardwright_state_graph.js")

    assert response(conn, 200) =~ "wardwright-state-graph"
    assert conn.resp_body =~ "showEdgeDetail"
    assert conn.resp_body =~ "model-group"
    assert conn.resp_body =~ "model-boundary-edge"
    assert conn.resp_body =~ "graphSpacingFactor"
    assert conn.resp_body =~ "bindGraphWheel"
    assert conn.resp_body =~ "userPanningEnabled: true"
    assert conn.resp_body =~ "boxSelectionEnabled: false"
    assert conn.resp_body =~ "WHEEL_ZOOM_INTENSITY"
  end

  test "transport registration pushes the initial workbench DOM payload" do
    assert {:ok, state} = WardwrightWeb.LustreWorkbenchSocket.init(%{})
    assert_receive {ref, message} when is_tuple(message), 1_000

    assert {:push, {:text, json}, _state} =
             WardwrightWeb.LustreWorkbenchSocket.handle_info({ref, message}, state)

    assert json =~ "Wardwright"
    assert json =~ "Selected model turn simulator"
    assert json =~ "Policy slice"
    assert json =~ "Fixture"
    refute json =~ "topbar-actions"

    for implementation_label <- [
          "Lustre 5",
          "Glizzy controls",
          "Gleam replay",
          "Lustre Workbench",
          "Gleam UI",
          "Wardwright Lustre Workbench Spike"
        ] do
      refute json =~ implementation_label
    end

    WardwrightWeb.LustreWorkbenchSocket.terminate(:normal, state)
  end

  test "workbench websocket transport requires protected access" do
    assert {:ok, _state} =
             WardwrightWeb.LustreWorkbenchSocket.connect(%{
               connect_info: %{peer_data: %{address: {127, 0, 0, 1}}, x_headers: []}
             })

    assert :error =
             WardwrightWeb.LustreWorkbenchSocket.connect(%{
               connect_info: %{peer_data: %{address: {203, 0, 113, 10}}, x_headers: []}
             })

    assert {:ok, _state} =
             WardwrightWeb.LustreWorkbenchSocket.connect(%{
               connect_info: %{
                 peer_data: %{address: {203, 0, 113, 10}},
                 session: %{"wardwright_protected_access" => true},
                 x_headers: []
               }
             })
  end

  test "workbench websocket transport accepts admin token headers" do
    previous = Application.get_env(:wardwright, :admin_token)
    Application.put_env(:wardwright, :admin_token, "lustre-token")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :admin_token, previous),
        else: Application.delete_env(:wardwright, :admin_token)
    end)

    assert {:ok, _state} =
             WardwrightWeb.LustreWorkbenchSocket.connect(%{
               connect_info: %{
                 peer_data: %{address: {203, 0, 113, 10}},
                 x_headers: [{"x-wardwright-admin-token", "lustre-token"}]
               }
             })
  end

  test "Lustre simulation updates the policy slice select" do
    assert :wardwright@lustre_workbench_test_support.selecting_policy_slice_updates_heading(
             "ambiguous-success",
             "Ambiguous success alert"
           )
  end

  test "Lustre UI derives projection state in Gleam" do
    assert :wardwright@lustre_workbench_test_support.selecting_policy_slice_updates_heading(
             "tts-retry",
             "Final: recording"
           )
  end

  test "Lustre UI renders state machine graph and active playback state" do
    put_retry_model_config()

    assert :wardwright@lustre_workbench_test_support.selecting_policy_slice_exposes_state_graph(
             "tts-retry",
             "stream.release / release_stream / tts.receipt-events"
           )

    assert :wardwright@lustre_workbench_test_support.selecting_model_policy_slice_exposes_state_graph(
             "retry-workbench",
             "tts-retry",
             "stream.match / abort_attempt / tts.no-old-client"
           )

    assert :wardwright@lustre_workbench_test_support.advancing_playback_highlights_state(
             "tts-retry",
             "guarding"
           )
  end

  test "Lustre state graph hides retry-only paths for models that cannot adopt them" do
    put_cow_transform_model_config()

    assert :wardwright@lustre_workbench_test_support.selecting_model_policy_slice_hides_state_graph_transition(
             "cow-transform-workbench",
             "tts-retry",
             "stream.match / abort_attempt / tts.no-old-client"
           )

    assert :wardwright@lustre_workbench_test_support.selecting_model_policy_slice_exposes_state_graph(
             "cow-transform-workbench",
             "tts-retry",
             "stream.release / release_stream / tts.receipt-events"
           )
  end

  test "Lustre workbench offers demo models alongside registered models" do
    ids =
      WardwrightWeb.LustreWorkbenchData.model_options()
      |> Enum.map(&elem(&1, 0))

    assert "coding-balanced" in ids
    assert "demo-retry-guard" in ids
    assert "demo-rewrite-review" in ids
    assert "demo-composed-retry-router" in ids
    assert "demo-nested-router" in ids
  end

  test "Lustre composed demo models inherit nested retry inputs" do
    assert WardwrightWeb.LustreWorkbenchData.retry_response_slots("demo-composed-retry-router") == 3
    assert WardwrightWeb.LustreWorkbenchData.default_model_response("demo-composed-retry-router") =~ "OldClient"
  end

  test "Lustre state graph composes across nested Wardwright model targets" do
    {_engine, _artifact, _initial, _default?, transitions} =
      WardwrightWeb.LustreWorkbenchData.projection_summary("tts-retry", "demo-composed-retry-router")

    assert {"observing", "route.delegate.demo-retry-guard", "demo-retry-guard::observing", "call_wardwright_model",
            "route.demo-retry-guard"} in transitions

    assert {"demo-retry-guard::observing", "stream.match", "demo-retry-guard::guarding", "abort_attempt",
            "tts.no-old-client"} in transitions

    refute {"observing", "stream.match", "guarding", "abort_attempt", "tts.no-old-client"} in transitions

    assert :wardwright@lustre_workbench_test_support.selecting_model_policy_slice_exposes_state_graph(
             "demo-composed-retry-router",
             "tts-retry",
             "route.delegate.demo-retry-guard / call_wardwright_model / route.demo-retry-guard"
           )
  end

  test "Lustre replay path follows delegated model policy events" do
    simulation =
      WardwrightWeb.LustreWorkbenchData.run_simulation(
        "tts-retry",
        "demo-composed-retry-router",
        "Migrate the old client.",
        "Use OldClient(arg) in the migration."
      )

    state_events = elem(simulation, 8)

    assert "route.delegate.demo-retry-guard" in state_events
    assert "stream.match" in state_events
  end

  test "Lustre simulation updates the selected model turn" do
    put_cow_transform_model_config()

    assert :wardwright@lustre_workbench_test_support.selecting_model_updates_simulation(
             "cow-transform-workbench",
             "system/wardwright_policy_reminder: Include a small ASCII cow"
           )
  end

  test "Lustre simulation reruns after editing and submitting the form" do
    put_cow_transform_model_config()

    assert :wardwright@lustre_workbench_test_support.editing_then_submitting_runs_simulation(
             "cow-transform-workbench",
             "please moo for me",
             "system/wardwright_policy_reminder: Include a small ASCII cow"
           )
  end

  test "selected model simulation uses the real workbench policy path" do
    put_cow_transform_model_config()

    simulation =
      WardwrightWeb.LustreWorkbenchData.run_simulation(
        "tts-retry",
        "cow-transform-workbench",
        "please moo for me",
        "ordinary answer"
      )

    assert elem(simulation, 2) =~ "system/wardwright_policy_reminder: Include a small ASCII cow"
    assert elem(simulation, 4) == true

    assert Enum.any?(elem(simulation, 7), fn {_phase, label, detail, _severity, _state_id} ->
             label == "request transform applied" and
               detail =~ "Include a small ASCII cow"
           end)

    assert elem(simulation, 9) == "cow-transform-workbench"
  end

  test "selected retry-capable model exposes retry responses in Lustre" do
    put_retry_model_config()

    assert WardwrightWeb.LustreWorkbenchData.retry_response_slots("retry-workbench") == 2

    simulation =
      WardwrightWeb.LustreWorkbenchData.run_simulation(
        "tts-retry",
        "retry-workbench",
        "Migrate the old client.",
        "Use OldClient(arg) in the migration.",
        [{2, "Still use OldClient(arg)."}, {3, "Use NewClient(arg) in the migration."}]
      )

    assert elem(simulation, 3) == "Use NewClient(arg) in the migration."

    assert :wardwright@lustre_workbench_test_support.selecting_model_exposes_retry_outputs(
             "retry-workbench",
             "Retry output 3"
           )

    assert :wardwright@lustre_workbench_test_support.editing_retry_output_updates_simulation(
             "retry-workbench",
             "Use OldClient(arg) in the migration.",
             "Use NewClient(arg) in the migration.",
             "Use NewClient(arg) in the migration."
           )
  end

  test "workbench fixture selector drives simulator inputs and retry slots" do
    put_retry_model_config()

    fixtures = WardwrightWeb.LustreWorkbenchData.fixture_options("tts-retry", "retry-workbench")

    assert Enum.any?(fixtures, fn {id, title, _description, _user_input, _model_response, retries} ->
             id == "model-default" and title == "Model default" and length(retries) == 2
           end)

    assert Enum.any?(fixtures, fn {id, title, _description, _user_input, model_response, retries} ->
             id == "safe-stream" and title =~ "safe stream" and
               model_response =~ "current client adapter" and length(retries) == 2
           end)

    assert :wardwright@lustre_workbench_test_support.selecting_fixture_updates_simulation(
             "tts-retry",
             "retry-workbench",
             "safe-stream",
             "Use the current client adapter."
           )
  end

  test "Lustre state graph keeps possible paths while replay follows edited model output" do
    put_retry_model_config()

    assert :wardwright@lustre_workbench_test_support.editing_response_advances_path_to(
             "tts-retry",
             "retry-workbench",
             "Use NewClient(arg) in the migration.",
             "recording"
           )

    assert :wardwright@lustre_workbench_test_support.editing_response_advances_path_to(
             "tts-retry",
             "retry-workbench",
             "Use OldClient(arg) in the migration.",
             "guarding"
           )

    assert :wardwright@lustre_workbench_test_support.editing_response_keeps_possible_transition(
             "tts-retry",
             "retry-workbench",
             "Use NewClient(arg) in the migration.",
             "stream.match / abort_attempt / tts.no-old-client"
           )
  end

  test "Gleam component starts as a real Lustre server component" do
    assert {:ok, component} =
             :wardwright@lustre_workbench.component()
             |> :lustre.start_server_component(nil)

    :lustre.send(component, :lustre.shutdown())
  end

  defp put_cow_transform_model_config do
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

    {:ok, _config} = Wardwright.put_model_config(config)
  end

  defp put_retry_model_config do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "retry-workbench")
      |> Map.put("version", "retry-workbench-test")
      |> Map.put("stream_rules", [
        %{
          "action" => "retry_with_reminder",
          "id" => "retry-old-client",
          "max_retries" => 2,
          "regex" => "OldClient\\(",
          "reminder" => "Use NewClient instead of OldClient."
        }
      ])
      |> Map.put("targets", [%{"context_window" => 8192, "model" => "ollama/gemma4:e4b"}])
      |> Map.put("dispatchers", [%{"id" => "dispatcher.retry", "models" => ["ollama/gemma4:e4b"]}])
      |> Map.put("route_root", "dispatcher.retry")

    {:ok, _config} = Wardwright.put_model_config(config)
  end

  defp basic_auth(username, password), do: "Basic " <> Base.encode64("#{username}:#{password}")
end
