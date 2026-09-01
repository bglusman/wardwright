defmodule Wardwright.RoutePlannerTest do
  use Wardwright.RouterCase

  test "dispatcher selects the smallest fitting model and preserves larger fallbacks" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "dispatchers" => [%{"id" => "fit-dispatcher", "models" => ["small/model", "medium/model", "large/model"]}],
        "model_id" => "unit-model",
        "route_root" => "fit-dispatcher",
        "targets" => [
          %{"context_window" => 16, "model" => "small/model"},
          %{"context_window" => 64, "model" => "medium/model"},
          %{"context_window" => 256, "model" => "large/model"}
        ],
        "version" => "unit-version"
      })

    assert %{
             fallback_models: ["large/model"],
             route_type: "dispatcher",
             selected_model: "medium/model",
             selected_models: ["medium/model", "large/model"],
             skipped: [%{"reason" => "context_window_too_small", "target" => "small/model"}]
           } = Wardwright.select_route(32)
  end

  test "cascade keeps declaration order while skipping oversized targets" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "cascades" => [%{"id" => "local-then-reserve", "models" => ["fast/model", "steady/model", "reserve/model"]}],
        "model_id" => "unit-model",
        "route_root" => "local-then-reserve",
        "targets" => [
          %{"context_window" => 16, "model" => "fast/model"},
          %{"context_window" => 128, "model" => "steady/model"},
          %{"context_window" => 256, "model" => "reserve/model"}
        ],
        "version" => "unit-version"
      })

    assert %{
             fallback_models: ["reserve/model"],
             route_type: "cascade",
             selected_model: "steady/model",
             selected_models: ["steady/model", "reserve/model"],
             skipped: [%{"target" => "fast/model"}]
           } = Wardwright.select_route(96)
  end

  test "partial alloys use overlapping constituents until smaller contexts stop fitting" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "alloys" => [
          %{
            "constituents" => ["local/qwen", "managed/kimi"],
            "id" => "local-kimi-partial",
            "partial_context" => true,
            "strategy" => "deterministic_all"
          }
        ],
        "model_id" => "unit-model",
        "route_root" => "local-kimi-partial",
        "targets" => [
          %{"context_window" => 32, "model" => "local/qwen"},
          %{"context_window" => 256, "model" => "managed/kimi"}
        ],
        "version" => "unit-version"
      })

    assert %{
             combine_strategy: "deterministic_all",
             route_type: "alloy",
             selected_model: "local/qwen",
             selected_models: ["local/qwen", "managed/kimi"],
             skipped: []
           } = Wardwright.select_route(16)

    assert %{
             combine_strategy: "deterministic_all",
             route_type: "alloy",
             selected_model: "managed/kimi",
             selected_models: ["managed/kimi"],
             skipped: [%{"reason" => "context_window_too_small", "target" => "local/qwen"}]
           } = Wardwright.select_route(96)
  end

  test "weighted alloys respect weights and expose the selected plan in receipts" do
    {:ok, _config} =
      Wardwright.put_config(%{
        "alloys" => [
          %{
            "constituents" => [
              %{"model" => "cheap/model", "weight" => 1},
              %{"model" => "strong/model", "weight" => 100}
            ],
            "id" => "weighted-blend",
            "min_context_window" => 128,
            "strategy" => "weighted"
          }
        ],
        "model_id" => "unit-model",
        "route_root" => "weighted-blend",
        "targets" => [
          %{"context_window" => 128, "model" => "cheap/model"},
          %{"context_window" => 128, "model" => "strong/model"}
        ],
        "version" => "unit-version"
      })

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "small prompt", role: "user"}],
          model: "unit-model"
        }
      })

    assert conn.status == 200
    receipt = JSON.decode!(conn.resp_body)["receipt"]

    assert get_in(receipt, ["decision", "route_type"]) == "alloy"
    assert get_in(receipt, ["decision", "strategy"]) == "weighted"
    assert get_in(receipt, ["decision", "selected_model"]) == "strong/model"
    assert get_in(receipt, ["decision", "selected_models"]) == ["strong/model", "cheap/model"]
  end

  test "model graph targets delegate through another Wardwright model to a concrete provider" do
    {:ok, _config} =
      Wardwright.put_config(model_graph_config())

    assert %{
             combine_strategy: "route_dag_delegate",
             route_lineage: [
               %{"delegated_to" => "policy-safe-writer", "model" => "outer-model"},
               %{"model" => "policy-safe-writer", "selected_model" => "canned/final"}
             ],
             route_type: "model_graph",
             selected_model: "canned/final",
             selected_provider: "canned"
           } = Wardwright.select_route(32)

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "hello", role: "user"}],
        model: "outer-model"
      })

    assert conn.status == 200
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["choices", Access.at(0), "message", "content"]) ==
             "nested provider response"

    assert get_in(body, ["wardwright", "selected_model"]) == "canned/final"
  end

  test "route policy can force a concrete provider inside a delegated Wardwright model" do
    {:ok, _config} = Wardwright.put_config(model_graph_config())

    assert %{
             route_blocked: false,
             route_type: "policy_override",
             selected_model: "canned/final",
             selected_provider: "canned"
           } =
             Wardwright.select_route(32, %{
               "allowed_targets" => ["canned"],
               "forced_model" => "canned/final"
             })
  end

  test "model graph validation rejects cycles before activation" do
    assert {:error, "model graph cycle detected at loop-model"} =
             Wardwright.put_config(%{
               "dispatchers" => [%{"id" => "outer-route", "models" => ["loop-model"]}],
               "model_id" => "loop-model",
               "route_root" => "outer-route",
               "targets" => [
                 %{
                   "artifact" => %{
                     "dispatchers" => [%{"id" => "inner-route", "models" => ["local/final"]}],
                     "model_id" => "loop-model",
                     "route_root" => "inner-route",
                     "targets" => [%{"context_window" => 4_096, "model" => "local/final"}],
                     "version" => "inner-version"
                   },
                   "context_window" => 4_096,
                   "model" => "loop-model",
                   "target_kind" => "wardwright_model"
                 }
               ],
               "version" => "unit-version"
             })
  end

  test "model graph validation rejects ModelSkyline on an embedded artifact" do
    config =
      update_in(model_graph_config(), ["targets", Access.at(0), "artifact"], fn artifact ->
        Map.put(artifact, "model_skyline", %{})
      end)

    assert {:error, message} = Wardwright.put_config(config)
    assert message =~ "model_skyline is supported only on a top-level serving model"
  end

  defp model_graph_config do
    %{
      "dispatchers" => [%{"id" => "outer-delegates", "models" => ["policy-safe-writer"]}],
      "model_id" => "outer-model",
      "route_root" => "outer-delegates",
      "targets" => [
        %{
          "artifact" => %{
            "dispatchers" => [%{"id" => "inner-context-fit", "models" => ["canned/final"]}],
            "model_id" => "policy-safe-writer",
            "route_root" => "inner-context-fit",
            "targets" => [
              %{
                "canned_outputs" => ["nested provider response"],
                "context_window" => 8_192,
                "model" => "canned/final",
                "provider_kind" => "canned_sequence"
              }
            ],
            "version" => "inner-version"
          },
          "context_window" => 4_096,
          "model" => "policy-safe-writer",
          "target_kind" => "wardwright_model"
        }
      ],
      "version" => "outer-version"
    }
  end
end
