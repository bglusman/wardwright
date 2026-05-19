defmodule Wardwright.RequestPolicyTest do
  use Wardwright.RouterCase

  test "request policy records asynchronous alert events" do
    config = unit_policy_config()
    assert call(:post, "/__test/config", config).status == 200

    request = %{
      request: %{
        messages: [%{content: "Looks done; return JSON for the caller", role: "user"}],
        model: "wardwright/unit-model"
      }
    }

    conn = call(:post, "/v1/wardwright/simulate", request)
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "final", "alert_count"]) == 1

    assert [%{"rule_id" => "ambiguous-success", "type" => "policy.alert"}] =
             get_in(body, ["receipt", "final", "events"])

    assert [
             %{
               "matched" => true,
               "rule_id" => "ambiguous-success",
               "source" => %{"engine" => "dune", "status" => "ok"}
             }
           ] = get_in(body, ["receipt", "decision", "policy_actions"])
  end

  test "request transform policy injects a named reminder into the prompt" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "action" => "inject_reminder_and_retry",
          "contains" => "return json",
          "id" => "json-reminder",
          "kind" => "request_transform",
          "reminder" => "Return only valid JSON."
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/wardwright/simulate", %{
        request: %{
          messages: [%{content: "Please return JSON.", role: "user"}],
          model: "unit-model"
        }
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert get_in(body, ["receipt", "request", "message_count"]) == 2

    assert [
             %{
               "matched" => true,
               "reminder_injected" => true,
               "rule_id" => "json-reminder",
               "source" => %{"engine" => "dune", "status" => "ok"}
             }
           ] = get_in(body, ["receipt", "decision", "policy_actions"])
  end
end
