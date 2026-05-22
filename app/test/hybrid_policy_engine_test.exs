defmodule Wardwright.HybridPolicyEngineTest do
  use Wardwright.RouterCase

  alias Wardwright.Policy.Engine
  alias Wardwright.PolicySandbox.DuneSnippetRegistry

  test "hybrid policy engine propagates nested blocking actions" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "engine" => "hybrid",
          "engines" => [
            %{
              "engine" => "primitive",
              "rules" => [%{"action" => "block", "contains" => "deny me", "id" => "primitive-deny"}]
            }
          ],
          "id" => "hybrid-block",
          "kind" => "route_gate"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "please deny me", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 429
    body = JSON.decode!(conn.resp_body)
    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()

    assert [
             %{
               "action" => "block",
               "action_schema" => "wardwright.policy_action.v1",
               "conflict_key" => "terminal_decision",
               "effect_type" => "terminal",
               "kind" => "route_gate",
               "rule_id" => "primitive-deny",
               "source" => %{"engine" => "dune", "status" => "ok", "type" => "engine"}
             }
           ] = get_in(receipt, ["decision", "policy_actions"])
  end

  test "hybrid policy reports policy blocks separately from engine failures" do
    assert %{
             "action" => "block",
             "actions" => [
               %{
                 "action" => "block",
                 "action_schema" => "wardwright.policy_action.v1",
                 "effect_type" => "terminal",
                 "rule_id" => "primitive-deny",
                 "source" => %{"engine" => "dune", "status" => "ok", "type" => "engine"}
               }
             ],
             "engine" => "hybrid",
             "result_schema" => "wardwright.policy_result.v1",
             "status" => "ok"
           } =
             Engine.evaluate(
               %{
                 "engine" => "hybrid",
                 "engines" => [
                   %{
                     "engine" => "primitive",
                     "rules" => [
                       %{"action" => "block", "contains" => "deny me", "id" => "primitive-deny"}
                     ]
                   }
                 ]
               },
               %{"request_text" => "please deny me"}
             )
  end

  test "hybrid policy can compose workspace Dune snippets by id" do
    original_workspace = Application.get_env(:wardwright, :dune_snippet_workspace_dir)
    workspace_dir = temp_workspace_dir("wardwright-hybrid-dune-snippets")
    Application.put_env(:wardwright, :dune_snippet_workspace_dir, workspace_dir)

    on_exit(fn ->
      File.rm_rf!(workspace_dir)

      case original_workspace do
        nil -> Application.delete_env(:wardwright, :dune_snippet_workspace_dir)
        value -> Application.put_env(:wardwright, :dune_snippet_workspace_dir, value)
      end
    end)

    assert {:ok, _saved} =
             DuneSnippetRegistry.save(%{
               "id" => "workspace.block-risk",
               "source" => """
               if String.contains?(input["request_text"], "deny me") do
                 %{"action" => "block", "reason" => "workspace snippet matched"}
               else
                 %{"action" => "allow"}
               end
               """
             })

    assert %{
             "action" => "block",
             "actions" => [
               %{
                 "action" => "block",
                 "rule_id" => "saved-dune",
                 "source" => %{"engine" => "dune", "status" => "ok", "type" => "engine"}
               }
             ],
             "engine" => "hybrid",
             "status" => "ok"
           } =
             Engine.evaluate(
               %{
                 "engine" => "hybrid",
                 "engines" => [%{"engine" => "dune", "id" => "saved-dune", "snippet_id" => "workspace.block-risk"}],
                 "id" => "saved-dune"
               },
               %{"request_text" => "please deny me"}
             )
  end

  test "policy engine errors fail closed before provider invocation" do
    config =
      unit_policy_config()
      |> Map.put("governance", [
        %{
          "engine" => "wasm",
          "id" => "unavailable-wasm-policy",
          "kind" => "route_gate"
        }
      ])

    assert call(:post, "/__test/config", config).status == 200

    conn =
      call(:post, "/v1/chat/completions", %{
        messages: [%{content: "hello", role: "user"}],
        model: "unit-model"
      })

    assert conn.status == 429
    body = JSON.decode!(conn.resp_body)

    assert get_in(body, ["wardwright", "status"]) == "policy_failed_closed"
    receipt = body |> get_in(["wardwright", "receipt_id"]) |> Wardwright.ReceiptStore.get()

    assert [
             %{
               "action" => "block",
               "kind" => "route_gate",
               "rule_id" => "unavailable-wasm-policy"
             }
           ] = get_in(receipt, ["decision", "policy_actions"])
  end

  defp temp_workspace_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end
end
