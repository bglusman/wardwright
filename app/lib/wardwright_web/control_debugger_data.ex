defmodule WardwrightWeb.ControlDebuggerData do
  @moduledoc false

  def pattern_options do
    Wardwright.PolicyProjection.patterns()
    |> Enum.map(fn pattern ->
      {
        pattern["id"] || "",
        pattern["title"] || pattern["id"] || "",
        pattern["category"] || "",
        pattern["promise"] || ""
      }
    end)
  end

  def default_pattern_id do
    pattern_options()
    |> List.first()
    |> case do
      nil -> "tts-retry"
      {pattern_id, _title, _category, _promise} -> pattern_id
    end
  end

  def receipt_options do
    %{}
    |> Wardwright.ReceiptStore.list(25)
    |> Enum.map(fn receipt ->
      receipt_id = receipt["receipt_id"] || ""
      status = receipt["status"] || "unknown"
      model_id = receipt["model_id"] || "unknown model"

      {
        receipt_id,
        "#{receipt_id} - #{status}",
        model_id,
        status
      }
    end)
  end

  def default_receipt_id do
    receipt_options()
    |> List.first()
    |> case do
      nil -> ""
      {receipt_id, _label, _model_id, _status} -> receipt_id
    end
  end

  def import_receipt_scenario(pattern_id, receipt_id, title) do
    pattern_id = blank_fallback(pattern_id, default_pattern_id())
    receipt_id = receipt_id |> to_string() |> String.trim()
    title = title |> to_string() |> String.trim()

    if receipt_id == "" do
      {false, "Choose a receipt to import.", ""}
    else
      case Wardwright.ReceiptStore.get(receipt_id) do
        nil ->
          {false, "Could not find receipt #{receipt_id}.", ""}

        receipt ->
          attrs =
            %{"pinned" => true, "title" => title}
            |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
            |> Map.new()

          case Wardwright.PolicyScenarioStore.create_from_receipt(pattern_id, receipt, attrs) do
            {:ok, scenario} ->
              {true, "Imported #{scenario.title} as replay evidence.", "saved:#{scenario.id}"}

            {:error, message} ->
              {false, "Could not import receipt: #{message}", ""}
          end
      end
    end
  end

  def replay_receipt(receipt_id) do
    receipt_id = receipt_id |> to_string() |> String.trim()

    if receipt_id == "" do
      {false, "Choose a receipt to replay.", "", "", ""}
    else
      case Wardwright.PolicyReplay.replay_receipt_id(receipt_id) do
        {:ok, replay} ->
          {
            true,
            "Replayed #{receipt_id} without calling a provider.",
            replay["schema"] || "",
            get_in(replay, ["final", "original_status"]) || "",
            get_in(replay, ["decision", "selected_model"]) || get_in(replay, ["route", "selected_model"]) || ""
          }

        {:error, :receipt_not_found} ->
          {false, "Could not find receipt #{receipt_id}.", "", "", ""}

        {:error, message} ->
          {false, "Could not replay receipt: #{message}", "", "", ""}
      end
    end
  end

  defp blank_fallback(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      value -> value
    end
  end

  defp blank_fallback(_value, fallback), do: fallback
end
