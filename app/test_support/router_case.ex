defmodule Wardwright.Test.StreamingProvider do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/ollama/api/chat" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    chunks =
      cond do
        body =~ "Use NewClient instead." ->
          ["use NewClient(", "arg) now"]

        body =~ "safe prefix" ->
          ["safe prefix that can release ", "Old", "Client(arg) now"]

        true ->
          ["use Old", "Client(arg) now"]
      end

    conn =
      conn
      |> Plug.Conn.put_resp_content_type("application/x-ndjson")
      |> Plug.Conn.send_chunked(200)

    conn =
      Enum.reduce(chunks, conn, fn chunk, conn ->
        {:ok, conn} =
          Plug.Conn.chunk(
            conn,
            JSON.encode!(%{"done" => false, "message" => %{"content" => chunk}}) <> "\n"
          )

        conn
      end)

    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        JSON.encode!(%{
          "done" => true,
          "done_reason" => "stop",
          "eval_count" => 2,
          "prompt_eval_count" => 4,
          "total_duration" => 123
        }) <> "\n"
      )

    conn
  end

  post "/repairing-ollama/api/chat" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    content =
      if body =~ "Previous model output failed Wardwright structured output validation" do
        ~s({"answer":"repaired after feedback","confidence":0.91})
      else
        "not json yet"
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(
      200,
      JSON.encode!(%{
        "done" => true,
        "message" => %{"content" => content},
        "total_duration" => 123
      })
    )
  end

  post "/openai/chat/completions" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer test-openai-key"] ->
        request = JSON.decode!(body)

        if request["stream"] == true do
          conn =
            conn
            |> Plug.Conn.put_resp_content_type("text/event-stream")
            |> Plug.Conn.send_chunked(200)

          {conn, finish_reason} =
            if streamed_tool_request?(request) do
              stream_openai_tool_calls(conn)
            else
              stream_openai_content(conn)
            end

          {:ok, conn} =
            Plug.Conn.chunk(
              conn,
              "data: " <>
                JSON.encode!(%{
                  "choices" => [%{"delta" => %{}, "finish_reason" => finish_reason, "index" => 0}],
                  "usage" => %{"completion_tokens" => 2, "prompt_tokens" => 3, "total_tokens" => 5}
                }) <>
                "\n\n"
            )

          {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
          conn
        else
          {finish_reason, message} =
            cond do
              server_tool_result_request?(request) ->
                {"stop",
                 %{
                   "content" => server_tool_response_content(request),
                   "role" => "assistant"
                 }}

              server_tool_request?(request) ->
                {name, call_id, arguments} = requested_server_tool_call(request)

                {"tool_calls",
                 %{
                   "content" => nil,
                   "role" => "assistant",
                   "tool_calls" => [
                     %{
                       "function" => %{"arguments" => arguments, "name" => name},
                       "id" => call_id,
                       "type" => "function"
                     }
                   ]
                 }}

              forwarded_tool_request?(request) ->
                {"tool_calls",
                 %{
                   "content" => nil,
                   "role" => "assistant",
                   "tool_calls" => [
                     %{
                       "function" => %{"arguments" => ~s({"title":"Forwarded tools"}), "name" => "create_pull_request"},
                       "id" => "call_forwarded_1",
                       "type" => "function"
                     }
                   ]
                 }}

              true ->
                {"stop", %{"content" => "openai-compatible text response", "role" => "assistant"}}
            end

          Plug.Conn.send_resp(
            conn,
            200,
            JSON.encode!(%{
              "choices" => [%{"finish_reason" => finish_reason, "index" => 0, "message" => message}],
              "usage" => %{"completion_tokens" => 2, "prompt_tokens" => 3, "total_tokens" => 5}
            })
          )
        end

      _ ->
        Plug.Conn.send_resp(conn, 401, "missing authorization")
    end
  end

  defp forwarded_tool_request?(request) do
    is_list(request["tools"]) and request["tools"] != [] and
      request["tool_choice"] == "auto" and
      Enum.any?(request["messages"] || [], fn message ->
        is_list(message["tool_calls"]) or message["tool_call_id"] == "call_1" or message["role"] == "tool"
      end)
  end

  defp server_tool_request?(request) do
    is_list(request["tools"]) and
      Enum.any?(request["tools"], fn tool ->
        get_in(tool, ["function", "name"]) in [
          "wardwright_policy_cache_status",
          "dune_echo_tool",
          "beam_reverse_tool"
        ]
      end) and not server_tool_result_request?(request)
  end

  defp server_tool_result_request?(request) do
    Enum.any?(request["messages"] || [], fn message ->
      message["role"] == "tool" and
        message["tool_call_id"] in [
          "call_wardwright_status_1",
          "call_dune_echo_tool_1",
          "call_beam_reverse_tool_1"
        ]
    end)
  end

  defp requested_server_tool_call(request) do
    request
    |> Map.get("tools", [])
    |> Enum.find_value(fn tool ->
      case get_in(tool, ["function", "name"]) do
        "wardwright_policy_cache_status" -> {"wardwright_policy_cache_status", "call_wardwright_status_1", "{}"}
        "dune_echo_tool" -> {"dune_echo_tool", "call_dune_echo_tool_1", ~s({"value":"from-model"})}
        "beam_reverse_tool" -> {"beam_reverse_tool", "call_beam_reverse_tool_1", ~s({"text":"stressed"})}
        _other -> nil
      end
    end)
  end

  defp server_tool_response_content(request) do
    cond do
      server_tool_result_message?(request, "call_wardwright_status_1") ->
        "Wardwright server tool status was observed."

      server_tool_result_message?(request, "call_dune_echo_tool_1") ->
        "Wardwright Dune server tool result was observed."

      server_tool_result_message?(request, "call_beam_reverse_tool_1") ->
        "Wardwright BEAM server tool result was observed."
    end
  end

  defp server_tool_result_message?(request, call_id) do
    Enum.any?(request["messages"] || [], fn message ->
      message["role"] == "tool" and message["tool_call_id"] == call_id
    end)
  end

  defp streamed_tool_request?(request) do
    is_list(request["tools"]) and request["tools"] != [] and request["tool_choice"] == "auto"
  end

  defp stream_openai_content(conn) do
    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        "data: " <>
          JSON.encode!(%{"choices" => [%{"delta" => %{"content" => "hello "}}]}) <>
          "\n\n"
      )

    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        "event: completion.delta\n" <>
          "data:" <>
          JSON.encode!(%{"choices" => [%{"delta" => %{"content" => "world"}}]}) <>
          "\n\n"
      )

    {conn, "stop"}
  end

  defp stream_openai_tool_calls(conn) do
    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        "data: " <>
          JSON.encode!(%{
            "choices" => [
              %{
                "delta" => %{
                  "tool_calls" => [
                    %{
                      "function" => %{"arguments" => "", "name" => "create_pull_request"},
                      "id" => "call_stream_1",
                      "index" => 0,
                      "type" => "function"
                    }
                  ]
                },
                "index" => 0
              }
            ]
          }) <>
          "\n\n"
      )

    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        "data: " <>
          JSON.encode!(%{
            "choices" => [
              %{
                "delta" => %{
                  "tool_calls" => [
                    %{
                      "function" => %{"arguments" => ~s({"title":"Streamed tools"})},
                      "index" => 0
                    }
                  ]
                },
                "index" => 0
              }
            ]
          }) <>
          "\n\n"
      )

    {conn, "tool_calls"}
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end

