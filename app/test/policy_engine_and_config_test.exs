defmodule Wardwright.PolicyEngineAndConfigTest do
  use Wardwright.RouterCase

  alias Wardwright.Policy.Engine

  test "policy engine adapters fail closed for unsupported WASM and Dune failures" do
    assert %{"action" => "block", "engine" => "wasm", "status" => "error"} =
             Engine.evaluate(%{"engine" => "wasm"}, %{})

    assert %{"action" => "block", "engine" => "dune", "status" => "error"} =
             Engine.evaluate(
               %{"engine" => "dune", "source" => "raise \"nope\""},
               %{}
             )
  end

  test "Dune policy engine receives request context through input binding" do
    assert %{
             "action" => "block",
             "actions" => [
               %{
                 "action" => "block",
                 "policy_status" => "ok",
                 "source" => %{"engine" => "dune", "status" => "ok", "type" => "engine"}
               }
             ],
             "engine" => "dune",
             "status" => "ok"
           } =
             Engine.evaluate(
               %{
                 "engine" => "dune",
                 "source" => ~S"""
                 %{"action" => if(input["request_text"] == "deny", do: "block", else: "allow")}
                 """
               },
               %{"request_text" => "deny"}
             )
  end

  test "Dune policy engine still supports legacy context placeholder snippets" do
    assert %{
             "action" => "block",
             "actions" => [%{"action" => "block", "message" => "deny", "policy_status" => "ok"}],
             "engine" => "dune"
           } =
             Engine.evaluate(
               %{
                 "engine" => "dune",
                 "source" => ~S"""
                 %{"action" => "block", "message" => __WARDWRIGHT_CONTEXT__["request_text"]}
                 """
               },
               %{"request_text" => "deny"}
             )
  end

  test "test config rejects invalid route graph shapes" do
    prefixed = unit_policy_config() |> Map.put("model_id", "wardwright/unit-model")
    conn = call(:post, "/__test/config", prefixed)
    assert conn.status == 400

    assert Jason.decode!(conn.resp_body)["error"]["message"] ==
             "model_id must be unprefixed"

    duplicate =
      unit_policy_config()
      |> Map.put("targets", [
        %{"context_window" => 8, "model" => "tiny/model"},
        %{"context_window" => 16, "model" => "tiny/model"}
      ])

    conn = call(:post, "/__test/config", duplicate)
    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"]["message"] == "duplicate target tiny/model"

    unknown_ref =
      unit_policy_config()
      |> Map.put("route_root", "bad-dispatcher")
      |> Map.put("dispatchers", [
        %{"id" => "bad-dispatcher", "models" => ["tiny/model", "missing/model"]}
      ])

    conn = call(:post, "/__test/config", unknown_ref)
    assert conn.status == 400

    assert Jason.decode!(conn.resp_body)["error"]["message"] ==
             "dispatcher bad-dispatcher references unknown target missing/model"

    zero_weight =
      unit_policy_config()
      |> Map.put("route_root", "bad-alloy")
      |> Map.put("alloys", [
        %{
          "constituents" => [%{"model" => "tiny/model", "weight" => 0}, %{"model" => "medium/model", "weight" => 10}],
          "id" => "bad-alloy",
          "strategy" => "weighted"
        }
      ])

    conn = call(:post, "/__test/config", zero_weight)
    assert conn.status == 400

    assert Jason.decode!(conn.resp_body)["error"]["message"] ==
             "alloy bad-alloy target tiny/model weight must be positive"
  end

  test "test config endpoint is disabled unless explicitly allowed" do
    previous = Application.get_env(:wardwright, :allow_test_config, false)
    Application.put_env(:wardwright, :allow_test_config, false)
    on_exit(fn -> Application.put_env(:wardwright, :allow_test_config, previous) end)

    conn = call(:post, "/__test/config", unit_policy_config())
    assert conn.status == 404
    assert Jason.decode!(conn.resp_body)["error"]["code"] == "not_found"
  end
end
