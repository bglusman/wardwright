defmodule Wardwright.RoutePlannerTest do
  use Wardwright.RouterCase

  test "dispatcher selects the smallest fitting model and preserves larger fallbacks" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "model_id" => "unit-model",
        "version" => "unit-version",
        "targets" => [
          %{"model" => "small/model", "context_window" => 16},
          %{"model" => "medium/model", "context_window" => 64},
          %{"model" => "large/model", "context_window" => 256}
        ],
        "route_root" => "fit-dispatcher",
        "dispatchers" => [
          %{"id" => "fit-dispatcher", "models" => ["small/model", "medium/model", "large/model"]}
        ]
      })

    assert %{
             route_type: "dispatcher",
             selected_model: "medium/model",
             selected_models: ["medium/model", "large/model"],
             fallback_models: ["large/model"],
             skipped: [%{"target" => "small/model", "reason" => "context_window_too_small"}]
           } = Wardwright.select_route(32)
  end

  test "cascade keeps declaration order while skipping oversized targets" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "model_id" => "unit-model",
        "version" => "unit-version",
        "targets" => [
          %{"model" => "fast/model", "context_window" => 16},
          %{"model" => "steady/model", "context_window" => 128},
          %{"model" => "reserve/model", "context_window" => 256}
        ],
        "route_root" => "local-then-reserve",
        "cascades" => [
          %{
            "id" => "local-then-reserve",
            "models" => ["fast/model", "steady/model", "reserve/model"]
          }
        ]
      })

    assert %{
             route_type: "cascade",
             selected_model: "steady/model",
             selected_models: ["steady/model", "reserve/model"],
             fallback_models: ["reserve/model"],
             skipped: [%{"target" => "fast/model"}]
           } = Wardwright.select_route(96)
  end

  test "partial alloys use overlapping constituents until smaller contexts stop fitting" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "model_id" => "unit-model",
        "version" => "unit-version",
        "targets" => [
          %{"model" => "local/qwen", "context_window" => 32},
          %{"model" => "managed/kimi", "context_window" => 256}
        ],
        "route_root" => "local-kimi-partial",
        "alloys" => [
          %{
            "id" => "local-kimi-partial",
            "strategy" => "deterministic_all",
            "partial_context" => true,
            "constituents" => ["local/qwen", "managed/kimi"]
          }
        ]
      })

    assert %{
             route_type: "alloy",
             combine_strategy: "deterministic_all",
             selected_model: "local/qwen",
             selected_models: ["local/qwen", "managed/kimi"],
             skipped: []
           } = Wardwright.select_route(16)

    assert %{
             route_type: "alloy",
             combine_strategy: "deterministic_all",
             selected_model: "managed/kimi",
             selected_models: ["managed/kimi"],
             skipped: [%{"target" => "local/qwen", "reason" => "context_window_too_small"}]
           } = Wardwright.select_route(96)
  end

  test "weighted alloys respect weights and expose the selected plan in receipts" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "model_id" => "unit-model",
        "version" => "unit-version",
        "targets" => [
          %{"model" => "cheap/model", "context_window" => 128},
          %{"model" => "strong/model", "context_window" => 128}
        ],
        "route_root" => "weighted-blend",
        "alloys" => [
          %{
            "id" => "weighted-blend",
            "strategy" => "weighted",
            "min_context_window" => 128,
            "constituents" => [
              %{"model" => "cheap/model", "weight" => 1},
              %{"model" => "strong/model", "weight" => 100}
            ]
          }
        ]
      })

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          model: "unit-model",
          messages: [%{role: "user", content: "small prompt"}]
        }
      })

    assert conn.status == 200
    receipt = Jason.decode!(conn.resp_body)["receipt"]

    assert get_in(receipt, ["decision", "route_type"]) == "alloy"
    assert get_in(receipt, ["decision", "strategy"]) == "weighted"
    assert get_in(receipt, ["decision", "selected_model"]) == "strong/model"
    assert get_in(receipt, ["decision", "selected_models"]) == ["strong/model", "cheap/model"]
  end

  test "model graph targets delegate through another Wardwright model to a concrete provider" do
    {:ok, _config} =
      Wardwright.put_config(model_graph_config())

    assert %{
             route_type: "model_graph",
             combine_strategy: "route_dag_delegate",
             selected_model: "canned/final",
             selected_provider: "canned",
             route_lineage: [
               %{"model" => "outer-model", "delegated_to" => "policy-safe-writer"},
               %{"model" => "policy-safe-writer", "selected_model" => "canned/final"}
             ]
           } = Wardwright.select_route(32)

    conn =
      call(:post, "/v1/chat/completions", %{
        model: "outer-model",
        messages: [%{role: "user", content: "hello"}]
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) ==
             "nested provider response"

    assert get_in(body, ["wardwright", "selected_model"]) == "canned/final"
  end

  test "route policy can force a concrete provider inside a delegated Wardwright model" do
    {:ok, _config} = Wardwright.put_config(model_graph_config())

    assert %{
             route_type: "policy_override",
             selected_model: "canned/final",
             selected_provider: "canned",
             route_blocked: false
           } =
             Wardwright.select_route(32, %{
               "forced_model" => "canned/final",
               "allowed_targets" => ["canned"]
             })
  end

  test "model graph validation rejects cycles before activation" do
    assert {:error, "model graph cycle detected at loop-model"} =
             Wardwright.put_config(%{
               "model_id" => "loop-model",
               "version" => "unit-version",
               "targets" => [
                 %{
                   "model" => "loop-model",
                   "target_kind" => "wardwright_model",
                   "context_window" => 4_096,
                   "artifact" => %{
                     "model_id" => "loop-model",
                     "version" => "inner-version",
                     "targets" => [
                       %{"model" => "local/final", "context_window" => 4_096}
                     ],
                     "route_root" => "inner-route",
                     "dispatchers" => [
                       %{"id" => "inner-route", "models" => ["local/final"]}
                     ]
                   }
                 }
               ],
               "route_root" => "outer-route",
               "dispatchers" => [
                 %{"id" => "outer-route", "models" => ["loop-model"]}
               ]
             })
  end

  defp model_graph_config do
    %{
      "model_id" => "outer-model",
      "version" => "outer-version",
      "targets" => [
        %{
          "model" => "policy-safe-writer",
          "target_kind" => "wardwright_model",
          "context_window" => 4_096,
          "artifact" => %{
            "model_id" => "policy-safe-writer",
            "version" => "inner-version",
            "targets" => [
              %{
                "model" => "canned/final",
                "provider_kind" => "canned_sequence",
                "context_window" => 8_192,
                "canned_outputs" => ["nested provider response"]
              }
            ],
            "route_root" => "inner-context-fit",
            "dispatchers" => [
              %{"id" => "inner-context-fit", "models" => ["canned/final"]}
            ]
          }
        }
      ],
      "route_root" => "outer-delegates",
      "dispatchers" => [
        %{"id" => "outer-delegates", "models" => ["policy-safe-writer"]}
      ]
    }
  end
end
