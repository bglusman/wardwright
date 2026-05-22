defmodule Wardwright.PolicyReplayTest do
  use Wardwright.RouterCase

  @moduletag :policy_replay

  test "receipts record metadata-only VCR fields for policy replay" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "escalate",
          "contains" => "synthetic private",
          "id" => "review-required",
          "kind" => "request_guard",
          "message" => "synthetic review required",
          "severity" => "warning"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        "request" => %{
          "messages" => [
            %{
              "content" => "Synthetic private prompt fixture that must not be stored in VCR.",
              "role" => "user"
            }
          ],
          "model" => "unit-model"
        }
      })

    assert conn.status == 200
    receipt = JSON.decode!(conn.resp_body)["receipt"]
    vcr = receipt["vcr"]

    assert vcr["schema"] == "wardwright.policy_vcr.v0"
    assert vcr["mode"] == "metadata_only"
    assert vcr["redaction"] == "metadata_only"
    assert get_in(vcr, ["request", "message_roles"]) == ["user"]
    assert get_in(vcr, ["request", "message_content_lengths"]) == [64]
    assert get_in(vcr, ["policy", "alert_count"]) == 1
    assert get_in(vcr, ["route", "selected_model"]) == "medium/model"
    assert get_in(vcr, ["decision", "selected_model"]) == "medium/model"

    encoded_vcr = JSON.encode!(vcr)
    refute encoded_vcr =~ "Synthetic private prompt"
    refute encoded_vcr =~ "Mock Wardwright response"
    refute Map.has_key?(vcr, "full_session")
  end

  test "full-session VCR mode records request and response payloads only when explicitly enabled" do
    config =
      unit_policy_config()
      |> Map.put("targets", [
        %{
          "canned_outputs" => ["Full-session synthetic completion"],
          "context_window" => 256,
          "model" => "canned/model",
          "provider_kind" => "canned_sequence"
        }
      ])
      |> Map.put("vcr", %{"mode" => "full_session"})

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        "messages" => [
          %{
            "content" => "Full-session synthetic prompt that is deliberately opt-in.",
            "role" => "user"
          }
        ],
        "model" => "unit-model"
      })

    assert conn.status == 200
    receipt_id = JSON.decode!(conn.resp_body) |> get_in(["wardwright", "receipt_id"])
    receipt = Wardwright.ReceiptStore.get(receipt_id)
    vcr = receipt["vcr"]

    assert vcr["mode"] == "full_session"
    assert vcr["redaction"] == "full_session"

    assert get_in(vcr, ["full_session", "request", "body", "messages", Access.at(0), "content"]) ==
             "Full-session synthetic prompt that is deliberately opt-in."

    assert get_in(vcr, ["full_session", "response", "content"]) == "Full-session synthetic completion"
    assert get_in(vcr, ["request", "message_content_lengths"]) == [58]
  end

  test "policy replay returns recorded decisions without creating a provider attempt" do
    receipt = replay_receipt_fixture()
    Wardwright.ReceiptStore.insert(receipt)

    assert {:ok, replay} = Wardwright.PolicyReplay.replay_receipt_id("rcpt_replay_1")

    assert replay["schema"] == "wardwright.policy_replay.v0"
    assert replay["source_receipt_id"] == "rcpt_replay_1"
    assert replay["source_vcr_schema"] == "wardwright.policy_vcr.v0"
    assert replay["redaction"] == "metadata_only"
    assert replay["final"]["status"] == "replayed"
    assert replay["final"]["original_status"] == "policy_failed_closed"
    assert replay["final"]["provider_called"] == false
    assert replay["final"]["would_call_provider"] == false
    assert get_in(replay, ["policy", "actions", Access.at(0), "rule_id"]) == "review-required"
    assert get_in(replay, ["route", "route_blocked"]) == true
    assert replay["warnings"] == []
  end

  test "protected replay API replays stored receipt metadata and rejects remote callers" do
    Wardwright.ReceiptStore.insert(replay_receipt_fixture())

    rejected =
      call(
        :post,
        "/v1/policy-authoring/replay-receipts/rcpt_replay_1",
        %{},
        [],
        {203, 0, 113, 10}
      )

    assert rejected.status == 403

    conn = call(:post, "/v1/policy-authoring/replay-receipts/rcpt_replay_1", %{})
    assert conn.status == 200

    replay = JSON.decode!(conn.resp_body)["replay"]
    assert replay["source_receipt_id"] == "rcpt_replay_1"
    assert get_in(replay, ["policy", "events", Access.at(0), "type"]) == "policy.alert"
    assert get_in(replay, ["final", "provider_called"]) == false

    missing = call(:post, "/v1/policy-authoring/replay-receipts/not-real", %{})
    assert missing.status == 404
  end

  test "legacy replay summarizes raw request messages instead of exposing content" do
    legacy =
      replay_receipt_fixture()
      |> Map.delete("vcr")
      |> put_in(["receipt_id"], "rcpt_legacy_raw")
      |> put_in(["request"], %{
        "messages" => [
          %{"content" => "Synthetic legacy raw prompt that must stay out of replay.", "role" => "user"}
        ],
        "model" => "unit-model",
        "normalized_model" => "unit-model",
        "stream" => true
      })

    Wardwright.ReceiptStore.insert(legacy)

    assert {:ok, replay} = Wardwright.PolicyReplay.replay_receipt_id("rcpt_legacy_raw")
    assert replay["source_vcr_schema"] == "wardwright.receipt_legacy.v1"
    assert replay["warnings"] == ["receipt has no policy_vcr metadata; replay used legacy receipt fields"]
    assert get_in(replay, ["request", "message_roles"]) == ["user"]
    assert get_in(replay, ["request", "message_content_lengths"]) == [57]

    encoded = JSON.encode!(replay)
    refute encoded =~ "Synthetic legacy raw prompt"
  end

  defp replay_receipt_fixture do
    %{
      "attempts" => [
        %{
          "called_provider" => false,
          "mock" => true,
          "model" => "unconfigured/no-target",
          "provider_id" => "unconfigured",
          "status" => "policy_failed_closed"
        }
      ],
      "caller" => %{},
      "created_at" => 1_800_000_222,
      "decision" => %{
        "policy_actions" => [
          %{
            "action" => "block",
            "kind" => "request_guard",
            "matched" => true,
            "message" => "synthetic review required",
            "rule_id" => "review-required"
          }
        ],
        "policy_conflicts" => [],
        "reason" => "route policy removed all provider targets",
        "route_blocked" => true,
        "route_id" => "policy.block",
        "route_type" => "policy_override",
        "selected_model" => "unconfigured/no-target",
        "selected_provider" => "unconfigured"
      },
      "final" => %{
        "events" => [
          %{
            "message" => "synthetic review required",
            "rule_id" => "review-required",
            "severity" => "warning",
            "type" => "policy.alert"
          }
        ],
        "status" => "policy_failed_closed"
      },
      "model_id" => "unit-model",
      "model_version" => "unit-version",
      "receipt_id" => "rcpt_replay_1",
      "receipt_schema" => "v1",
      "request" => %{
        "estimated_prompt_tokens" => 12,
        "message_count" => 1,
        "model" => "unit-model",
        "normalized_model" => "unit-model"
      },
      "vcr" => %{
        "decision" => %{
          "reason" => "route policy removed all provider targets",
          "route_blocked" => true,
          "route_id" => "policy.block",
          "route_type" => "policy_override",
          "selected_model" => "unconfigured/no-target",
          "selected_provider" => "unconfigured"
        },
        "final" => %{"status" => "policy_failed_closed"},
        "policy" => %{
          "actions" => [
            %{
              "action" => "block",
              "kind" => "request_guard",
              "matched" => true,
              "message" => "synthetic review required",
              "rule_id" => "review-required"
            }
          ],
          "alert_count" => 1,
          "conflicts" => [],
          "events" => [
            %{
              "message" => "synthetic review required",
              "rule_id" => "review-required",
              "severity" => "warning",
              "type" => "policy.alert"
            }
          ],
          "route_constraints" => %{"allowed_targets" => []}
        },
        "provider" => %{
          "called_provider" => false,
          "mock" => true,
          "status" => "policy_failed_closed"
        },
        "redaction" => "metadata_only",
        "request" => %{
          "estimated_prompt_tokens" => 12,
          "message_content_lengths" => [44],
          "message_count" => 1,
          "message_roles" => ["user"],
          "model" => "unit-model",
          "normalized_model" => "unit-model",
          "stream" => false
        },
        "schema" => "wardwright.policy_vcr.v0"
      }
    }
  end
end
