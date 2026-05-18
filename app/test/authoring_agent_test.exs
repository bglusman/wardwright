defmodule WardwrightWeb.AuthoringAgentTest do
  use ExUnit.Case, async: false

  setup do
    original_env =
      for key <- env_keys(), into: %{} do
        {key, System.get_env(key)}
      end

    Enum.each(env_keys(), &System.delete_env/1)

    on_exit(fn ->
      Enum.each(env_keys(), fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)
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
    assert prompt =~ "This spike cannot execute tools directly yet"
    assert prompt =~ "draft_wardwright_model"
    assert prompt =~ "activate_wardwright_model"
    assert prompt =~ "simulate_policy"
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
    assert response.backend.tool_mode == "plan_only"
    assert response.content =~ "Jido authoring agent is installed but not configured"
    assert response.content =~ "WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE"
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
  end

  defp env_keys do
    [
      "WARDWRIGHT_AUTHORING_AGENT_ENABLED",
      "WARDWRIGHT_AUTHORING_AGENT_BASE_URL",
      "WARDWRIGHT_AUTHORING_AGENT_MODEL",
      "WARDWRIGHT_AUTHORING_AGENT_API_KEY",
      "WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE",
      "WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS",
      "WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS"
    ]
  end
end
