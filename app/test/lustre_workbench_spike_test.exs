defmodule WardwrightWeb.LustreWorkbenchSpikeTest do
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

  test "spike route mounts the Lustre server component runtime" do
    conn = get(build_conn(), "/spikes/lustre-workbench")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert conn.resp_body =~ "/vendor/lustre/lustre-server-component.mjs"
    assert conn.resp_body =~ "/spikes/lustre-workbench/socket/websocket"
  end

  test "spike route marks a protected browser session for websocket reuse" do
    previous = Application.get_env(:wardwright, :basic_auth_password)
    Application.put_env(:wardwright, :basic_auth_password, "lustre-password")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wardwright, :basic_auth_password, previous),
        else: Application.delete_env(:wardwright, :basic_auth_password)
    end)

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", basic_auth("admin", "lustre-password"))
      |> get("/spikes/lustre-workbench")

    assert html_response(conn, 200) =~ "lustre-server-component"
    assert Plug.Conn.get_session(conn, :wardwright_protected_access) == true
  end

  test "Lustre client runtime is served for the server component" do
    conn = get(build_conn(), "/vendor/lustre/lustre-server-component.mjs")

    assert response(conn, 200) =~ "customElements.define"
  end

  test "transport registration pushes the initial Lustre DOM payload" do
    assert {:ok, state} = WardwrightWeb.LustreWorkbenchSocket.init(%{})
    assert_receive {ref, message} when is_tuple(message), 1_000

    assert {:push, {:text, json}, _state} =
             WardwrightWeb.LustreWorkbenchSocket.handle_info({ref, message}, state)

    assert json =~ "Wardwright"
    assert json =~ "Selected model turn simulator"

    WardwrightWeb.LustreWorkbenchSocket.terminate(:normal, state)
  end

  test "Lustre websocket transport requires protected access" do
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

  test "Lustre websocket transport accepts admin token headers" do
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
    assert :wardwright@lustre_workbench_test_support.selecting_policy_slice_exposes_state_graph(
             "tts-retry",
             "stream.match / abort_attempt / tts.no-old-client"
           )

    assert :wardwright@lustre_workbench_test_support.advancing_playback_highlights_state(
             "tts-retry",
             "guarding"
           )
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

    assert Enum.any?(elem(simulation, 7), fn {_phase, label, detail, _severity} ->
             label == "request transform applied" and
               detail =~ "Include a small ASCII cow"
           end)

    assert elem(simulation, 8) == "cow-transform-workbench"
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

  defp basic_auth(username, password), do: "Basic " <> Base.encode64("#{username}:#{password}")
end
