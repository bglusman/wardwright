defmodule WardwrightWeb.SprocketWorkbenchPage do
  @moduledoc false

  @modes [
    {"diagram", "Flow"},
    {"phase_map", "Phases"},
    {"state_machine", "States"},
    {"effect_matrix", "Effects"},
    {"trace_overlay", "Trace"}
  ]

  def render(params \\ %{}) do
    ensure_sprocket_code_paths!()
    state = state(params)

    :wardwright@sprocket_workbench.document_html(
      styles(),
      state.summary_rows,
      state.boundary_rows,
      state.capability_rows,
      state.trace_rows,
      state.pattern_options,
      state.mode_options,
      state.model_options,
      state.scenario_options,
      state.simulation_title,
      state.expected_behavior,
      "Step #{state.selected_step + 1}",
      state.prev_step_url,
      state.next_step_url,
      state.reset_step_url
    )
  end

  defp ensure_sprocket_code_paths! do
    ["gleam_erlang", "gleam_json", "gleam_otp", "gleam_regexp", "gleam_stdlib", "sprocket"]
    |> Enum.each(fn package ->
      [File.cwd!(), "build", "dev", "erlang", package, "ebin"]
      |> Path.join()
      |> Code.prepend_path()
    end)
  end

  defp state(params) do
    pattern_id = selected_pattern_id(params["pattern"])
    mode = selected_mode(params["mode"])
    selected_model_config = selected_model_config(params["model"])
    selected_model_id = Wardwright.model_id(selected_model_config)
    selected_recipe_id = params["recipe"] || ""
    projection = Wardwright.PolicyProjection.projection(pattern_id, selected_model_config)
    simulations = Wardwright.PolicyProjection.simulations(pattern_id, selected_model_config)
    simulation_inputs = Wardwright.PolicyProjection.simulation_inputs(pattern_id)
    selected_input = selected_input(simulation_inputs, params["scenario"])

    selected_simulation =
      simulation_from_input(pattern_id, simulations, selected_input, selected_model_config)

    trace = selected_simulation["trace"] || []
    selected_step = selected_step(params["step"], length(trace))
    receipt = selected_simulation["receipt_preview"] || %{}
    input = receipt["input"] || %{}
    stream = receipt["stream"] || %{}
    pattern = Wardwright.PolicyProjection.pattern(pattern_id)

    summary_rows =
      :wardwright@sprocket_workbench.summary_rows(
        pattern["title"] || pattern_id,
        mode_label(mode),
        selected_model_id,
        selected_recipe_id,
        projection["projection_schema"] || "",
        selected_simulation["simulation_schema"] || "",
        selected_simulation["artifact_hash"] || "",
        selected_simulation["verdict"] || "",
        length(trace),
        coverage_gap_count(trace)
      )

    boundary_rows =
      :wardwright@sprocket_workbench.boundary_rows(
        input["user_input"] || selected_input["user_input"] || "",
        input["model_received_input"] || input["user_input"] || selected_input["user_input"] || "",
        input["model_response"] || selected_input["model_response"] || "",
        stream["final_output"] || input["model_response"] || selected_input["model_response"] || ""
      )

    capability_rows =
      :wardwright@sprocket_workbench.capability_rows(
        length(input["request_rewrites"] || []),
        length(stream["rewrites"] || []),
        Map.get(stream, "released_to_consumer", true),
        Map.get(stream, "trigger_count", 0),
        length(simulation_inputs),
        length(Wardwright.model_summaries())
      )

    %{
      boundary_rows: boundary_rows,
      capability_rows: capability_rows,
      expected_behavior: selected_simulation["expected_behavior"] || "",
      mode_options: option_rows(mode_options(pattern_id, mode, selected_model_id, selected_input["id"]), mode),
      model_options: option_rows(model_options(pattern_id, mode, selected_input["id"]), selected_model_id),
      next_step_url:
        step_url(
          pattern_id,
          mode,
          selected_model_id,
          selected_input["id"],
          min(selected_step + 1, max(length(trace) - 1, 0))
        ),
      pattern_options: option_rows(pattern_options(mode, selected_model_id, selected_input["id"]), pattern_id),
      prev_step_url: step_url(pattern_id, mode, selected_model_id, selected_input["id"], max(selected_step - 1, 0)),
      reset_step_url: step_url(pattern_id, mode, selected_model_id, selected_input["id"], 0),
      scenario_options:
        option_rows(
          scenario_options(pattern_id, mode, selected_model_id, simulation_inputs),
          selected_input["id"] || ""
        ),
      selected_step: selected_step,
      simulation_title: selected_simulation["title"] || selected_input["title"] || "Simulation",
      summary_rows: summary_rows,
      trace_rows: trace_rows(trace, selected_step)
    }
  end

  defp simulation_from_input(pattern_id, simulations, %{"id" => input_id} = input, selected_model_config) do
    model_input = input["user_input"] || ""
    model_response = input["model_response"] || ""

    cond do
      input_id in [nil, ""] ->
        List.first(simulations) || %{}

      input["relationship"] == "saved_scenario" ->
        Wardwright.PolicyProjection.simulate_recipe_turn_with_attempts(
          pattern_id,
          input_id,
          model_input,
          model_response,
          input["history_context"] || %{},
          [],
          selected_model_config
        )

      true ->
        Wardwright.PolicyProjection.simulate_recipe_turn_with_attempts(
          pattern_id,
          input_id,
          model_input,
          model_response,
          input["history_context"] || %{},
          input["response_attempts"] || [],
          selected_model_config
        )
    end
  end

  defp simulation_from_input(_pattern_id, simulations, _input, _selected_model_config),
    do: List.first(simulations) || %{}

  defp option_rows(options, selected_id) do
    :wardwright@sprocket_workbench.option_rows(options, selected_id || "")
  end

  defp pattern_options(mode, selected_model_id, scenario_id) do
    Enum.map(Wardwright.PolicyProjection.patterns(), fn pattern ->
      id = pattern["id"]
      {id, pattern["title"] || id, path(id, mode, selected_model_id, scenario_id, 0)}
    end)
  end

  defp mode_options(pattern_id, _mode, selected_model_id, scenario_id) do
    Enum.map(@modes, fn {id, label} ->
      {id, label, path(pattern_id, id, selected_model_id, scenario_id, 0)}
    end)
  end

  defp model_options(pattern_id, mode, scenario_id) do
    Wardwright.model_summaries()
    |> Enum.map(fn model ->
      id = model["model_id"]
      label = "#{id} · #{model["route_type"] || "route"}"
      {id, label, path(pattern_id, mode, id, scenario_id, 0)}
    end)
  end

  defp scenario_options(pattern_id, mode, selected_model_id, simulation_inputs) do
    Enum.map(simulation_inputs, fn input ->
      id = input["id"] || ""
      label = input["title"] || id
      {id, label, path(pattern_id, mode, selected_model_id, id, 0)}
    end)
  end

  defp trace_rows(trace, selected_step) do
    trace
    |> Enum.map(fn event ->
      {
        event["phase"] || "",
        event["type"] || "",
        event["label"] || event["event"] || "",
        detail_text(event["detail"]),
        event["status"] || ""
      }
    end)
    |> :wardwright@sprocket_workbench.trace_rows(selected_step)
  end

  defp selected_input([], _scenario_id), do: %{"id" => "", "title" => "Default"}

  defp selected_input(inputs, scenario_id) when scenario_id in [nil, ""] do
    List.first(inputs)
  end

  defp selected_input(inputs, scenario_id) do
    Enum.find(inputs, &(Map.get(&1, "id") == scenario_id)) || List.first(inputs)
  end

  defp selected_model_config(model_id) when model_id in [nil, ""], do: Wardwright.current_config()

  defp selected_model_config(model_id) do
    case Wardwright.model_config(model_id) do
      {:ok, config} -> config
      {:error, _message} -> Wardwright.current_config()
    end
  end

  defp selected_pattern_id(pattern_id) do
    if pattern_id in Wardwright.PolicyProjection.pattern_ids() do
      pattern_id
    else
      Wardwright.PolicyProjection.pattern_ids() |> List.first()
    end
  end

  defp selected_mode(mode) do
    if mode in Enum.map(@modes, &elem(&1, 0)), do: mode, else: "diagram"
  end

  defp selected_step(nil, _trace_count), do: 0

  defp selected_step(raw, trace_count) do
    case Integer.parse(to_string(raw)) do
      {step, ""} -> step |> max(0) |> min(max(trace_count - 1, 0))
      _ -> 0
    end
  end

  defp coverage_gap_count(trace) do
    Enum.count(trace, fn event ->
      event["type"] == "simulation.coverage_gap" or event["status"] == "coverage_gap"
    end)
  end

  defp detail_text(nil), do: ""
  defp detail_text(detail) when is_binary(detail), do: detail
  defp detail_text(detail), do: Jason.encode!(detail)

  defp mode_label(mode), do: @modes |> Enum.find_value(mode, fn {id, label} -> if id == mode, do: label end)

  defp step_url(pattern_id, mode, selected_model_id, scenario_id, step) do
    path(pattern_id, mode, selected_model_id, scenario_id, step)
  end

  defp path(pattern_id, mode, selected_model_id, scenario_id, step) do
    query =
      [
        {"pattern", pattern_id},
        {"mode", mode},
        {"model", selected_model_id},
        {"scenario", scenario_id},
        {"step", Integer.to_string(step)}
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> URI.encode_query()

    "/spikes/sprocket-workbench?#{query}"
  end

  defp styles do
    """
    * { box-sizing: border-box; }
    body { margin: 0; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #182026; background: #eef1ee; }
    a { color: inherit; text-decoration: none; }
    .page { min-height: 100vh; }
    .masthead { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, 420px); gap: 28px; padding: 32px clamp(18px, 4vw, 56px) 20px; color: #f5f7f7; background: #1f2a2e; }
    .eyebrow { margin: 0 0 8px; color: #8fd4bd; font-size: 12px; font-weight: 760; letter-spacing: .08em; text-transform: uppercase; }
    h1, h2, h3, p { margin-top: 0; }
    h1 { margin-bottom: 10px; font-size: clamp(34px, 5vw, 62px); line-height: 1; letter-spacing: 0; }
    h2 { margin-bottom: 10px; font-size: 20px; letter-spacing: 0; }
    h3 { margin-bottom: 10px; font-size: 14px; letter-spacing: 0; }
    .lede { max-width: 780px; margin-bottom: 0; color: #d6ddde; font-size: 17px; line-height: 1.55; }
    .runtime-note { align-self: end; padding: 16px; border: 1px solid #506167; background: #2b3a3f; }
    .runtime-note strong { display: block; margin-bottom: 8px; color: #f7d08a; }
    .runtime-note span { color: #d6ddde; line-height: 1.45; }
    .workspace { display: grid; grid-template-columns: 280px minmax(0, 1fr); gap: 0; }
    .rail { position: sticky; top: 0; height: 100vh; overflow: auto; padding: 22px 16px; background: #ffffff; border-right: 1px solid #d6ddd9; }
    .selector-group { margin-bottom: 24px; }
    .selector-group h2 { margin-bottom: 8px; color: #526066; font-size: 12px; text-transform: uppercase; }
    .selector { display: block; width: 100%; padding: 9px 10px; border-left: 3px solid transparent; color: #253238; font-size: 13px; line-height: 1.3; }
    .selector:hover { background: #eef5f1; }
    .selector.selected { border-color: #238f6a; background: #dff2eb; font-weight: 700; }
    .canvas { min-width: 0; padding: 22px clamp(16px, 3vw, 42px) 60px; }
    .summary-grid { display: grid; grid-template-columns: repeat(5, minmax(120px, 1fr)); gap: 10px; margin-bottom: 16px; }
    .summary, .stage, .trace-panel { border: 1px solid #d7dedb; background: #fff; }
    .summary { min-height: 86px; padding: 12px; }
    .summary p { margin-bottom: 7px; color: #657177; font-size: 12px; }
    .summary strong { display: block; overflow-wrap: anywhere; color: #1f2a2e; font-size: 15px; line-height: 1.25; }
    .summary.ok strong, .capability-list .ok dd { color: #147756; }
    .summary.warn strong, .capability-list .warn dd { color: #a86600; }
    .summary.danger strong, .capability-list .danger dd { color: #a53a2a; }
    .stage { display: grid; grid-template-columns: minmax(0, 1fr) 260px; gap: 0; margin-bottom: 16px; }
    .stage-main, .stage-side, .trace-panel { padding: 20px; }
    .stage-side { border-left: 1px solid #d7dedb; background: #f8faf8; }
    .section-heading p:last-child { margin-bottom: 0; color: #526066; line-height: 1.45; }
    .section-heading.row { display: flex; align-items: start; justify-content: space-between; gap: 16px; }
    .boundary-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin-top: 18px; }
    .boundary { min-width: 0; padding: 14px; border: 1px solid #d7dedb; background: #fbfcfb; }
    .boundary.request { border-top: 3px solid #2c8ab8; }
    .boundary.response { border-top: 3px solid #238f6a; }
    pre { min-height: 92px; max-height: 230px; margin: 0; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .capability-list { display: grid; gap: 10px; margin: 0; }
    .capability-list div { display: flex; justify-content: space-between; gap: 12px; padding-bottom: 10px; border-bottom: 1px solid #d7dedb; }
    .capability-list dt { color: #657177; }
    .capability-list dd { margin: 0; font-weight: 760; }
    .step-controls { display: flex; gap: 8px; flex-wrap: wrap; }
    .step-controls a { padding: 8px 10px; border: 1px solid #bec9c5; background: #fff; font-size: 13px; }
    .trace-list { display: grid; gap: 8px; margin: 18px 0 0; padding: 0; list-style: none; }
    .trace-row { display: grid; grid-template-columns: 42px minmax(0, 1fr); gap: 12px; padding: 12px; border: 1px solid #d7dedb; background: #fbfcfb; opacity: .58; }
    .trace-row.past, .trace-row.current { opacity: 1; }
    .trace-row.current { border-color: #238f6a; background: #edf8f4; }
    .trace-row.warn.current { border-color: #d9911e; background: #fff7e9; }
    .trace-row.danger.current { border-color: #b84d3c; background: #fff0ed; }
    .trace-index { display: inline-flex; align-items: center; justify-content: center; width: 32px; height: 32px; color: #fff; background: #526066; font-weight: 800; }
    .trace-row.current .trace-index { background: #238f6a; }
    .trace-row p { margin: 0 0 4px; }
    .trace-row span { color: #657177; font-size: 12px; }
    .trace-row small { color: #38464c; line-height: 1.45; }
    @media (max-width: 980px) {
      .masthead, .workspace, .stage { grid-template-columns: 1fr; }
      .rail { position: static; height: auto; border-right: 0; border-bottom: 1px solid #d6ddd9; }
      .summary-grid, .boundary-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .stage-side { border-left: 0; border-top: 1px solid #d7dedb; }
    }
    @media (max-width: 560px) {
      .masthead { padding: 24px 16px 18px; }
      .canvas { padding: 16px 12px 44px; }
      .summary-grid, .boundary-grid { grid-template-columns: 1fr; }
      .section-heading.row { display: block; }
      .step-controls { margin-top: 12px; }
    }
    """
  end
end
