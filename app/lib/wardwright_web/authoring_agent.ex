defmodule WardwrightWeb.AuthoringAgent do
  @moduledoc """
  Narrow policy-authoring assistant boundary for the LiveView workbench spike.

  The first implementation keeps Jido integration behind a small interface so the
  UI, prompt contract, and configuration rules are testable without requiring
  live model credentials in CI.
  """

  alias WardwrightWeb.PolicyAuthoringTools

  @default_base_url "https://opencode.ai/zen/go/v1"
  @default_model "qwen3.6-plus"

  def configured? do
    enabled?() and api_key() not in [nil, ""]
  end

  def status do
    %{
      configured: configured?(),
      backend: "jido_ai",
      base_url: base_url(),
      model: model(),
      tool_mode: "plan_only",
      instructions:
        "Set WARDWRIGHT_AUTHORING_AGENT_ENABLED=1 and WARDWRIGHT_AUTHORING_AGENT_API_KEY or WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE to run live."
    }
  end

  def respond(message, context \\ %{}) when is_binary(message) and is_map(context) do
    prompt = prompt(message, context)

    if configured?() do
      run_jido(prompt)
    else
      {:ok,
       %{
         status: "not_configured",
         content: not_configured_message(prompt),
         prompt_preview: prompt,
         backend: status()
       }}
    end
  end

  def prompt(message, context \\ %{}) when is_binary(message) and is_map(context) do
    selected_model = Map.get(context, :model_id, Wardwright.model_id())
    selected_pattern = Map.get(context, :pattern_id, "unknown")
    selected_recipe = Map.get(context, :recipe_id, "")

    """
    You are Wardwright's in-page model-authoring assistant.

    Your scope is narrow:
    - Help the operator design, refine, validate, simulate, and activate Wardwright models.
    - Prefer small reviewable changes over broad rewrites.
    - Never claim a model is active unless an activation tool result says it is active.
    - Always explain what evidence would convince you and which tool should gather it.
    - Treat deterministic artifacts as source of truth, projections as explanation, and simulations as evidence.
    - Ask for human confirmation before any write-capable action.
    - This spike cannot execute tools directly yet; when a tool is needed,
      name the exact tool and the minimal inputs a human or MCP client should run.

    Current workbench context:
    - active_model_id: #{selected_model}
    - selected_policy_pattern: #{selected_pattern}
    - selected_recipe_id: #{selected_recipe}

    Available Wardwright authoring tools:
    #{tool_manifest()}

    User request:
    #{message}

    Respond with:
    1. A concise answer.
    2. A proposed next tool plan using the exact tool names above.
    3. Any risks, missing information, or human approvals needed.
    """
  end

  defp run_jido(prompt) do
    model_spec = %{provider: :openai, id: model(), base_url: base_url()}

    result =
      Jido.AI.ask(prompt,
        model: model_spec,
        api_key: api_key(),
        max_tokens: max_tokens(),
        temperature: 0.2,
        timeout: timeout_ms()
      )

    case result do
      {:ok, content} when is_binary(content) ->
        {:ok, %{status: "completed", content: content, backend: status()}}

      {:ok, response} ->
        {:ok,
         %{
           status: "completed",
           content: response_text(response),
           raw_response: inspect(response),
           backend: status()
         }}

      {:error, reason} ->
        {:ok,
         %{
           status: "error",
           content: "The Jido authoring agent failed before returning an answer.",
           error: inspect(reason),
           backend: status()
         }}
    end
  rescue
    exception ->
      {:ok,
       %{
         status: "error",
         content: "The Jido authoring agent raised #{inspect(exception.__struct__)}.",
         error: Exception.message(exception),
         backend: status()
       }}
  end

  defp response_text(response) do
    cond do
      is_binary(response) ->
        response

      function_exported?(ReqLLM.Response, :text, 1) ->
        ReqLLM.Response.text(response)

      true ->
        inspect(response)
    end
  rescue
    _ -> inspect(response)
  end

  defp not_configured_message(prompt) do
    """
    Jido authoring agent is installed but not configured for live model calls.

    To try it locally with opencode-go:

        WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
        WARDWRIGHT_AUTHORING_AGENT_BASE_URL=#{@default_base_url}
        WARDWRIGHT_AUTHORING_AGENT_MODEL=#{@default_model}
        WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE=/Users/admin/.config/calciforge/secrets/opencode-api-key

    The prompt below is what the agent would receive:

    #{prompt}
    """
  end

  defp tool_manifest do
    PolicyAuthoringTools.list()
    |> Enum.map(&tool_manifest_line/1)
    |> Enum.join("\n")
  end

  defp tool_manifest_line(%{
         "method" => method,
         "name" => name,
         "path" => path,
         "safety" => safety,
         "when_to_use" => when_to_use
       }) do
    "- #{name}: #{method} #{path}; #{when_to_use}; safety: #{safety}"
  end

  defp enabled? do
    System.get_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))
  end

  defp base_url, do: System.get_env("WARDWRIGHT_AUTHORING_AGENT_BASE_URL", @default_base_url)
  defp model, do: System.get_env("WARDWRIGHT_AUTHORING_AGENT_MODEL", @default_model)

  defp max_tokens do
    "WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS"
    |> System.get_env("1200")
    |> Integer.parse()
    |> case do
      {value, ""} when value > 0 -> value
      _ -> 1200
    end
  end

  defp timeout_ms do
    "WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS"
    |> System.get_env("60000")
    |> Integer.parse()
    |> case do
      {value, ""} when value > 0 -> value
      _ -> 60_000
    end
  end

  defp api_key do
    System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY") || api_key_from_file()
  end

  defp api_key_from_file do
    case System.get_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE") do
      nil ->
        nil

      path ->
        path
        |> File.read()
        |> case do
          {:ok, key} -> String.trim(key)
          {:error, _reason} -> nil
        end
    end
  end
end
