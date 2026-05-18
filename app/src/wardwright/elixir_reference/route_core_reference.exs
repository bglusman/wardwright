defmodule Wardwright.ElixirReference.RouteCore do
  @moduledoc """
  Executable Elixir reference for `app/src/wardwright/route_core.gleam`.

  Data is represented as maps and tuples rather than Gleam custom types so
  Elixir readers can follow behavior without learning the generated BEAM shape.
  """

  def normalize_alloy_strategy(strategy)
      when strategy in ["deterministic_all", "weighted", "round_robin"],
      do: strategy

  def normalize_alloy_strategy("all"), do: "deterministic_all"
  def normalize_alloy_strategy(_strategy), do: "weighted"

  def dispatcher_reason(0), do: "estimated prompt fits selected context window"

  def dispatcher_reason(_skipped_count),
    do: "estimated prompt exceeded smaller configured context windows"

  def cascade_reason(0), do: "selected first configured cascade target"

  def cascade_reason(_skipped_count),
    do: "cascade skipped targets whose context windows were too small"

  def alloy_reason(true, 0),
    do: "partial alloy selected all constituents whose context windows fit"

  def alloy_reason(true, _skipped_count),
    do: "partial alloy dropped smaller constituents whose context windows were too small"

  def alloy_reason(false, 0),
    do: "alloy constituents share a compatible context window for this prompt"

  def alloy_reason(false, _skipped_count),
    do: "alloy prompt exceeded the compatible minimum context window"

  def forced_model_reason(false, _fits_prompt),
    do: "policy forced model was not in the allowed route set"

  def forced_model_reason(true, false),
    do: "policy forced model was too small for estimated prompt"

  def forced_model_reason(true, true), do: "policy forced selected model"

  def forced_fallback_reason(forced_reason),
    do: forced_reason <> "; explicit policy fallback allowed"

  def default_root(configured_root, first_dispatcher, first_cascade, first_alloy) do
    cond do
      configured_root != "" -> configured_root
      first_dispatcher != "" -> first_dispatcher
      first_cascade != "" -> first_cascade
      first_alloy != "" -> first_alloy
      true -> "__targets_dispatcher__"
    end
  end

  def validate_strategy(raw), do: raw in ["weighted", "round_robin", "deterministic_all", "all"]

  def select_dispatcher(models, all_targets, estimated_prompt_tokens) do
    {eligible, skipped} = split_by_context(models, estimated_prompt_tokens)
    selected = first_or_largest(eligible, all_targets)
    route_selection(selected, eligible, skipped, dispatcher_reason(length(skipped)))
  end

  def select_cascade(models, all_targets, estimated_prompt_tokens) do
    {eligible, skipped} = split_by_context(models, estimated_prompt_tokens)
    selected = first_or_largest(eligible, all_targets)
    route_selection(selected, eligible, skipped, cascade_reason(length(skipped)))
  end

  def select_forced_model(forced, policy_skipped_targets, estimated_prompt_tokens) do
    policy_skips =
      Enum.map(policy_skipped_targets, &{:policy_route_gate, &1.model, &1.context_window})

    case forced do
      [] ->
        %{
          selected_model: "unconfigured/no-target",
          selected_context_window: 0,
          selected_models: [],
          skipped: policy_skips,
          route_blocked: true,
          reason: forced_model_reason(false, false)
        }

      [target | _rest] when target.context_window < estimated_prompt_tokens ->
        %{
          selected_model: "unconfigured/no-target",
          selected_context_window: 0,
          selected_models: [],
          skipped: [
            {:context_too_small, target.model, target.context_window, estimated_prompt_tokens}
            | policy_skips
          ],
          route_blocked: true,
          reason: forced_model_reason(true, false)
        }

      [target | _rest] ->
        %{
          selected_model: target.model,
          selected_context_window: target.context_window,
          selected_models: [target.model],
          skipped: policy_skips,
          route_blocked: false,
          reason: forced_model_reason(true, true)
        }
    end
  end

  def target(model, context_window, weight \\ 1),
    do: %{model: model, context_window: context_window, weight: weight}

  defp route_selection(selected, eligible, skipped, reason) do
    selected_models =
      case {selected, eligible} do
        {{:ok, target}, []} -> [target.model]
        {_selected, eligible} -> Enum.map(eligible, & &1.model)
      end

    %{
      selected_model: selected_model(selected),
      selected_context_window: selected_context_window(selected),
      selected_models: selected_models,
      fallback_models: Enum.drop(selected_models, 1),
      skipped: skipped,
      route_blocked: match?(:error, selected),
      reason: reason
    }
  end

  defp split_by_context(models, estimated_prompt_tokens) do
    Enum.reduce(models, {[], []}, fn model, {eligible, skipped} ->
      if model.context_window >= estimated_prompt_tokens do
        {[model | eligible], skipped}
      else
        {
          eligible,
          [
            {:context_too_small, model.model, model.context_window, estimated_prompt_tokens}
            | skipped
          ]
        }
      end
    end)
    |> then(fn {eligible, skipped} -> {Enum.reverse(eligible), Enum.reverse(skipped)} end)
  end

  defp first_or_largest([target | _rest], _all_targets), do: {:ok, target}
  defp first_or_largest([], []), do: :error
  defp first_or_largest([], all_targets), do: {:ok, List.last(all_targets)}

  defp selected_model({:ok, target}), do: target.model
  defp selected_model(:error), do: "unconfigured/no-target"

  defp selected_context_window({:ok, target}), do: target.context_window
  defp selected_context_window(:error), do: 0
end
