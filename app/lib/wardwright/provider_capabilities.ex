defmodule Wardwright.ProviderCapabilities do
  @moduledoc """
  Versioned provider capability records exposed at the provider API boundary.

  These records are descriptive for now. Runtime enforcement should eventually
  reject policy-relevant options that a selected adapter cannot honor.
  """

  defstruct [
    :auth_scheme,
    :cancellation_confidence,
    :cancellation_mechanism,
    :endpoint_shape,
    :stream_format,
    terminal_metadata: [],
    unsupported_options_policy: "not_applicable",
    unsupported_request_fields: [],
    unsupported_stream_delta_fields: []
  ]

  @schema "wardwright.provider_capabilities.v1"
  @schema_key "schema"
  @endpoint_shape_key "endpoint_shape"
  @stream_format_key "stream_format"
  @auth_scheme_key "auth_scheme"
  @terminal_metadata_key "terminal_metadata"
  @cancellation_key "cancellation"
  @mechanism_key "mechanism"
  @confidence_key "confidence"
  @unsupported_request_fields_key "unsupported_request_fields"
  @unsupported_stream_delta_fields_key "unsupported_stream_delta_fields"
  @unsupported_options_policy_key "unsupported_options_policy"
  @messages_key "messages"
  @role_key "role"
  @tool_calls_key "tool_calls"
  @tool_call_id_key "tool_call_id"
  @tool_choice_key "tool_choice"
  @tools_key "tools"
  @role_value_tool "tool"
  @ollama_unsupported_request_fields [@tool_choice_key]

  def for_provider("ollama", _credential_source) do
    %__MODULE__{
      auth_scheme: "none",
      cancellation_confidence: "needs_live_provider_smoke",
      cancellation_mechanism: "task_cancel_httpc_request",
      endpoint_shape: "ollama_chat_api",
      stream_format: "ollama_ndjson",
      terminal_metadata: ["done", "done_reason", "total_duration", "load_duration", "prompt_eval_count", "eval_count"],
      unsupported_options_policy: "ignore_safe_options_fail_later_for_policy_relevant_options",
      unsupported_request_fields: @ollama_unsupported_request_fields
    }
    |> to_map()
  end

  def for_provider("openai-compatible", credential_source) do
    %__MODULE__{
      auth_scheme: bearer_auth_scheme(credential_source),
      cancellation_confidence: "needs_live_provider_smoke",
      cancellation_mechanism: "task_cancel_httpc_request",
      endpoint_shape: "openai_chat_completions",
      stream_format: "openai_sse",
      terminal_metadata: ["finish_reason", "choice_index", "usage", "system_fingerprint", "refusal", "done"],
      unsupported_options_policy: "ignore_safe_options_fail_later_for_policy_relevant_options",
      unsupported_stream_delta_fields: [@role_key, @tool_calls_key, "logprobs"]
    }
    |> to_map()
  end

  def for_provider(_kind, _credential_source) do
    %__MODULE__{
      auth_scheme: "none",
      cancellation_confidence: "deterministic_local",
      cancellation_mechanism: "local_task",
      endpoint_shape: "wardwright_mock",
      stream_format: "wardwright_chunks"
    }
    |> to_map()
  end

  def to_map(%__MODULE__{} = capabilities) do
    %{
      @auth_scheme_key => capabilities.auth_scheme,
      @cancellation_key => %{
        @confidence_key => capabilities.cancellation_confidence,
        @mechanism_key => capabilities.cancellation_mechanism
      },
      @endpoint_shape_key => capabilities.endpoint_shape,
      @schema_key => @schema,
      @stream_format_key => capabilities.stream_format,
      @terminal_metadata_key => capabilities.terminal_metadata,
      @unsupported_options_policy_key => capabilities.unsupported_options_policy,
      @unsupported_request_fields_key => capabilities.unsupported_request_fields,
      @unsupported_stream_delta_fields_key => capabilities.unsupported_stream_delta_fields
    }
  end

  def validate_request(kind, request) when is_binary(kind) and is_map(request) do
    unsupported =
      kind
      |> for_provider("none")
      |> Map.get(@unsupported_request_fields_key, [])
      |> Enum.filter(&request_field_present?(&1, request))

    case unsupported do
      [] ->
        :ok

      fields ->
        {:error,
         "provider adapter #{inspect(kind)} does not support request fields: " <>
           Enum.join(fields, ", ")}
    end
  end

  def validate_request(_kind, _request), do: :ok

  defp bearer_auth_scheme("none"), do: "none"
  defp bearer_auth_scheme(_credential_source), do: "bearer"

  defp request_field_present?("tools", request), do: present?(Map.get(request, @tools_key))

  defp request_field_present?("tool_choice", request), do: present?(Map.get(request, @tool_choice_key))

  defp request_field_present?("message.tool_calls", request) do
    request |> messages() |> Enum.any?(&present?(Map.get(&1, @tool_calls_key)))
  end

  defp request_field_present?("message.tool_call_id", request) do
    request |> messages() |> Enum.any?(&present?(Map.get(&1, @tool_call_id_key)))
  end

  defp request_field_present?("message.role:tool", request) do
    request |> messages() |> Enum.any?(&(Map.get(&1, @role_key) == @role_value_tool))
  end

  defp request_field_present?(_field, _request), do: false

  defp messages(%{@messages_key => messages}) when is_list(messages), do: Enum.filter(messages, &is_map/1)

  defp messages(_request), do: []

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(%{}), do: false
  defp present?(_value), do: true
end
