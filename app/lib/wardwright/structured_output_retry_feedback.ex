defmodule Wardwright.StructuredOutputRetryFeedback do
  @moduledoc false

  @guard_loop_key "guard_loop"
  @on_violation_key "on_violation"
  @retry_with_validation_feedback "retry_with_validation_feedback"
  @schemas_key "schemas"
  @messages_key "messages"
  @content_key "content"
  @name_key "name"
  @role_key "role"

  def add(request, attempt_index, structured_config)
      when attempt_index > 0 and is_map(request) and is_map(structured_config) do
    guard_config = Map.get(structured_config, @guard_loop_key, %{})

    if Map.get(guard_config, @on_violation_key, @retry_with_validation_feedback) ==
         @retry_with_validation_feedback do
      Map.update(request, @messages_key, [feedback_message(structured_config)], fn messages ->
        messages ++ [feedback_message(structured_config)]
      end)
    else
      request
    end
  end

  def add(request, _attempt_index, _structured_config), do: request

  defp feedback_message(structured_config) do
    %{
      @content_key => feedback_text(structured_config),
      @name_key => "wardwright_structured_output_guard",
      @role_key => "system"
    }
  end

  defp feedback_text(structured_config) do
    [
      "Previous model output failed Wardwright structured output validation.",
      "Retry now and return only valid JSON matching the configured structured_output schema.",
      "Do not include markdown fences or prose outside JSON.",
      schema_names_feedback(structured_config)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp schema_names_feedback(structured_config) do
    schema_names =
      structured_config
      |> Map.get(@schemas_key, %{})
      |> Map.keys()
      |> Enum.join(", ")

    if schema_names != "", do: "Available schemas: #{schema_names}."
  end
end
