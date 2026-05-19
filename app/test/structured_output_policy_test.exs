defmodule Wardwright.StructuredOutputPolicyTest do
  use Wardwright.RouterCase

  alias Wardwright.Policy.StructuredOutput
  alias Wardwright.Runtime.Events

  test "provider runtime enforces target timeouts and publishes attempt visibility" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_delay_ms" => 25,
          "canned_outputs" => ["late answer"],
          "context_window" => 256,
          "model" => "slow/model",
          "provider_kind" => "canned_sequence",
          "provider_timeout_ms" => 1
        }
      ])
      |> Map.put("governance", [])

    assert :ok = Events.subscribe(Events.topic(:models))
    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "hello", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 502
    body = Jason.decode!(conn.resp_body)
    assert get_in(body, ["wardwright", "status"]) == "provider_error"
    assert get_in(body, ["wardwright", "provider_error"]) =~ "provider timed out after 1ms"

    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()
    assert get_in(receipt, ["attempts", Access.at(0), "called_provider"]) == true
    assert get_in(receipt, ["attempts", Access.at(0), "mock"]) == false

    assert_receive {:wardwright_runtime_event, "runtime:models",
                    %{
                      "model" => "slow/model",
                      "provider_id" => "slow",
                      "timeout_ms" => 1,
                      "type" => "provider.attempt.started"
                    }}

    assert_receive {:wardwright_runtime_event, "runtime:models",
                    %{
                      "model" => "slow/model",
                      "provider_id" => "slow",
                      "status" => "provider_error",
                      "type" => "provider.attempt.finished"
                    }}
  end

  test "structured output guard retries canned provider outputs and records guard receipts" do
    config =
      structured_policy_config(
        [
          "{not json",
          ~s({"answer":"missing confidence"}),
          ~s({"answer":"valid and confident","confidence":0.91})
        ],
        3
      )

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "return structured json", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    structured = get_in(body, ["wardwright", "structured_output"])
    assert structured["final_status"] == "completed_after_guard"
    assert structured["selected_schema"] == "answer_v1"
    assert structured["attempt_count"] == 3

    assert Enum.map(structured["guard_events"], & &1["guard_type"]) == [
             "json_syntax",
             "schema_validation"
           ]

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) ==
             ~s({"answer":"valid and confident","confidence":0.91})
  end

  test "structured output guard fails closed when per-rule budget is exhausted" do
    config =
      structured_policy_config([
        ~s({"answer":"too uncertain one","confidence":0.1}),
        ~s({"answer":"too uncertain two","confidence":0.2}),
        ~s({"answer":"would have succeeded too late","confidence":0.95})
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "return structured json", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 422
    body = Jason.decode!(conn.resp_body)

    structured = get_in(body, ["wardwright", "structured_output"])
    assert structured["final_status"] == "exhausted_rule_budget"
    assert structured["exhausted_rule_id"] == "minimum-confidence"

    assert Enum.map(structured["guard_events"], & &1["rule_id"]) == [
             "minimum-confidence",
             "minimum-confidence"
           ]
  end

  test "structured semantic rules reject matched JSON pointer strings" do
    config =
      structured_policy_config([~s({"answer":"draft answer","confidence":0.95})], 3)
      |> get_in(["structured_output"])
      |> update_in(["semantic_rules"], fn rules ->
        rules ++
          [
            %{
              "id" => "answer-not-draft",
              "kind" => "json_path_string_not_contains",
              "path" => "/answer",
              "pattern" => "draft"
            }
          ]
      end)

    assert {:error, "semantic_validation", "answer-not-draft"} =
             StructuredOutput.validate_output(
               ~s({"answer":"draft answer","confidence":0.95}),
               config
             )

    assert {:ok, "answer_v1", %{"answer" => "final answer", "confidence" => 0.95}} =
             StructuredOutput.validate_output(
               ~s({"answer":"final answer","confidence":0.95}),
               config
             )
  end

  test "structured schema and semantic validation fail closed for boundary violations" do
    config = structured_policy_config([~s({"answer":"unused","confidence":0.95})], 3)

    for invalid_output <- [
          ~s({"answer":"extra field","confidence":0.95,"debug":true}),
          ~s({"answer":"too high","confidence":1.01}),
          ~s({"answer":"","confidence":0.95}),
          ~s({"answer":"bad citation","confidence":0.95,"citations":[123]})
        ] do
      assert {:error, "schema_validation", "structured-json"} =
               StructuredOutput.validate_output(
                 invalid_output,
                 config["structured_output"]
               )
    end

    invalid_path_config =
      config
      |> get_in(["structured_output"])
      |> put_in(["semantic_rules"], [
        %{
          "gte" => 0.7,
          "id" => "confidence-pointer-required",
          "kind" => "json_path_number",
          "path" => "confidence"
        }
      ])

    assert {:error, "semantic_validation", "confidence-pointer-required"} =
             StructuredOutput.validate_output(
               ~s({"answer":"valid","confidence":0.95}),
               invalid_path_config
             )
  end

  test "structured schema validates arrays of tool-call objects" do
    config = %{
      "schemas" => %{
        "authoring_tool_plan_v1" => %{
          "additionalProperties" => false,
          "properties" => %{
            "answer" => %{"minLength" => 1, "type" => "string"},
            "tool_calls" => %{
              "items" => %{
                "additionalProperties" => false,
                "properties" => %{
                  "arguments" => %{
                    "additionalProperties" => true,
                    "properties" => %{},
                    "type" => "object"
                  },
                  "name" => %{"minLength" => 1, "type" => "string"}
                },
                "required" => ["name", "arguments"],
                "type" => "object"
              },
              "type" => "array"
            }
          },
          "required" => ["answer", "tool_calls"],
          "type" => "object"
        }
      }
    }

    assert {:ok, "authoring_tool_plan_v1", _parsed} =
             StructuredOutput.validate_output(
               ~s({"answer":"Drafted.","tool_calls":[{"name":"draft_wardwright_model","arguments":{"model_id":"cow"}}]}),
               config
             )

    assert {:error, "schema_validation", "structured-json"} =
             StructuredOutput.validate_output(
               ~s({"answer":"Drafted.","tool_calls":[{"name":"draft_wardwright_model"}]}),
               config
             )
  end

  test "structured semantic rules traverse nested JSON pointer paths" do
    config =
      structured_policy_config([~s({"answer":"unused","confidence":0.95})], 3)
      |> get_in(["structured_output"])
      |> put_in(["schemas"], %{
        "nested_answer_v1" => %{
          "additionalProperties" => true,
          "properties" => %{},
          "required" => ["answer"],
          "type" => "object"
        }
      })
      |> put_in(["semantic_rules"], [
        %{
          "gte" => 0.7,
          "id" => "nested-minimum-confidence",
          "kind" => "json_path_number",
          "path" => "/answer/confidence"
        }
      ])

    assert {:error, "semantic_validation", "nested-minimum-confidence"} =
             StructuredOutput.validate_output(
               ~s({"answer":{"text":"too uncertain","confidence":0.2}}),
               config
             )

    assert {:ok, "nested_answer_v1", _parsed} =
             StructuredOutput.validate_output(
               ~s({"answer":{"text":"confident","confidence":0.91}}),
               config
             )
  end

  test "structured guard honors integer attempt budgets exactly" do
    config =
      structured_policy_config(["{not json"], 5)
      |> get_in(["structured_output"])
      |> put_in(["guard_loop", "max_attempts"], 2)

    provider = fn _attempt_index ->
      %{
        called_provider: false,
        content: "{not json",
        error: nil,
        latency_ms: 0,
        mock: true,
        status: "completed",
        structured_output: nil
      }
    end

    result = StructuredOutput.run(config, provider)
    assert result.status == "exhausted_guard_budget"
    assert get_in(result.structured_output, ["attempt_count"]) == 2
    assert length(get_in(result.structured_output, ["guard_events"])) == 2
  end
end
