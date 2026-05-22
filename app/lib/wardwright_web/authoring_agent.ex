defmodule WardwrightWeb.AuthoringAgent do
  @moduledoc """
  Narrow policy-authoring assistant boundary for the LiveView workbench spike.

  The first implementation keeps Jido integration behind a small interface so the
  UI, prompt contract, and configuration rules are testable without requiring
  live model credentials in CI.
  """

  alias Wardwright.PolicySandbox.DuneSnippetRegistry
  alias WardwrightWeb.PolicyArtifactValidator
  alias WardwrightWeb.PolicyAuthoringDrafts
  alias WardwrightWeb.PolicyAuthoringTools

  require Logger

  @default_base_url "https://opencode.ai/zen/go/v1"
  @default_model "qwen3.6-plus"
  @default_max_tokens 16_384
  @default_timeout_ms 120_000
  @required_authoring_schema "authoring_tool_plan_v1"
  @authoring_config_file_env "WARDWRIGHT_AUTHORING_AGENT_CONFIG_FILE"

  def configured?(context \\ %{}) do
    enabled?() and
      if local_wardwright_route?(),
        do: requested_local_authoring_model_config(context) != nil,
        else: api_key() not in [nil, ""]
  end

  def status(context \\ %{}) do
    %{
      backend: "jido_ai",
      base_url: base_url(),
      can_execute_tools: true,
      configured: configured?(context),
      instructions:
        "Set WARDWRIGHT_AUTHORING_AGENT_ENABLED=1, WARDWRIGHT_AUTHORING_AGENT_ROUTE=wardwright, and WARDWRIGHT_AUTHORING_AGENT_MODEL to dogfood a specific local Wardwright /v1 model. Dogfood mode requires that local model to expose the #{@required_authoring_schema} structured-output schema so authoring tool plans are governed by Wardwright before execution. If that local model requires keyed access, set WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY or WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY_FILE. For direct provider calls, set WARDWRIGHT_AUTHORING_AGENT_API_KEY or WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE. Reasoning-heavy coding models may also need WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS and WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS.",
      max_tokens: max_tokens(),
      model: model(context),
      required_structured_schema: if(local_wardwright_route?(), do: @required_authoring_schema),
      route: authoring_route(),
      timeout_ms: timeout_ms(),
      tool_access: "read_and_draft_tools"
    }
  end

  def respond(message, context \\ %{}) when is_binary(message) and is_map(context) do
    prompt = prompt(message, context)

    if configured?(context) do
      run_jido(prompt, message, context)
    else
      {:ok,
       %{
         backend: status(context),
         content: not_configured_message(prompt),
         prompt_preview: prompt,
         status: "not_configured"
       }}
    end
  end

  def prompt(message, context \\ %{}) when is_binary(message) and is_map(context) do
    selected_model = selected_model_id(context)
    selected_pattern = Map.get(context, :pattern_id, "unknown")
    selected_recipe = Map.get(context, :recipe_id, "")
    simulator_user_input = Map.get(context, :simulator_user_input, "")
    simulator_model_response = Map.get(context, :simulator_model_response, "")
    simulator_response_attempts = Map.get(context, :simulator_response_attempts, [])

    """
    You are Wardwright's in-page model-authoring assistant.

    Your scope is narrow:
    - Help the operator design, refine, validate, simulate, and activate Wardwright models.
    - Prefer small reviewable changes over broad rewrites.
    - Never claim a model is active unless an activation tool result says it is active.
    - Treat deterministic artifacts as source of truth, projections as explanation, and simulations as evidence.
    - Ask for human confirmation before any durable write-capable action.
    - Be skeptical of your own draft. A plausible artifact is not enough.
    - Draft-only tools are safe to call immediately; they create reviewable
      artifacts but do not activate models or persist policy changes.
    - You may call read-only and draft-only authoring tools by returning a
      machine-readable tool_calls array. Wardwright will execute those calls and
      return the results for review.
    - When the user asks you to make, create, draft, build, add, update, or
      change a Wardwright model, policy, rule, guard, route, scenario, or Dune
      snippet, a tool call is required in this turn. Do not answer with only a
      prose design or approval checklist.
    - draft_wardwright_model is intentionally ephemeral. It does not register a
      model, does not update /v1/models, and only creates a reviewable draft for
      the current workbench session.
    - draft_wardwright_model and other draft-only/read-only tools do not require
      user approval. Use them immediately when they make the answer concrete.
    - Never request silent activation, deletion, scenario persistence, or any
      other durable write. For those, explain the approval needed and name the
      exact tool a human should run after review.
    - When the user asks for changed behavior, do not draft a route-only model.
      Include at least one concrete behavior primitive: governance,
      stream_rules, prompt_transforms, structured_output, or a Dune-backed rule.
      Prefer top-level fields named governance, stream_rules, prompt_transforms,
      and structured_output. If you use a behavior_primitives wrapper,
      Wardwright will normalize it, but top-level fields are clearer.
      If Wardwright cannot express the requested behavior exactly yet, say that
      clearly and draft the closest reviewable approximation with limitations.
    - For regex semantics, use stream_rules[].regex. Use stream_rules[].pattern
      only for literal substring replacement.
    - Before drafting, inspect the current surface with explain_projection when
      the request depends on an existing pattern or model.
    - After drafting or proposing a change, validate it and simulate at least
      one matching case and one non-matching control case when the available
      tools can express those cases.
    - If a simulation does not exercise the behavior you changed, say so plainly
      and propose the missing scenario instead of claiming success.
    - Do not mention proxy names, provider plumbing, base URLs, or transport
      layers in the operator-facing answer unless the user explicitly asks about
      them or a tool result requires it. Focus on the Wardwright artifact and
      its observable behavior.
    - Report validation warnings, coverage gaps, and simulator limitations in
      your answer. Do not bury them in next steps.
    - Good authoring tasks include: request reminders that trigger on user text,
      response stream rewrites or retries, route/model switching, structured
      output repair, tool-use constraints, history thresholds, and Dune snippet
      sketches. Pick the smallest Wardwright primitive that can express the
      requested behavior.

    Current workbench context:
    - active_model_id: #{selected_model}
    - selected_policy_pattern: #{selected_pattern}
    - selected_recipe_id: #{selected_recipe}
    - pending_drafts: #{JSON.encode!(Map.get(context, :pending_drafts, []))}

    Current simulator turn:
    - user_input: #{JSON.encode!(simulator_user_input)}
    - raw_model_output_or_stream: #{JSON.encode!(simulator_model_response)}
    - retry_attempt_outputs: #{JSON.encode!(simulator_response_attempts)}

    Available Wardwright authoring tools:
    #{tool_manifest()}

    User request:
    #{message}

    Prefer this JSON shape when a tool call would make your answer concrete:
    {
      "answer": "concise explanation for the operator",
      "tool_calls": [
        {"name": "draft_wardwright_model", "arguments": {"model_id": "example", "...": "..."}}
      ],
      "next_steps": ["review and activate from the workbench if the draft matches the request"]
    }

    If no tool is needed, return the same JSON shape with an empty tool_calls
    array. Do not wrap JSON in markdown fences.
    """
  end

  defp run_jido(prompt, user_message, context) do
    model_id = model(context)
    provider_base_url = base_url()
    model_spec = %{base_url: provider_base_url, id: model_id, model: model_id, provider: :openai}
    started_at = System.monotonic_time(:millisecond)
    backend_status = status(context)

    Logger.info(
      "authoring agent provider request started model=#{model_id} base_url=#{provider_base_url} max_tokens=#{max_tokens()} timeout_ms=#{timeout_ms()}"
    )

    result = request_authoring_model(prompt, model_spec)

    case result do
      {:ok, response} ->
        Logger.info(
          "authoring agent provider request completed elapsed_ms=#{elapsed_ms(started_at)} finish_reason=#{inspect(response_finish_reason(response))}"
        )

        content = response_text(response)

        if needs_authoring_tool_retry?(content, user_message) do
          Logger.info(
            "authoring agent provider response omitted required draft tool call; retrying with targeted feedback"
          )

          retry_prompt = authoring_tool_retry_prompt(prompt, content)
          retry_started_at = System.monotonic_time(:millisecond)

          case request_authoring_model(retry_prompt, model_spec) do
            {:ok, retry_response} ->
              Logger.info(
                "authoring agent provider retry completed elapsed_ms=#{elapsed_ms(retry_started_at)} finish_reason=#{inspect(response_finish_reason(retry_response))}"
              )

              retry_response
              |> response_text()
              |> answer_with_tool_execution(
                user_message,
                backend: backend_status,
                finish_reason: response_finish_reason(retry_response),
                provider_usage: response_usage(retry_response)
              )

            {:error, retry_reason} ->
              error_summary = safe_error_summary(retry_reason)

              Logger.warning(
                "authoring agent provider retry failed elapsed_ms=#{elapsed_ms(retry_started_at)} error=#{error_summary}"
              )

              content
              |> answer_with_tool_execution(
                user_message,
                backend: backend_status,
                error: error_summary,
                finish_reason: response_finish_reason(response),
                provider_usage: response_usage(response)
              )
          end
        else
          content
          |> answer_with_tool_execution(
            user_message,
            backend: backend_status,
            finish_reason: response_finish_reason(response),
            provider_usage: response_usage(response)
          )
        end

      {:error, reason} ->
        error_summary = safe_error_summary(reason)

        Logger.warning(
          "authoring agent provider request failed elapsed_ms=#{elapsed_ms(started_at)} error=#{error_summary}"
        )

        {:ok,
         %{
           backend: backend_status,
           content:
             "The Wardwright authoring assistant failed before returning an answer.\n\nProvider error: #{error_summary}",
           error: error_summary,
           status: "error"
         }}
    end
  rescue
    exception ->
      Logger.error(
        "authoring agent provider request raised exception=#{inspect(exception.__struct__)} error=#{Exception.message(exception)}"
      )

      {:ok,
       %{
         backend: status(context),
         content: "The Wardwright authoring assistant raised #{inspect(exception.__struct__)}.",
         error: Exception.message(exception),
         status: "error"
       }}
  end

  defp request_authoring_model(prompt, model_spec) do
    jido_client().generate_text(prompt,
      model: model_spec,
      api_key: api_key_for_request(),
      max_tokens: max_tokens(),
      temperature: 0.2,
      timeout: timeout_ms()
    )
  end

  defp elapsed_ms(started_at), do: System.monotonic_time(:millisecond) - started_at

  defp needs_authoring_tool_retry?(content, user_message) do
    with true <- authoring_action_requested?(user_message),
         {:ok, %{"tool_calls" => []}} <- decode_tool_plan(content) do
      true
    else
      _ -> false
    end
  end

  defp authoring_tool_retry_prompt(original_prompt, prior_content) do
    """
    #{original_prompt}

    Previous assistant answer did not include an executable authoring tool call:

    #{String.slice(prior_content || "", 0, 4_000)}

    Retry now. The user asked to create or change a Wardwright model, policy, or
    rule, so return only valid JSON with at least one draft-only or read-only
    tool call. For a new or changed model, use draft_wardwright_model. Do not
    ask for approval before draft_wardwright_model; it is reviewable and not
    active.
    """
  end

  defp answer_with_tool_execution(content, user_message, extras) do
    content = String.trim(content || "")

    case decode_tool_plan(content) do
      {:ok, plan} ->
        answer_text = plan |> Map.get("answer", content) |> to_string() |> String.trim()
        tool_calls = Map.get(plan, "tool_calls", [])
        tool_results = execute_tool_calls(tool_calls)

        if tool_calls == [] and authoring_action_requested?(user_message) do
          answer(
            no_tool_executed_for_authoring_request_message(answer_text),
            Keyword.put(extras, :status, "error")
          )
        else
          next_steps =
            tool_results
            |> add_default_next_steps(Map.get(plan, "next_steps", Map.get(plan, "approval_needed", [])))

          rendered = render_tool_answer(answer_text, tool_results, next_steps)

          answer(rendered, Keyword.put(extras, :tool_results, tool_results))
        end

      :error ->
        if looks_like_tool_plan?(content) do
          answer(unreadable_tool_plan_message(), Keyword.put(extras, :status, "error"))
        else
          answer(content, extras)
        end
    end
  end

  defp authoring_action_requested?(message) when is_binary(message) do
    normalized = String.downcase(message)

    Regex.match?(
      ~r/\b(make|create|draft|build|add|update|change|modify|write|generate)\b/,
      normalized
    ) and
      Regex.match?(
        ~r/\b(model|policy|rule|guard|rewrite|route|scenario|snippet|behavior|behaviour)\b/,
        normalized
      )
  end

  defp no_tool_executed_for_authoring_request_message(answer_text) do
    """
    #{answer_text}

    No authoring tool was executed. For a request to create or change a Wardwright model, the assistant must return a draft_wardwright_model or other draft-only tool call so Wardwright can validate and show a reviewable draft. Please retry, or ask for a design-only explanation explicitly.
    """
  end

  defp answer(content, extras) do
    content = String.trim(content)
    status = Keyword.get(extras, :status, "completed")

    if content == "" do
      {:ok,
       %{
         backend: status(),
         content: empty_answer_message(extras),
         status: "error"
       }
       |> Map.merge(Map.new(extras))}
    else
      {:ok,
       %{
         backend: status(),
         content: content,
         status: status
       }
       |> Map.merge(Map.new(extras))}
    end
  end

  @auto_tool_names MapSet.new([
                     "draft_wardwright_model",
                     "evaluate_dune_snippet",
                     "explain_projection",
                     "list_dune_snippets",
                     "propose_rule_change",
                     "simulate_policy",
                     "validate_policy_artifact"
                   ])

  defp decode_tool_plan(content) do
    content
    |> candidate_json_strings()
    |> Enum.find_value(:error, fn candidate ->
      case JSON.decode(candidate) do
        {:ok, %{"tool_calls" => calls} = plan} when is_list(calls) -> {:ok, plan}
        _ -> nil
      end
    end)
  end

  defp candidate_json_strings(content) do
    fenced =
      ~r/```(?:json)?\s*([\s\S]*?)\s*```/
      |> Regex.scan(content, capture: :all_but_first)
      |> List.flatten()

    [content | fenced]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp looks_like_tool_plan?(content) do
    String.contains?(content, "\"tool_calls\"")
  end

  defp unreadable_tool_plan_message do
    """
    The authoring assistant returned a tool plan, but Wardwright could not parse it as valid JSON.

    No tool was executed. Ask again for a draft model, or provide a valid JSON object with an answer and a tool_calls array.
    """
  end

  defp execute_tool_calls(calls) when is_list(calls) do
    calls
    |> Enum.take(4)
    |> Enum.map(&execute_tool_call/1)
  end

  defp execute_tool_calls(_calls), do: []

  defp execute_tool_call(%{"name" => name} = call) when is_binary(name) do
    arguments = Map.get(call, "arguments", %{})

    cond do
      not MapSet.member?(@auto_tool_names, name) ->
        skipped_tool(
          name,
          "requires explicit user approval or is not available to the embedded assistant"
        )

      not is_map(arguments) ->
        skipped_tool(name, "arguments must be a JSON object")

      true ->
        safe_run_auto_tool(name, arguments)
    end
  end

  defp execute_tool_call(_call), do: skipped_tool("unknown", "tool call must include a string name")

  defp safe_run_auto_tool(name, arguments) do
    run_auto_tool(name, arguments)
  rescue
    exception ->
      tool_result(name, "error", %{
        "error" => Exception.message(exception),
        "exception" => inspect(exception.__struct__)
      })
  end

  defp run_auto_tool("draft_wardwright_model", arguments) do
    tool_result(
      "draft_wardwright_model",
      "executed",
      PolicyAuthoringDrafts.wardwright_model_draft(arguments)
    )
  end

  defp run_auto_tool("evaluate_dune_snippet", arguments) do
    case DuneSnippetRegistry.evaluate(arguments) do
      {:ok, result} -> tool_result("evaluate_dune_snippet", "executed", result)
      {:error, message} -> tool_result("evaluate_dune_snippet", "error", %{"error" => message})
    end
  end

  defp run_auto_tool("explain_projection", arguments) do
    pattern_id = Map.get(arguments, "pattern_id")

    if pattern_id in Wardwright.PolicyProjection.pattern_ids() do
      tool_result("explain_projection", "executed", %{
        "projection" => Wardwright.PolicyProjection.projection(pattern_id)
      })
    else
      tool_result("explain_projection", "error", %{"error" => "policy pattern not found"})
    end
  end

  defp run_auto_tool("list_dune_snippets", _arguments) do
    tool_result("list_dune_snippets", "executed", DuneSnippetRegistry.list())
  end

  defp run_auto_tool("propose_rule_change", arguments) do
    tool_result(
      "propose_rule_change",
      "executed",
      PolicyAuthoringDrafts.propose_rule_change(arguments)
    )
  end

  defp run_auto_tool("simulate_policy", arguments) do
    pattern_id = Map.get(arguments, "pattern_id")

    if pattern_id in Wardwright.PolicyProjection.pattern_ids() do
      tool_result("simulate_policy", "executed", %{
        "data" => Wardwright.PolicyProjection.simulations(pattern_id)
      })
    else
      tool_result("simulate_policy", "error", %{"error" => "policy pattern not found"})
    end
  end

  defp run_auto_tool("validate_policy_artifact", arguments) do
    artifact = Map.get(arguments, "artifact", %{})
    source = if artifact == %{}, do: "current_config", else: "submitted"

    tool_result(
      "validate_policy_artifact",
      "executed",
      PolicyArtifactValidator.validate(artifact, source: source)
    )
  end

  defp skipped_tool(name, reason) do
    tool_result(name, "skipped", %{"reason" => reason})
  end

  defp tool_result(name, status, result) do
    %{"name" => name, "result" => result, "status" => status}
  end

  defp render_tool_answer(answer_text, tool_results, next_steps) do
    sections = [
      answer_text,
      render_tool_results(tool_results),
      render_next_steps(next_steps)
    ]

    sections
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp render_tool_results([]), do: ""

  defp render_tool_results(tool_results) do
    lines =
      Enum.map(tool_results, fn %{"name" => name, "status" => status} = tool_result ->
        detail = tool_result_summary(tool_result)
        "- #{name}: #{status}#{detail}"
      end)

    "Executed authoring tools:\n" <> Enum.join(lines, "\n")
  end

  defp tool_result_summary(%{
         "name" => "draft_wardwright_model",
         "result" => %{
           "artifact" => %{"model_id" => model_id},
           "validation" => %{"errors" => errors, "warnings" => warnings}
         }
       })
       when is_binary(model_id) and is_list(errors) and is_list(warnings) do
    " (draft #{model_id}, #{length(errors)} validation errors, #{length(warnings)} warnings, not active)"
  end

  defp tool_result_summary(%{"result" => %{"validation" => %{"errors" => errors, "warnings" => warnings}}})
       when is_list(errors) and is_list(warnings) do
    " (#{length(errors)} validation errors, #{length(warnings)} warnings)"
  end

  defp tool_result_summary(%{"result" => %{"errors" => errors, "warnings" => warnings}})
       when is_list(errors) and is_list(warnings) do
    " (#{length(errors)} validation errors, #{length(warnings)} warnings)"
  end

  defp tool_result_summary(%{"result" => %{"error" => error}}) when is_binary(error), do: " (#{error})"

  defp tool_result_summary(_tool_result), do: ""

  defp add_default_next_steps(tool_results, next_steps) do
    next_steps = List.wrap(next_steps)

    if Enum.any?(tool_results, &draft_model_tool_result?/1) do
      Enum.uniq(
        next_steps ++
          ["Review and activate the draft from the workbench if it matches your intent."]
      )
    else
      next_steps
    end
  end

  defp draft_model_tool_result?(%{
         "name" => "draft_wardwright_model",
         "result" => %{"artifact" => %{"model_id" => model_id}},
         "status" => "executed"
       })
       when is_binary(model_id), do: true

  defp draft_model_tool_result?(_result), do: false

  defp render_next_steps([]), do: ""

  defp render_next_steps(next_steps) when is_list(next_steps) do
    items =
      next_steps
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))

    if items == [] do
      ""
    else
      "Suggested next steps:\n" <> Enum.map_join(items, "\n", &"- #{&1}")
    end
  end

  defp render_next_steps(next_steps), do: render_next_steps([next_steps])

  defp response_text(response) do
    cond do
      is_binary(response) ->
        response

      is_struct(response, ReqLLM.Response) ->
        ReqLLM.Response.text(response)

      true ->
        inspect(response)
    end
  rescue
    _ -> inspect(response)
  end

  defp response_finish_reason(response) do
    case response do
      %{finish_reason: reason} -> reason
      _ -> nil
    end
  end

  defp response_usage(response) do
    case response do
      %{usage: usage} when is_map(usage) -> usage
      _ -> nil
    end
  end

  defp empty_answer_message(extras) do
    finish_reason = Keyword.get(extras, :finish_reason)

    if finish_reason in [:length, "length"] do
      """
      The Wardwright authoring assistant received reasoning metadata but no final answer before the model hit its token limit.

      Increase WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS and WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS, or switch to a model that returns final content more quickly. OpenCode Go marks BYOK usage in the response usage metadata; no extra Wardwright request-body flag is currently required for the configured OpenCode Go endpoint.
      """
    else
      "The Wardwright authoring assistant returned an empty answer."
    end
  end

  defp safe_error_summary(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> String.replace(~r/(Bearer\s+)[A-Za-z0-9._~+\/=-]+/i, "\\1[REDACTED]")
    |> String.replace(~r/(api[_-]?key[\"']?\s*[:=]\s*[\"']?)[^\"'\s,}]+/i, "\\1[REDACTED]")
    |> String.slice(0, 1_000)
  end

  defp not_configured_message(prompt) do
    """
    Wardwright's authoring assistant is installed but not configured for live model calls.

    To try it locally with opencode-go:

        WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
        WARDWRIGHT_AUTHORING_AGENT_ROUTE=direct
        WARDWRIGHT_AUTHORING_AGENT_BASE_URL=#{@default_base_url}
        WARDWRIGHT_AUTHORING_AGENT_MODEL=#{@default_model}
        WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE=/Users/admin/.config/calciforge/secrets/opencode-api-key
        WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=#{@default_max_tokens}
        WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=#{@default_timeout_ms}

    To dogfood the current local Wardwright model instead:

        WARDWRIGHT_AUTHORING_AGENT_ENABLED=1
        WARDWRIGHT_AUTHORING_AGENT_ROUTE=wardwright
        WARDWRIGHT_AUTHORING_AGENT_MODEL=local-authoring-model
        WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY_FILE=/path/to/local/wardwright/model-key
        WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS=#{@default_max_tokens}
        WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS=#{@default_timeout_ms}

    The selected local Wardwright model must include a structured_output schema
    named #{@required_authoring_schema}; otherwise dogfood mode stays disabled.

    The prompt below is what the agent would receive:

    #{prompt}
    """
  end

  defp tool_manifest do
    PolicyAuthoringTools.list()
    |> Enum.map_join("\n", &tool_manifest_line/1)
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

  defp authoring_route do
    authoring_env("WARDWRIGHT_AUTHORING_AGENT_ROUTE", "direct")
    |> String.downcase()
  end

  defp local_wardwright_route? do
    authoring_route() in ["wardwright", "local_wardwright", "local-wardwright", "dogfood"]
  end

  defp enabled? do
    authoring_env("WARDWRIGHT_AUTHORING_AGENT_ENABLED", "")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes", "on"])
  end

  defp base_url do
    authoring_env("WARDWRIGHT_AUTHORING_AGENT_BASE_URL") ||
      if local_wardwright_route?(), do: local_wardwright_base_url(), else: @default_base_url
  end

  defp model(_context) do
    case blank_to_nil(authoring_env("WARDWRIGHT_AUTHORING_AGENT_MODEL")) do
      nil ->
        if local_wardwright_route?(), do: "not-configured", else: @default_model

      configured_model ->
        configured_model
    end
  end

  defp selected_model_id(context) when is_map(context) do
    blank_to_nil(Map.get(context, :model_id)) ||
      blank_to_nil(Map.get(context, "model_id")) ||
      Wardwright.model_id()
  end

  defp requested_local_authoring_model_config(_context) do
    case blank_to_nil(authoring_env("WARDWRIGHT_AUTHORING_AGENT_MODEL")) do
      nil -> nil
      configured_model -> usable_local_authoring_model_config(configured_model)
    end
  end

  defp usable_local_authoring_model_config(model_id) do
    with {:ok, config} <- Wardwright.model_config(model_id),
         true <- locally_callable_for_authoring?(config) do
      config
    else
      _ -> nil
    end
  end

  defp locally_callable_for_authoring?(config) do
    authoring_tool_plan_schema?(config) and
      cond do
        Wardwright.model_requires_api_key?(config) -> blank_to_nil(local_model_api_key()) != nil
        Wardwright.unkeyed_model_access(config) == "public" -> true
        true -> false
      end
  end

  defp authoring_tool_plan_schema?(config) when is_map(config) do
    get_in(config, ["structured_output", "schemas", @required_authoring_schema])
    |> case do
      %{"type" => "object"} -> true
      _ -> false
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp local_wardwright_base_url do
    bind = System.get_env("WARDWRIGHT_BIND") || authoring_env("WARDWRIGHT_BIND", "127.0.0.1:8787")

    bind
    |> String.replace_prefix("0.0.0.0", "127.0.0.1")
    |> String.replace_prefix("http://0.0.0.0", "http://127.0.0.1")
    |> String.replace_prefix("https://0.0.0.0", "https://127.0.0.1")
    |> then(fn url ->
      cond do
        String.ends_with?(url, "/v1") -> url
        String.starts_with?(url, ["http://", "https://"]) -> url <> "/v1"
        true -> "http://#{url}/v1"
      end
    end)
  end

  defp max_tokens do
    "WARDWRIGHT_AUTHORING_AGENT_MAX_TOKENS"
    |> authoring_env(Integer.to_string(@default_max_tokens))
    |> Integer.parse()
    |> case do
      {value, ""} when value > 0 -> value
      _ -> @default_max_tokens
    end
  end

  defp timeout_ms do
    "WARDWRIGHT_AUTHORING_AGENT_TIMEOUT_MS"
    |> authoring_env(Integer.to_string(@default_timeout_ms))
    |> Integer.parse()
    |> case do
      {value, ""} when value > 0 -> value
      _ -> @default_timeout_ms
    end
  end

  defp jido_client do
    Application.get_env(:wardwright, :authoring_agent_client, Jido.AI)
  end

  defp api_key do
    authoring_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY") || api_key_from_file()
  end

  defp api_key_for_request do
    if local_wardwright_route?() do
      local_model_api_key() || "wardwright-local"
    else
      api_key()
    end
  end

  defp local_model_api_key do
    authoring_env("WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY") || local_model_api_key_from_file()
  end

  defp api_key_from_file do
    case authoring_env("WARDWRIGHT_AUTHORING_AGENT_API_KEY_FILE") do
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

  defp local_model_api_key_from_file do
    case authoring_env("WARDWRIGHT_AUTHORING_AGENT_MODEL_API_KEY_FILE") do
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

  defp authoring_env(key, default \\ nil) do
    System.get_env(key) ||
      authoring_config_file()
      |> config_file_env()
      |> Map.get(key, default)
  end

  defp authoring_config_file do
    System.get_env(@authoring_config_file_env) || default_authoring_config_file()
  end

  defp default_authoring_config_file do
    if !test_env?() do
      [
        Wardwright.Paths.config_path("authoring_agent.env"),
        "/opt/homebrew/etc/wardwright/authoring_agent.env",
        "/usr/local/etc/wardwright/authoring_agent.env"
      ]
      |> Enum.find(&File.regular?/1)
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp config_file_env(nil), do: %{}

  defp config_file_env(path) do
    path
    |> File.read()
    |> case do
      {:ok, contents} -> parse_env_file(contents)
      {:error, _reason} -> %{}
    end
  end

  defp parse_env_file(contents) do
    contents
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" or String.starts_with?(line, "#") ->
          acc

        String.contains?(line, "=") ->
          [key, value] = String.split(line, "=", parts: 2)
          key = String.trim(key)
          value = value |> String.trim() |> unquote_env_value()

          if String.starts_with?(key, "WARDWRIGHT_") and key != "" do
            Map.put(acc, key, value)
          else
            acc
          end

        true ->
          acc
      end
    end)
  end

  defp unquote_env_value(value) do
    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        value |> String.trim_leading("\"") |> String.trim_trailing("\"")

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        value |> String.trim_leading("'") |> String.trim_trailing("'")

      true ->
        value
    end
  end
end
