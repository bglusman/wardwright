defmodule Wardwright.LocalGemmaAuthoringRecipeTest do
  use ExUnit.Case, async: false

  @env_keys [
    "WARDWRIGHT_AUTHORING_AGENT_ENABLED",
    "WARDWRIGHT_AUTHORING_AGENT_CONFIG_FILE",
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

  setup do
    Wardwright.reset_config()

    original_env =
      for key <- @env_keys, into: %{} do
        {key, System.get_env(key)}
      end

    Enum.each(@env_keys, &System.delete_env/1)

    on_exit(fn ->
      Wardwright.reset_config()

      Enum.each(@env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)
    end)

    :ok
  end

  test "local Gemma authoring recipe keeps route and policy behavior pass-through while enabling Jido dogfood JSON" do
    config = local_gemma_authoring_config()

    assert config["model_id"] == "local-gemma-authoring"
    assert config["governance"] == []
    assert config["stream_rules"] == []
    assert config["prompt_transforms"] == %{}
    assert get_in(config, ["tool_mediation", "rules"]) == []

    assert [
             %{
               "context_window" => 131_072,
               "model" => "ollama/gemma4:26b-a4b-it-q4_K_M",
               "provider_kind" => "ollama"
             }
           ] = config["targets"]

    assert get_in(config, ["structured_output", "schemas", "authoring_tool_plan_v1", "type"]) ==
             "object"

    draft = WardwrightWeb.PolicyAuthoringDrafts.wardwright_model_draft(config)
    assert get_in(draft, ["validation", "errors"]) == []
    assert get_in(draft, ["artifact", "description"]) =~ "Local Gemma 4 26B"
    assert get_in(draft, ["artifact", "route_root"]) == "dispatcher.local-gemma-authoring"

    assert {:ok, activated} = WardwrightWeb.PolicyAuthoringDrafts.activate_wardwright_model(config)
    assert get_in(activated, ["artifact", "description"]) =~ "Local Gemma 4 26B"
    assert get_in(activated, ["artifact", "route_root"]) == "dispatcher.local-gemma-authoring"

    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "1")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "wardwright")
    System.put_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", "local-gemma-authoring")

    assert WardwrightWeb.AuthoringAgent.configured?()

    status = WardwrightWeb.AuthoringAgent.status()
    assert status.backend == "jido_ai"
    assert status.model == "local-gemma-authoring"
    assert status.route == "wardwright"
    assert status.required_structured_schema == "authoring_tool_plan_v1"
  end

  defp local_gemma_authoring_config do
    "../../config/local-gemma-authoring.model.json"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> JSON.decode!()
  end
end