defmodule Wardwright.RouterCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import Plug.Conn
  import Plug.Test

  alias Wardwright.Test.StreamingProvider

  using do
    quote do
      use ExUnit.Case, async: false

      import Plug.Conn
      import Plug.Test
      import Wardwright.RouterCase
    end
  end

  setup do
    previous_transcript_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)
    transcript_store_dir = Path.join(System.tmp_dir!(), "wardwright-router-case-#{System.unique_integer([:positive])}")

    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, transcript_store_dir)
    Wardwright.reset_config()
    Wardwright.ReceiptStore.clear()
    Wardwright.ModelApiKeyStore.reset!()
    Wardwright.PolicyScenarioStore.clear()
    Wardwright.PolicyCache.reset()

    on_exit(fn ->
      File.rm_rf(transcript_store_dir)
      restore_env(:counterfactual_transcript_store_dir, previous_transcript_store_dir)
    end)

    :ok
  end

  @opts Wardwright.Router.init([])

  def call(method, path, body \\ nil, headers \\ [], remote_ip \\ {127, 0, 0, 1}) do
    encoded = if !is_nil(body), do: JSON.encode!(body)

    method
    |> conn(path, encoded)
    |> Map.put(:remote_ip, remote_ip)
    |> put_req_header("content-type", "application/json")
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {key, value}, acc -> put_req_header(acc, key, value) end)
    end)
    |> Wardwright.Router.call(@opts)
  end

  def streaming_provider_base_url(prefix) do
    ref = :"wardwright_streaming_provider_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Plug.Cowboy.http(StreamingProvider, [], ref: ref, port: 0)
    port = :ranch.get_port(ref)
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    "http://127.0.0.1:#{port}#{prefix}"
  end

  def wardwright_router_base_url do
    ref = :"wardwright_router_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Plug.Cowboy.http(Wardwright.Router, [], ref: ref, port: 0)
    port = :ranch.get_port(ref)
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    "http://127.0.0.1:#{port}"
  end

  def unit_policy_config do
    %{
      "governance" => [
        %{
          "action" => "escalate",
          "contains" => "looks done",
          "id" => "ambiguous-success",
          "kind" => "request_guard",
          "message" => "completion claim needs artifact",
          "severity" => "warning"
        }
      ],
      "model_id" => "unit-model",
      "targets" => [
        %{"context_window" => 8, "model" => "tiny/model"},
        %{"context_window" => 32, "model" => "medium/model"},
        %{"context_window" => 256, "model" => "large/model"}
      ],
      "version" => "unit-version"
    }
  end

  def structured_policy_config(outputs, max_failures_per_rule \\ 2) do
    unit_policy_config()
    |> Map.put("targets", [
      %{
        "canned_outputs" => outputs,
        "context_window" => 256,
        "model" => "canned/model",
        "provider_kind" => "canned_sequence"
      }
    ])
    |> Map.put("structured_output", %{
      "guard_loop" => %{
        "max_attempts" => 4,
        "max_failures_per_rule" => max_failures_per_rule,
        "on_exhausted" => "block",
        "on_violation" => "retry_with_validation_feedback"
      },
      "schemas" => %{
        "answer_v1" => %{
          "additionalProperties" => false,
          "properties" => %{
            "answer" => %{"minLength" => 1, "type" => "string"},
            "citations" => %{"items" => %{"type" => "string"}, "type" => "array"},
            "confidence" => %{"maximum" => 1, "minimum" => 0, "type" => "number"}
          },
          "required" => ["answer", "confidence"],
          "type" => "object"
        }
      },
      "semantic_rules" => [
        %{"gte" => 0.7, "id" => "minimum-confidence", "kind" => "json_path_number", "path" => "/confidence"}
      ]
    })
  end

  def receipt_fixture(receipt_id, created_at, agent_id, opts \\ []) do
    status = Keyword.get(opts, :status, "completed")

    %{
      "caller" => %{
        "application_id" => %{"source" => "header", "value" => "app-a"},
        "consuming_agent_id" => %{"source" => "header", "value" => agent_id},
        "consuming_user_id" => %{"source" => "header", "value" => "user-a"},
        "run_id" => %{"source" => "header", "value" => "run-a"},
        "session_id" => %{"source" => "header", "value" => "session-a"},
        "tenant_id" => %{"source" => "header", "value" => "tenant-a"}
      },
      "created_at" => created_at,
      "decision" => %{"selected_model" => "managed/kimi-k2.6", "selected_provider" => "managed"},
      "events" => [%{"event_id" => receipt_id <> ":1", "receipt_id" => receipt_id, "sequence" => 1}],
      "final" => %{"status" => status},
      "model_id" => "coding-balanced",
      "model_version" => "2026-05-13.mock",
      "receipt_id" => receipt_id,
      "receipt_schema" => "v1",
      "simulation" => status == "simulated"
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)
end
