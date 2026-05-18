defmodule WardwrightWeb.AuthoringAgentTest do
  use ExUnit.Case, async: false

  setup do
    Wardwright.reset_config()

    original_client = Application.get_env(:wardwright, :authoring_agent_client, :unset)

    original_env =
      for key <- env_keys(), into: %{} do
        {key, System.get_env(key)}
      end

    Enum.each(env_keys(), &System.delete_env/1)

    on_exit(fn ->
      Wardwright.reset_config()

      Enum.each(env_keys(), fn key ->
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

  test "prompt constrains the in-page agent to Wardwright model authoring logistics" do
    prompt =
      WardwrightWeb.AuthoringAgent.prompt("Make the private route gate easier to review.", %{
        model_id: "wardwright/coding-balanced",
        pattern_id: "route-privacy",
        recipe_id: "private-helpdesk-local-gate"
      })

    assert prompt =~ "Wardwright's in-page model-authoring assistant"
    assert prompt =~ "active_model_id: wardwright/coding-balanced"
    assert prompt =~ "selected_policy_pattern: route-privacy"
    assert prompt =~ "selected_recipe_id: private-helpdesk-local-gate"
    assert prompt =~ "Ask for human confirmation before any write-capable action."
    assert prompt =~ "You may call read-only and draft-only authoring tools"
    assert prompt =~ "draft_wardwright_model is intentionally ephemeral"
    assert prompt =~ "draft_wardwright_model"
    assert prompt =~ "activate_wardwright_model"
    assert prompt =~ "simulate_policy"
    assert prompt =~ "\"tool_calls\""
    assert prompt =~ "pending_drafts: []"
    assert prompt =~ "User request:\nMake the private route gate easier to review."
  end

  test "unconfigured response returns setup help and the prompt preview instead of making a model call" do
    {:ok, response} =
      WardwrightWeb.AuthoringAgent.respond("Draft a safer tool policy.", %{
        model_id: "wardwright/default",
        pattern_id: "tool-governance",
        recipe_id: "tool-governance"
      })

    assert response.status == "not_configured"
    assert response.backend.configured == false
    assert response.backend.can_execute_tools == true
    assert response.backend.tool_access == "read_and_draft_tools"
    assert response.backend.route == "direct"
    assert response.backend.max_tokens == 16_384
    assert response.backend.timeout_ms == 120_000
    assert response.content =~ "Wardwright's authoring assistant is installed but not configured"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_ROUTE=wardwright"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_MODEL=local-authoring-model"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=16384"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=120000"
    assert response.prompt_preview =~ "Draft a safer tool policy."
    assert response.prompt_preview =~ "propose_rule_change"
  end

  test "status reports configured only when explicitly enabled and a key source is present" do
    refute WardwrightWeb.AuthoringAgent.configured?()
    refute WardwrightWeb.AuthoringAgent.status().configured

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    refute WardwrightWeb.AuthoringAgent.configured?()

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")
    assert WardwrightWeb.AuthoringAgent.configured?()
    assert WardwrightWeb.AuthoringAgent.status().configured
    assert WardwrightWeb.AuthoringAgent.status().max_tokens == 16_384
    assert WardwrightWeb.AuthoringAgent.status().timeout_ms == 120_000
  end

  test "local Wardwright route is configured without a provider API key" do
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", Wardwright.model_id())
    System.put_env("WARDWRIGHT_BIND", "0.0.0.0:8797")

    assert WardwrightWeb.AuthoringAgent.configured?()

    status = WardwrightWeb.AuthoringAgent.status()
    assert status.route == "wardwright"
    assert status.base_url == "http://127.0.0.1:8797/v1"
    assert status.model == Wardwright.model_id()

    selected_status = WardwrightWeb.AuthoringAgent.status(%{model_id: Wardwright.model_id()})
    assert selected_status.model == Wardwright.model_id()

    unknown_status = WardwrightWeb.AuthoringAgent.status(%{model_id: "wardwright/cow-guard"})
    assert unknown_status.model == Wardwright.model_id()

    blank_status = WardwrightWeb.AuthoringAgent.status(%{model_id: ""})
    assert blank_status.model == Wardwright.model_id()
  end

  test "local Wardwright route accepts a full v1 bind URL" do
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "dogfood")
    System.put_env("WARDWRIGHT_BIND", "http://127.0.0.1:8797/v1")

    assert WardwrightWeb.AuthoringAgent.status().base_url == "http://127.0.0.1:8797/v1"
  end

  test "local Wardwright route uses the configured authoring backend, not the selected workbench model" do
    on_exit(fn -> Wardwright.reset_config() end)

    cow_config =
      Wardwright.default_config()
      |> Map.put("model_id", "cow-guard")
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})

    assert {:ok, _config} = Wardwright.put_model_config(cow_config)

    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.CapturingAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", Wardwright.model_id())
    System.put_env("WARDWRIGHT_BIND", "127.0.0.1:8797")

    {:ok, response} =
      WardwrightWeb.AuthoringAgent.respond("Review the current model.", %{
        model_id: "wardwright/cow-guard"
      })

    assert response.status == "completed"
    assert response.backend.model == Wardwright.model_id()
    assert response.content =~ "model=#{Wardwright.model_id()}"
    assert response.content =~ "base_url=http://127.0.0.1:8797/v1"
    assert response.content =~ "api_key=wardwright-local"
  end

  test "local Wardwright route falls back when the selected workbench model is blank" do
    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.CapturingAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", Wardwright.model_id())
    System.put_env("WARDWRIGHT_BIND", "127.0.0.1:8797")

    {:ok, response} =
      WardwrightWeb.AuthoringAgent.respond("Review the current model.", %{
        model_id: ""
      })

    assert response.status == "completed"
    assert response.backend.model == Wardwright.model_id()
    assert response.content =~ "model=#{Wardwright.model_id()}"
    assert response.content =~ "provider_model=#{Wardwright.model_id()}"
  end

  test "local Wardwright route avoids internal-only models when choosing a backing model" do
    on_exit(fn -> Wardwright.reset_config() end)

    internal_config =
      Wardwright.default_config()
      |> Map.put("auth", %{"unkeyed_model_access" => "internal"})

    public_config =
      Wardwright.default_config()
      |> Map.put("model_id", "local-fast-draft-test")
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})
      |> Map.put("requires_api_key", true)

    assert {:ok, _config} = Wardwright.put_config(internal_config)
    assert {:ok, _config} = Wardwright.put_model_config(public_config)

    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.CapturingAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_BIND", "127.0.0.1:8797")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", "local-fast-draft-test")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY", "local-model-key")

    {:ok, response} =
      WardwrightWeb.AuthoringAgent.respond("Review the current model.", %{
        model_id: Wardwright.model_id()
      })

    assert response.status == "completed"
    assert response.backend.model == "local-fast-draft-test"
    assert response.content =~ "model=local-fast-draft-test"
    assert response.content =~ "api_key=local-model-key"
  end

  test "local Wardwright route does not use direct provider keys as local model keys" do
    on_exit(fn -> Wardwright.reset_config() end)

    keyed_config =
      Wardwright.default_config()
      |> Map.put("model_id", "keyed-local")
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})
      |> Map.put("requires_api_key", true)

    internal_config =
      Wardwright.default_config()
      |> Map.put("auth", %{"unkeyed_model_access" => "internal"})

    assert {:ok, _config} = Wardwright.put_config(internal_config)
    assert {:ok, _config} = Wardwright.put_model_config(keyed_config)

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "provider-key")

    refute WardwrightWeb.AuthoringAgent.configured?(%{model_id: "keyed-local"})
  end

  test "local Wardwright route validates explicit model env override against registered models" do
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", "not-registered")

    refute WardwrightWeb.AuthoringAgent.configured?()

    local_config =
      Wardwright.default_config()
      |> Map.put("model_id", "local-fast-draft-test")
      |> Map.put("auth", %{"unkeyed_model_access" => "public"})

    assert {:ok, _config} = Wardwright.put_model_config(local_config)

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", "local-fast-draft-test")

    assert WardwrightWeb.AuthoringAgent.configured?()
    assert WardwrightWeb.AuthoringAgent.status().model == "local-fast-draft-test"
  end

  test "configured response explains token-limited reasoning-only provider responses" do
    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.LengthLimitedAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")

    {:ok, response} = WardwrightWeb.AuthoringAgent.respond("Make a cow model.")

    assert response.status == "error"
    assert response.finish_reason == :length
    assert response.provider_usage == %{output_tokens: 20, is_byok: true}
    assert response.content =~ "reasoning metadata but no final answer"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS"
    assert response.content =~ "no extra Wardwright request-body flag"
  end

  test "configured response exposes sanitized provider errors in the visible answer" do
    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.FailingAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")

    {:ok, response} = WardwrightWeb.AuthoringAgent.respond("Make a cow model.")

    assert response.status == "error"
    assert response.content =~ "Provider error:"
    assert response.content =~ "upstream_timeout"
    refute response.content =~ "secret-token"
  end

  test "configured response executes read and draft tool calls returned by the model" do
    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.DraftingAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")

    {:ok, response} = WardwrightWeb.AuthoringAgent.respond("Make a cow model.")

    assert response.status == "completed"
    assert response.content =~ "Drafted a cow-focused model."
    assert response.content =~ "Executed authoring tools:"

    assert response.content =~
             "draft_wardwright_model: executed (draft cow-guard, 0 validation errors, 0 warnings, not active)"

    assert response.content =~ "Needs human approval:"
    assert response.content =~ "Review and activate the draft from the workbench"

    assert [%{"name" => "draft_wardwright_model", "status" => "executed", "result" => result}] =
             response.tool_results

    assert get_in(result, ["artifact", "model_id"]) == "cow-guard"
    assert get_in(result, ["validation", "errors"]) == []
  end

  test "configured response refuses approval-gated tool calls" do
    Application.put_env(
      :wardwright,
      :authoring_agent_client,
      __MODULE__.ActivatingAuthoringClient
    )

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY", "test-key")

    {:ok, response} = WardwrightWeb.AuthoringAgent.respond("Activate this immediately.")

    assert response.status == "completed"
    assert response.content =~ "activate_wardwright_model: skipped"

    assert [%{"name" => "activate_wardwright_model", "status" => "skipped", "result" => result}] =
             response.tool_results

    assert result["reason"] =~ "explicit user approval"
  end

  defmodule LengthLimitedAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:ok,
       %ReqLLM.Response{
         id: "test-response",
         model: "kimi-k2.6",
         context: nil,
         message: %ReqLLM.Message{role: :assistant, content: []},
         finish_reason: :length,
         usage: %{output_tokens: 20, is_byok: true}
       }}
    end
  end

  defmodule DraftingAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:ok,
       Jason.encode!(%{
         "answer" => "Drafted a cow-focused model.",
         "tool_calls" => [
           %{
             "name" => "draft_wardwright_model",
             "arguments" => %{
               "model_id" => "cow-guard",
               "targets" => [%{"model" => "local-ollama", "context_window" => 8192}],
               "route" => %{
                 "type" => "dispatcher",
                 "id" => "dispatcher.cow",
                 "models" => ["local-ollama"]
               },
               "stream_rules" => [
                 %{
                   "id" => "cow-art",
                   "phase" => "response.streaming",
                   "pattern" => "\\bmoo+\\b",
                   "action" => "rewrite_chunk",
                   "replacement" => "moo\n(^__^)\n(oo)\\\\_______"
                 }
               ]
             }
           }
         ],
         "approval_needed" => ["activate_wardwright_model after review"]
       })}
    end
  end

  defmodule FailingAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:error, {:upstream_timeout, "Bearer secret-token"}}
    end
  end

  defmodule ActivatingAuthoringClient do
    def generate_text(_prompt, _opts) do
      {:ok,
       Jason.encode!(%{
         "answer" => "I prepared an activation.",
         "tool_calls" => [
           %{"name" => "activate_wardwright_model", "arguments" => %{"artifact" => %{}}}
         ]
       })}
    end
  end

  defmodule CapturingAuthoringClient do
    def generate_text(_prompt, opts) do
      {:ok,
       Jason.encode!(%{
         "answer" =>
           "model=#{opts[:model].id} provider_model=#{opts[:model].model} base_url=#{opts[:model].base_url} api_key=#{opts[:api_key]}",
         "tool_calls" => []
       })}
    end
  end

  defp env_keys do
    [
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
  end
end
