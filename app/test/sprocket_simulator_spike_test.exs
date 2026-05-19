defmodule Wardwright.SprocketSimulatorSpikeTest do
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

  test "Gleam-owned workbench view model preserves projection and simulation contract fields" do
    summary_rows =
      :wardwright@sprocket_workbench.summary_rows(
        "Time-travel rewrite",
        "Trace",
        "local/test",
        "community/test",
        "wardwright.policy_projection.v1",
        "wardwright.policy_simulation.v1",
        "sha256:test",
        "passed",
        3,
        0
      )

    assert {"Projection", "wardwright.policy_projection.v1", "neutral"} in summary_rows
    assert {"Simulation", "wardwright.policy_simulation.v1", "neutral"} in summary_rows
    assert {"Trace events", "3", "neutral"} in summary_rows
    assert {"Verdict", "Passed", "ok"} in summary_rows
    assert {"Coverage gaps", "0", "ok"} in summary_rows

    html =
      :wardwright@sprocket_workbench.document_html(
        "",
        summary_rows,
        [{"Caller input", "moo", "request"}, {"User receives", "cow", "response"}],
        [{"Request rewrites", "1", "warn"}, {"Released", "yes", "ok"}],
        [
          {"1", "current", "response", "stream.replace", "rewrote output", "moo -> cow", "ok"}
        ],
        [{"Time-travel rewrite", "/spikes/sprocket-workbench?pattern=tts-retry", "selected", "tts-retry"}],
        [{"Trace", "/spikes/sprocket-workbench?mode=trace_overlay", "selected", "trace_overlay"}],
        [{"local/test", "/spikes/sprocket-workbench?model=local/test", "selected", "local/test"}],
        [{"Cow path", "/spikes/sprocket-workbench?scenario=cow-path", "selected", "cow-path"}],
        "Cow rewrite scenario",
        "Request and response rewrites are visible at the simulation boundary.",
        "Step 1",
        "/spikes/sprocket-workbench?step=0",
        "/spikes/sprocket-workbench?step=1",
        "/spikes/sprocket-workbench?step=0"
      )

    assert html =~ "Sprocket + Gleam runtime spike"
    assert html =~ "wardwright.policy_projection.v1"
    assert html =~ ~s(data-option-id="tts-retry")
    assert html =~ "moo -&gt; cow"
  end

  test "spike route renders a Sprocket page from backend projection data" do
    conn = get(build_conn(), "/spikes/sprocket-workbench?mode=trace_overlay&step=1")

    assert html_response(conn, 200) =~ "Sprocket + Gleam runtime spike"
    assert html_response(conn, 200) =~ "wardwright.policy_projection.v1"
    assert html_response(conn, 200) =~ "wardwright.policy_simulation.v1"
    assert html_response(conn, 200) =~ ~s(data-option-id=)
  end

  test "spike route honors query-string policy and view selections" do
    conn = get(build_conn(), "/spikes/sprocket-workbench?pattern=stream-rewrite-state&mode=trace_overlay&step=1")
    html = html_response(conn, 200)

    assert html =~ "Regex rewrite and state transition"
    assert html =~ "<strong>Trace</strong>"
    assert html =~ ~s(class="selector selected" href="/spikes/sprocket-workbench?pattern=stream-rewrite-state)
    refute html =~ "<strong>Time-travel stream retry</strong>"
  end

  test "legacy spike route remains an alias while the new page is evaluated" do
    conn = get(build_conn(), "/spikes/sprocket-simulator")

    assert html_response(conn, 200) =~ "Policy Workbench, Re-modeled"
  end
end
