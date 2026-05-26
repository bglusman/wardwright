defmodule Wardwright.JidoAdapterSmokeTest do
  use Wardwright.RouterCase

  import Wardwright.FrameworkAdapterSmokeCase,
    only: [assert_framework_receipt_ready!: 1, assert_receipt_caller!: 2]

  @env_keys [
    "WARDWRIGHT_AUTHORING_AGENT_ENABLED",
    "WARDWRIGHT_AUTHORING_AGENT_BASE_URL",
    "WARDWRIGHT_AUTHORING_AGENT_MODEL",
    "WARDWRIGHT_AUTHORING_AGENT_ROUTE",
    "WARDWRIGHT_BIND",
    "WARDWRIGHT_AUTHORING_AGENT_API_KEY",
    "WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE",
    "WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY",
    "WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY_FILE",
    "WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS",
    "WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS"
  ]

  setup do
    original_client = Application.get_env(:wardwright, :authoring_agent_client, :unset)

    original_env =
      for key <- @env_keys, into: %{} do
        {key, System.get_env(key)}
      end

    Enum.each(@env_keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(@env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)

      case original_client do
        :unset -> Application.delete_env(:wardwright, :authoring_agent_client)
        client -> Application.put_env(:wardwright, :authoring_agent_client, client)
      end
    end)

    :ok
  end

  test "Jido-backed in-page authoring route reaches Wardwright and captures a receipt" do
    assert call(:post, "/__test/config", jido_smoke_config()).status == 200

    base_url = wardwright_router_base_url()

    Application.put_env(:wardwright, :authoring_agent_client, __MODULE__.WardwrightHttpJidoClient)
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", "unit-model")
    System.put_env("WARDWRIGHT_BIND", base_url)

    {:ok, response} =
      WardwrightWeb.AuthoringAgent.respond("Review the current model for release readiness.", %{
        model_id: "operator-selected-model",
        pattern_id: "release-readiness"
      })

    assert response.status == "completed"
    assert response.backend.backend == "jido_ai"
    assert response.backend.route == "wardwright"
    assert response.backend.model == "unit-model"
    assert response.content =~ "Jido in-page adapter reached Wardwright"
    assert response.content =~ "selected_model=canned/jido-ai"

    assert %{
             framework: "jido_ai",
             selected_model: "canned/jido-ai",
             wardwright_receipt_id: receipt_id
           } = response.provider_usage

    assert is_binary(receipt_id)
    assert receipt_id != ""

    assert_receipt_caller!(receipt_id, %{
      application_id: "app-jido-authoring",
      client_request_id_prefix: "jido-authoring-smoke-",
      consuming_agent_id: "agent-jido-authoring",
      consuming_user_id: "user-jido-smoke",
      run_id: "run-jido-smoke",
      session_id: "session-jido-smoke",
      tenant_id: "tenant-jido-smoke"
    })

    assert :wardwright@framework_adapter.smoke_status(true, true, true, true, true) == "passed"

    assert :wardwright@framework_adapter.framework_fidelity(true, true, true, false) ==
             "framework_receipt_correlated"

    assert_framework_receipt_ready!("jido-ai")
  end

  defmodule WardwrightHttpJidoClient do
    def generate_text(prompt, opts) do
      model = Keyword.fetch!(opts, :model)
      base_url = Map.fetch!(model, :base_url)
      model_id = Map.fetch!(model, :model)

      body =
        JSON.encode!(%{
          "max_tokens" => Keyword.fetch!(opts, :max_tokens),
          "messages" => [
            %{"content" => prompt, "role" => "user"}
          ],
          "model" => model_id,
          "temperature" => Keyword.fetch!(opts, :temperature)
        })

      headers =
        [
          {"authorization", "Bearer #{Keyword.fetch!(opts, :api_key)}"},
          {"x-wardwright-tenant-id", "tenant-jido-smoke"},
          {"x-wardwright-application-id", "app-jido-authoring"},
          {"x-wardwright-agent-id", "agent-jido-authoring"},
          {"x-wardwright-user-id", "user-jido-smoke"},
          {"x-wardwright-session-id", "session-jido-smoke"},
          {"x-wardwright-run-id", "run-jido-smoke"},
          {"x-client-request-id", "jido-authoring-smoke-#{System.unique_integer([:positive])}"}
        ]
        |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

      url = String.to_charlist("#{base_url}/chat/completions")

      case :httpc.request(:post, {url, headers, ~c"application/json", body}, [], body_format: :binary) do
        {:ok, {{_http, status, _reason}, response_headers, response_body}} when status in 200..299 ->
          receipt_id = response_header!(response_headers, "x-wardwright-receipt-id")
          selected_model = response_header!(response_headers, "x-wardwright-selected-model")
          provider_text = provider_text(response_body)

          {:ok,
           %{
             content:
               JSON.encode!(%{
                 "answer" =>
                   "Jido in-page adapter reached Wardwright selected_model=#{selected_model} receipt=#{receipt_id}: #{provider_text}",
                 "tool_calls" => []
               }),
             usage: %{
               framework: "jido_ai",
               selected_model: selected_model,
               wardwright_receipt_id: receipt_id
             }
           }}

        {:ok, {{_http, status, reason}, _headers, response_body}} ->
          {:error, %{body: response_body, reason: reason, status: status}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp response_header!(headers, name) do
      Enum.find_value(headers, fn {key, value} ->
        if String.downcase(to_string(key)) == name, do: to_string(value)
      end) || raise "missing #{name} header"
    end

    defp provider_text(response_body) do
      response_body
      |> JSON.decode!()
      |> get_in(["choices", Access.at(0), "message", "content"])
      |> to_string()
    end
  end

  defp jido_smoke_config do
    unit_policy_config()
    |> Map.put("governance", [])
    |> Map.put("targets", [
      %{
        "canned_outputs" => [JSON.encode!(%{"answer" => "jido ai smoke ok", "tool_calls" => []})],
        "context_window" => 256,
        "model" => "canned/jido-ai",
        "provider_kind" => "canned_sequence"
      }
    ])
    |> Map.put("structured_output", %{
      "schemas" => %{
        "authoring_tool_plan_v1" => %{
          "additionalProperties" => true,
          "properties" => %{
            "answer" => %{"minLength" => 1, "type" => "string"},
            "tool_calls" => %{"items" => %{"type" => "object"}, "type" => "array"}
          },
          "required" => ["answer", "tool_calls"],
          "type" => "object"
        }
      }
    })
  end
end
