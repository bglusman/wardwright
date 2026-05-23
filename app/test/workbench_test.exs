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
    Wardwright.ReceiptStore.clear()
    Wardwright.PolicyScenarioStore.clear()
    :ok
  end

  test "admin route mounts the server component runtime" do
    conn = get(build_conn(), "/admin")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "<title>Wardwright Admin</title>"
    assert conn.resp_body =~ "/vendor/lustre/lustre-server-component.mjs"
    assert conn.resp_body =~ "/vendor/cytoscape/cytoscape.min.js"
    assert conn.resp_body =~ "/assets/wardwright_state_graph.js"
    assert conn.resp_body =~ "/admin/socket/websocket"
    assert conn.resp_body =~ "page=workbench"
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
    refute conn.resp_body =~ "Wardwright Lustre Workbench Spike"
  end

  test "root route opens the admin workbench" do
    conn = get(build_conn(), "/")

    assert html_response(conn, 200) =~ "<title>Wardwright Admin</title>"
    assert conn.resp_body =~ "/admin/socket/websocket"
    assert conn.resp_body =~ "page=workbench"
  end

  test "admin model access view mounts through the shared runtime" do
    conn = get(build_conn(), "/admin?view=model_access&model=coding-balanced")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "<title>Wardwright Admin</title>"
    assert conn.resp_body =~ "/vendor/lustre/lustre-server-component.mjs"
    assert conn.resp_body =~ "/admin/socket/websocket"
    assert conn.resp_body =~ "page=model_access"
    assert conn.resp_body =~ "model=coding-balanced"
    refute conn.resp_body =~ "Phoenix.LiveView"
  end

  test "admin control debugger view mounts through the shared runtime" do
    conn = get(build_conn(), "/admin?view=control_debugger")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "<title>Wardwright Admin</title>"
    assert conn.resp_body =~ "/admin/socket/websocket"
    assert conn.resp_body =~ "page=control_debugger"
    refute conn.resp_body =~ "Phoenix.LiveView"
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
      |> get("/admin")

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
    assert json =~ "Simulate a turn"
    assert json =~ "Model authoring"
    assert json =~ "Diagram focus"
    assert json =~ "Example models"
    assert json =~ "Scenario"
    assert json =~ "/admin"
    assert json =~ "/admin?view=model_access"
    assert json =~ "/admin?view=control_debugger"
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

  test "transport registration pushes the initial model access DOM payload" do
    assert {:ok, state} =
             WardwrightWeb.LustreWorkbenchSocket.init(%{params: %{"page" => "model_access"}})

    assert_receive {ref, message} when is_tuple(message), 1_000

    assert {:push, {:text, json}, _state} =
             WardwrightWeb.LustreWorkbenchSocket.handle_info({ref, message}, state)

    assert json =~ "Models & access"
    assert json =~ "Access Policy"
    assert json =~ "Debug recording"
    assert json =~ "Receipt store"
    assert json =~ "Create Key"
    assert json =~ "/admin?model=coding-balanced"
    assert json =~ "/admin?view=control_debugger&model=coding-balanced"
    refute json =~ "Legacy workbench (deprecated)"
    refute json =~ ~s(href="/policies")
    refute json =~ "Lustre Workbench"
    refute json =~ "Gleam UI"

    WardwrightWeb.LustreWorkbenchSocket.terminate(:normal, state)
  end

  test "transport registration pushes the initial control debugger DOM payload" do
    assert {:ok, state} =
             WardwrightWeb.LustreWorkbenchSocket.init(%{params: %{"page" => "control_debugger"}})

    assert_receive {ref, message} when is_tuple(message), 1_000

    assert {:push, {:text, json}, _state} =
             WardwrightWeb.LustreWorkbenchSocket.handle_info({ref, message}, state)

    assert json =~ "Session replay"
    assert json =~ "Create simulator case"
    assert json =~ "Save scenario"
    assert json =~ "Receipts:"
    assert json =~ "Simulator cases:"
    assert json =~ "Replay summary"
    assert json =~ "Explain receipt"
    assert json =~ "/admin"
    assert json =~ "/admin?view=model_access"
    refute json =~ "Phoenix.LiveView"

    WardwrightWeb.LustreWorkbenchSocket.terminate(:normal, state)
  end

  test "admin transport honors the selected model websocket parameter" do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "query-selected-model")

    assert {:ok, _config} = Wardwright.put_model_config(config)

    assert {:ok, state} =
             WardwrightWeb.LustreWorkbenchSocket.init(%{
               connect_info: %{session: %{}},
               params: %{"model" => "query-selected-model", "page" => "model_access"}
             })

    assert_receive {ref, message} when is_tuple(message), 1_000

    assert {:push, {:text, json}, _state} =
             WardwrightWeb.LustreWorkbenchSocket.handle_info({ref, message}, state)

    assert json =~ "query-selected-model"
    assert json =~ "/admin?model=query-selected-model"
    assert json =~ "/admin?view=model_access&model=query-selected-model"
    assert json =~ "/admin?view=control_debugger&model=query-selected-model"

    WardwrightWeb.LustreWorkbenchSocket.terminate(:normal, state)
  end

  test "admin transport preserves selected model on debugger fallback links" do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "debugger-selected-model")

    assert {:ok, _config} = Wardwright.put_model_config(config)

    assert {:ok, state} =
             WardwrightWeb.LustreWorkbenchSocket.init(%{
               connect_info: %{session: %{}},
               params: %{"model" => "debugger-selected-model", "page" => "control_debugger"}
             })

    assert_receive {ref, message} when is_tuple(message), 1_000

    assert {:push, {:text, json}, _state} =
             WardwrightWeb.LustreWorkbenchSocket.handle_info({ref, message}, state)

    assert json =~ "Session replay"
    assert json =~ "/admin?model=debugger-selected-model"
    assert json =~ "/admin?view=model_access&model=debugger-selected-model"
    assert json =~ "/admin?view=control_debugger&model=debugger-selected-model"

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
             "Ends in: recording"
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
    assert WardwrightWeb.LustreWorkbenchData.retry_response_slots("demo-composed-retry-router") ==
             3

    assert WardwrightWeb.LustreWorkbenchData.default_model_response("demo-composed-retry-router") =~
             "OldClient"
  end

  test "Lustre state graph composes across nested Wardwright model targets" do
    {_engine, _artifact, _initial, _default?, transitions} =
      WardwrightWeb.LustreWorkbenchData.projection_summary(
        "tts-retry",
        "demo-composed-retry-router"
      )

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

  test "admin shell preserves selected model in workbench fallback link" do
    put_cow_transform_model_config()

    assert :wardwright@lustre_admin_test_support.selecting_model_access_model_updates_workbench_href(
             "cow-transform-workbench"
           )

    assert :wardwright@lustre_admin_test_support.workbench_deep_link_uses_selected_model(
             "cow-transform-workbench",
             "system/wardwright_policy_reminder: Include a small ASCII cow"
           )
  end

  test "Lustre workbench submits authoring requests through the existing assistant boundary" do
    original_client = Application.get_env(:wardwright, :authoring_agent_client, :unset)
    original_enabled = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED")
    original_api_key = System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY")
    original_route = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    Application.put_env(:wardwright, :authoring_agent_client, __MODULE__.AdminAuthoringClient)
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

    assert :wardwright@lustre_workbench_test_support.submitting_authoring_request_shows_response(
             "coding-balanced",
             "Make an admin cow model.",
             "Drafted admin cow model."
           )

    assert :wardwright@lustre_workbench_test_support.submitting_authoring_request_shows_response(
             "coding-balanced",
             "Make an admin cow model.",
             "Draft admin-cow: 0 validation errors"
           )

    assert :wardwright@lustre_workbench_test_support.authoring_request_can_review_and_activate_draft(
             "coding-balanced",
             "Make an admin cow model.",
             "Draft admin-cow: 0 validation errors",
             "dispatcher.admin-cow",
             "Activated admin-cow"
           )

    assert {:ok, config} = Wardwright.model_config("admin-cow")
    assert Wardwright.model_id(config) == "admin-cow"

    assert :wardwright@lustre_workbench_test_support.edited_authoring_draft_powers_simulation_and_activation(
             "coding-balanced",
             "Make an admin cow model.",
             "please moo for me",
             "system/wardwright_policy_reminder: Include a small ASCII cow",
             "Activated edited-admin-cow"
           )

    assert {:ok, edited_config} = Wardwright.model_config("edited-admin-cow")
    assert Wardwright.model_id(edited_config) == "edited-admin-cow"

    assert :wardwright@lustre_workbench_test_support.invalid_authoring_draft_blocks_simulation(
             "coding-balanced",
             "Make an admin cow model."
           )

    assert :wardwright@lustre_workbench_test_support.authoring_refinement_prompt_is_available(
             "coding-balanced",
             "Make an admin cow model."
           )
  end

  test "Lustre authoring boundary includes the simulator turn in the assistant prompt" do
    original_client = Application.get_env(:wardwright, :authoring_agent_client, :unset)
    original_enabled = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED")
    original_api_key = System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY")

    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.SimulatorContextAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")

    on_exit(fn ->
      case original_client do
        :unset -> Application.delete_env(:wardwright, :authoring_agent_client)
        client -> Application.put_env(:wardwright, :authoring_agent_client, client)
      end

      restore_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", original_enabled)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", original_api_key)
    end)

    {status, content, "", "", "", ""} =
      WardwrightWeb.LustreWorkbenchData.ask_authoring_agent(
        "coding-balanced",
        "tts-retry",
        "please moo",
        "raw moo output",
        [{2, "retry moo output"}],
        "Explain the simulator context."
      )

    assert status == "completed"
    assert content =~ "simulator context received"
  end

  test "Lustre workbench explains authoring setup instead of showing dead controls when disabled" do
    original_enabled = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED")
    original_api_key = System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY")
    original_api_key_file = System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE")
    original_route = System.get_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    System.delete_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED")
    System.delete_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY")
    System.delete_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE")
    System.delete_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE")

    on_exit(fn ->
      restore_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", original_enabled)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", original_api_key)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE", original_api_key_file)
      restore_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", original_route)
    end)

    assert :wardwright@lustre_workbench_test_support.unconfigured_authoring_shows_setup_without_form()
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

    assert :wardwright@lustre_workbench_test_support.selecting_fixture_controls_textarea(
             "tts-retry",
             "retry-workbench",
             "safe-stream",
             "model_response",
             "Use the current client adapter.\nAvoid legacy constructor names."
           )
  end

  test "workbench model selector hides route-type framing" do
    assert :wardwright@lustre_workbench_test_support.initial_view_omits("dispatcher /")
    assert :wardwright@lustre_workbench_test_support.initial_view_omits("cascade /")
    assert :wardwright@lustre_workbench_test_support.initial_view_omits("alloy /")
  end

  test "saved fixtures are available to another model on the same projection" do
    put_retry_model_config()

    {ok?, message, fixture_id} =
      WardwrightWeb.LustreWorkbenchData.save_fixture(
        "tts-retry",
        "retry-workbench",
        "Reusable release fixture",
        "Use the current client.",
        "Use NewClient(arg) in the migration.",
        [{2, "Use NewClient(arg) in the migration."}]
      )

    assert ok?
    assert message =~ "Scenario saved"
    assert fixture_id =~ "saved:"

    assert Enum.any?(
             WardwrightWeb.LustreWorkbenchData.fixture_options("tts-retry", "coding-balanced"),
             fn {id, title, _description, user_input, model_response, _retries} ->
               id == fixture_id and title == "Saved: Reusable release fixture" and
                 user_input == "Use the current client." and
                 model_response == "Use NewClient(arg) in the migration."
             end
           )
  end

  test "control debugger imports receipts as reusable replay evidence" do
    Wardwright.ReceiptStore.insert(control_debugger_receipt_fixture("rcpt_control_import"))

    assert :wardwright@lustre_control_debugger_test_support.importing_receipt_shows_status(
             "rcpt_control_import",
             "tts-retry",
             "Imported control receipt",
             "Stored in simulator case store:"
           )

    assert [
             scenario
           ] = Wardwright.PolicyScenarioStore.list("tts-retry")

    assert scenario.title == "Imported control receipt"
    assert scenario.source == "live_replay"
    assert scenario.pinned
    assert get_in(scenario.receipt_preview, ["receipt_id"]) == "rcpt_control_import"
  end

  test "control debugger replays receipt metadata without provider calls" do
    Wardwright.ReceiptStore.insert(control_debugger_receipt_fixture("rcpt_control_replay"))

    assert :wardwright@lustre_control_debugger_test_support.replaying_receipt_shows_facts(
             "rcpt_control_replay",
             "completed",
             "managed/kimi-k2.6"
           )

    assert :wardwright@lustre_control_debugger_test_support.replaying_receipt_shows_facts(
             "rcpt_control_replay",
             "Receipt storage",
             "managed/kimi-k2.6"
           )
  end

  test "control debugger exposes counterfactual fork workflow and runtime readiness" do
    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains("What-if replay")

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains("Replay, change policy, continue")

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains(
             "deterministic replay/fork and live model continuation available"
           )

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains("append-only files")

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains("Record example session")

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains("Agent harness export")

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains(
             "can also continue the fork through a selected Wardwright model"
           )

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains("tool calls/results")

    assert :wardwright@lustre_control_debugger_test_support.initial_view_contains(
             "WARDWRIGHT_POLICY_SCENARIO_STORE_FILE"
           )
  end

  test "control debugger records the default counterfactual example from the UI" do
    assert :wardwright@lustre_control_debugger_test_support.running_counterfactual_demo_shows_outcome()
  end

  test "control debugger states the exact read-before-edit violation on the selected trace event" do
    assert :wardwright@lustre_control_debugger_test_support.read_before_edit_trace_states_exact_violation()
  end

  test "control debugger targets the matching workbench pattern for counterfactual examples" do
    assert :wardwright@lustre_control_debugger_test_support.read_before_edit_example_targets_tool_governance_pattern()

    assert :wardwright@lustre_control_debugger_test_support.output_contract_example_targets_output_pattern()
  end

  test "control debugger keeps fork actions attached to a loaded transcript event" do
    assert :wardwright@lustre_control_debugger_test_support.fork_actions_are_contextual_to_loaded_event()
  end

  test "control debugger records a non-tool output contract example from the UI" do
    assert :wardwright@lustre_control_debugger_test_support.output_contract_example_shows_non_tool_fork_point()
  end

  test "control debugger loads transcript fork points from the demo receipt" do
    assert :wardwright@lustre_control_debugger_test_support.loading_transcript_from_demo_receipt_shows_fork_points()
  end

  test "control debugger replays to the selected fork point without a provider call" do
    assert :wardwright@lustre_control_debugger_test_support.replaying_to_loaded_fork_point_shows_no_provider_call()
  end

  test "control debugger forks from the selected point and compares the outcome" do
    assert :wardwright@lustre_control_debugger_test_support.forking_from_loaded_fork_point_shows_comparison()
  end

  test "control debugger can continue a fork through a configured Wardwright model" do
    put_counterfactual_live_model_config()

    assert :wardwright@lustre_control_debugger_test_support.live_model_continuation_shows_provider_call(
             "counterfactual-live-canned"
           )
  end

  test "control debugger prepares an agent harness handoff from a loaded trace" do
    assert :wardwright@lustre_control_debugger_test_support.harness_export_requires_loaded_trace()
    assert :wardwright@lustre_control_debugger_test_support.opencode_harness_export_shows_fidelity_warning()
  end

  test "control debugger validates editable policy overlays before forking" do
    assert :wardwright@lustre_control_debugger_test_support.invalid_policy_overlay_blocks_fork()
  end

  test "control debugger rejects blank policy overlays instead of applying a default" do
    assert :wardwright@lustre_control_debugger_test_support.blank_policy_overlay_blocks_fork()
  end

  test "control debugger accepts generic editable policy overlays before forking" do
    assert :wardwright@lustre_control_debugger_test_support.generic_policy_overlay_can_fork()
  end

  test "control debugger applies a valid edited policy overlay when forking" do
    assert :wardwright@lustre_control_debugger_test_support.custom_policy_overlay_changes_applied_rule()
  end

  test "control debugger policy overlay text area is controlled" do
    assert :wardwright@lustre_control_debugger_test_support.policy_overlay_textarea_is_controlled(
             ~s({"id":"custom","requires_prior_read_for":["edit_file"]})
           )
  end

  test "control debugger receipt id text input is controlled" do
    assert :wardwright@lustre_control_debugger_test_support.receipt_text_input_is_controlled("manual_receipt_id")
  end

  test "control debugger receipt selector exposes an accessible name" do
    assert :wardwright@lustre_control_debugger_test_support.receipt_select_has_accessible_name()
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
             |> :lustre.start_server_component("")

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

  defp put_counterfactual_live_model_config do
    config =
      Wardwright.default_config()
      |> Map.put("model_id", "counterfactual-live-canned")
      |> Map.put("version", "counterfactual-live-test")
      |> Map.put("vcr", %{"mode" => "full_session"})
      |> Map.put("requires_api_key", false)
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})
      |> Map.put("targets", [
        %{
          "canned_outputs" => [
            "Read settings.json before editing; feature_enabled is true and tests passed."
          ],
          "context_window" => 8192,
          "model" => "canned/counterfactual-live",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("dispatchers", [
        %{"id" => "dispatcher.counterfactual-live", "models" => ["canned/counterfactual-live"]}
      ])
      |> Map.put("route_root", "dispatcher.counterfactual-live")

    {:ok, _config} = Wardwright.put_model_config(config)
  end

  defp control_debugger_receipt_fixture(receipt_id) do
    %{
      "created_at" => 1_800_000_456,
      "decision" => %{
        "policy_actions" => [],
        "policy_conflicts" => [],
        "reason" => "synthetic control debugger fixture",
        "route_id" => "dispatcher.managed",
        "route_type" => "dispatcher",
        "selected_model" => "managed/kimi-k2.6",
        "selected_provider" => "managed"
      },
      "final" => %{
        "status" => "completed",
        "stream_policy" => %{
          "events" => [
            %{
              "action" => "retry_with_reminder",
              "rule_id" => "tts.no-old-client",
              "type" => "stream_policy.triggered"
            },
            %{
              "retry_count" => 1,
              "rule_id" => "tts.retry-arbiter",
              "type" => "attempt.retry_requested"
            }
          ],
          "released_to_consumer" => true,
          "retry_count" => 1,
          "status" => "completed"
        }
      },
      "model_id" => "coding-balanced",
      "model_version" => "2026-05-13.mock",
      "receipt_id" => receipt_id,
      "receipt_schema" => "v1",
      "request" => %{
        "estimated_prompt_tokens" => 12,
        "message_count" => 1,
        "model" => "coding-balanced",
        "normalized_model" => "coding-balanced"
      },
      "vcr" => %{
        "decision" => %{
          "reason" => "synthetic control debugger fixture",
          "route_id" => "dispatcher.managed",
          "route_type" => "dispatcher",
          "selected_model" => "managed/kimi-k2.6",
          "selected_provider" => "managed"
        },
        "final" => %{"status" => "completed"},
        "policy" => %{"actions" => [], "conflicts" => []},
        "redaction" => "metadata_only",
        "request" => %{
          "estimated_prompt_tokens" => 12,
          "message_content_lengths" => [24],
          "message_count" => 1,
          "message_roles" => ["user"],
          "normalized_model" => "coding-balanced"
        },
        "route" => %{
          "reason" => "synthetic control debugger fixture",
          "route_id" => "dispatcher.managed",
          "route_type" => "dispatcher",
          "selected_model" => "managed/kimi-k2.6",
          "selected_provider" => "managed"
        },
        "schema" => "wardwright.policy_vcr.v0"
      }
    }
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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defmodule AdminAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:ok,
       JSON.encode!(%{
         "answer" => "Drafted admin cow model.",
         "next_steps" => ["review the draft before activation"],
         "tool_calls" => [
           %{
             "arguments" => %{
               "description" => "Adds a small cow reminder for admin authoring review.",
               "governance" => [
                 %{
                   "action" => "transform",
                   "contains" => "moo",
                   "id" => "admin-cow-reminder",
                   "kind" => "request_transform",
                   "message" => "mooing input matched",
                   "reminder" => "Include a small ASCII cow, then answer normally."
                 }
               ],
               "model_id" => "admin-cow",
               "route" => %{
                 "id" => "dispatcher.admin-cow",
                 "models" => ["local-ollama"],
                 "type" => "dispatcher"
               },
               "targets" => [%{"context_window" => 8192, "model" => "local-ollama"}]
             },
             "name" => "draft_wardwright_model"
           }
         ]
       })}
    end
  end

  defmodule SimulatorContextAuthoringClient do
    def generate_text(prompt, _opts) do
      answer =
        if prompt =~ ~s(user_input: "please moo") and
             prompt =~ ~s(raw_model_output_or_stream: "raw moo output") and
             prompt =~ ~s("model_output":"retry moo output") and
             prompt =~ "selected_recipe_id: \n" do
          "simulator context received"
        else
          "simulator context missing"
        end

      {:ok, JSON.encode!(%{"answer" => answer, "tool_calls" => []})}
    end
  end
end
