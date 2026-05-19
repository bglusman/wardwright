defmodule Wardwright.ToolContextTest do
  use ExUnit.Case, async: true

  test "normalizes OpenAI-style tool choice and declared schema evidence" do
    {_request, context} =
      Wardwright.ToolContext.normalize_request(%{
        "messages" => [%{"content" => "file this incident", "role" => "user"}],
        "tool_choice" => %{"function" => %{"name" => "create_ticket"}, "type" => "function"},
        "tools" => [
          %{
            "function" => %{
              "name" => "create_ticket",
              "parameters" => %{"properties" => %{"title" => %{"type" => "string"}}, "type" => "object"}
            },
            "type" => "function"
          }
        ]
      })

    assert context["schema"] == "wardwright.tool_context.v1"
    assert context["phase"] == "planning"
    assert context["confidence"] == "exact"

    assert context["primary_tool"] == %{
             "name" => "create_ticket",
             "namespace" => "openai.function",
             "risk_class" => "unknown",
             "source" => "tool_choice"
           }

    assert get_in(context, ["available_tools", Access.at(0), "schema_hash"]) =~ "sha256:"
    assert Wardwright.ToolContext.cache_key(context) == "openai.function:create_ticket:planning"

    assert Wardwright.ToolContext.matches?(context, %{
             "name" => "create_ticket",
             "namespace" => "openai.function",
             "phase" => "planning"
           })

    refute Wardwright.ToolContext.matches?(context, %{"risk_class" => "write"})
  end

  test "normalizes assistant tool calls without preserving raw arguments or results" do
    raw_argument = ~s({"command":"echo secret-token-123"})
    raw_result = "created secret-token-123"

    context =
      Wardwright.ToolContext.normalize(%{
        "messages" => [
          %{"content" => "prepare the command", "role" => "user"},
          %{
            "content" => nil,
            "role" => "assistant",
            "tool_calls" => [
              %{
                "function" => %{"arguments" => raw_argument, "name" => "run_shell"},
                "id" => "call_secret",
                "type" => "function"
              }
            ]
          },
          %{"content" => raw_result, "role" => "tool", "tool_call_id" => "call_secret"}
        ]
      })

    assert context["phase"] == "result_interpretation"
    assert context["tool_call_id"] == "call_secret"
    assert context["argument_hash"] =~ "sha256:"
    assert context["result_hash"] =~ "sha256:"
    assert context["result_status"] == "unknown"
    assert get_in(context, ["primary_tool", "name"]) == "run_shell"

    refute inspect(context) =~ "secret-token-123"
    refute inspect(context) =~ raw_argument
    refute inspect(context) =~ raw_result
  end

  test "normalizes caller metadata into a bounded contract shape" do
    {request, context} =
      Wardwright.ToolContext.normalize_request(
        %{
          "metadata" => %{
            "tool_context" => %{
              "argument_hash" => "raw secret argument",
              "available_tools" => [%{"name" => "create_pull_request", "namespace" => "mcp.github"}],
              "confidence" => "unexpected",
              "phase" => "planning",
              "primary_tool" => %{
                "name" => "create_pull_request",
                "namespace" => "mcp.github",
                "risk_class" => "write",
                "source" => "unexpected"
              },
              "result_hash" => "raw secret result",
              "schema" => "caller-controlled",
              "tool_call_id" => 42
            }
          }
        },
        trusted_metadata: true
      )

    assert context["schema"] == "wardwright.tool_context.v1"
    assert context["tool_call_id"] == "42"
    assert context["argument_hash"] =~ "sha256:"
    assert context["result_hash"] =~ "sha256:"
    assert context["confidence"] == "declared"
    assert get_in(context, ["primary_tool", "source"]) == "caller_metadata"
    assert get_in(request, ["metadata", "tool_context"]) == context
    refute inspect(context) =~ "raw secret"

    assert Wardwright.ToolContext.matches?(context, %{
             "names" => ["create_pull_request"],
             "namespaces" => ["mcp.github"],
             "risk_classes" => ["read_only", "write"]
           })
  end

  test "ignores caller metadata unless the gateway marks it trusted" do
    request = %{
      "metadata" => %{
        "tool_context" => %{
          "phase" => "planning",
          "primary_tool" => %{"name" => "create_pull_request", "namespace" => "mcp.github"}
        }
      }
    }

    assert Wardwright.ToolContext.normalize(request) == nil

    assert get_in(
             Wardwright.ToolContext.normalize(request, trusted_metadata: true),
             ["primary_tool", "name"]
           ) == "create_pull_request"
  end

  test "does not produce partial cache keys for incomplete identities" do
    refute Wardwright.ToolContext.cache_key(%{
             "phase" => "planning",
             "primary_tool" => %{"name" => "create_pull_request"}
           })
  end
end
