defmodule Wardwright.Router do
  @moduledoc false

  use Plug.Router

  alias Wardwright.Policy.AlertDelivery
  alias Wardwright.Policy.History
  alias Wardwright.Policy.Plan
  alias Wardwright.Policy.StructuredOutput
  alias Wardwright.PolicySandbox.DuneSnippetRegistry

  @max_unpinned_key "max_unpinned"
  @regression_format_key "format"
  @json_format "json"

  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: JSON,
    length: 1_048_576
  )

  plug(:cors)
  plug(:match)
  plug(:dispatch)

  options _ do
    send_resp(conn, 204, "")
  end

  get "/v1/models" do
    data =
      Wardwright.externally_callable_model_configs()
      |> Enum.flat_map(fn config ->
        model_id = config["model_id"]

        [
          %{"id" => model_id, "object" => "model", "owned_by" => "wardwright"},
          %{"id" => "wardwright/#{model_id}", "object" => "model", "owned_by" => "wardwright"}
        ]
      end)

    json(conn, 200, %{"data" => data, "object" => "list"})
  end

  get "/v1/wardwright/models" do
    data =
      Wardwright.externally_callable_model_configs()
      |> Enum.map(&Wardwright.model_summary/1)

    json(conn, 200, %{"data" => data})
  end

  post "/v1/chat/completions" do
    with {:ok, request} <- require_json_object(conn.body_params),
         {:ok, model} <- Wardwright.normalize_model(Map.get(request, "model")),
         {:ok, config} <- Wardwright.model_config(model),
         :ok <- require_model_access(conn, model, config),
         :ok <- require_messages(request) do
      request = apply_prompt_transforms(request, config)
      caller = WardwrightWeb.RequestContext.caller(conn, Map.get(request, "metadata", %{}))
      tool_context_opts = WardwrightWeb.RequestContext.tool_context_opts(conn)
      History.record_request(caller, request, tool_context_opts)
      {request, policy} = apply_request_policies(request, caller, tool_context_opts, config)
      {policy, fail_closed?} = deliver_policy_alerts(policy)
      decision = route_decision(request, policy, config)

      record_runtime_event(model, config, caller, "route.selected", %{
        "estimated_prompt_tokens" => decision.estimated_prompt_tokens,
        "selected_model" => decision.selected_model,
        "selected_provider" => decision.selected_provider
      })

      if Map.get(request, "stream") == true and not fail_closed? and not decision.route_blocked do
        WardwrightWeb.StreamRuntime.run(conn, model, caller, request, decision, policy, config)
      else
        provider = provider_outcome(request, decision, fail_closed?, config)
        History.record_response(caller, provider.content)

        receipt =
          provider.status
          |> WardwrightWeb.ReceiptBuilder.build(
            model,
            caller,
            request,
            decision,
            provider.called_provider,
            policy,
            config
          )
          |> WardwrightWeb.ReceiptBuilder.apply_provider_outcome(provider)

        Wardwright.ReceiptStore.insert(receipt)
        record_counterfactual_transcript(receipt)

        record_runtime_event(model, config, caller, "receipt.finalized", %{
          "alert_count" => get_in(receipt, ["final", "alert_count"]) || 0,
          "receipt_id" => receipt["receipt_id"],
          "simulation" => false,
          "status" => get_in(receipt, ["final", "status"])
        })

        emit_receipt_sink_event(receipt, false)

        conn =
          conn
          |> put_resp_header("x-wardwright-receipt-id", receipt["receipt_id"])
          |> put_resp_header("x-wardwright-selected-model", decision.selected_model)

        json(
          conn,
          WardwrightWeb.ReceiptBuilder.response_status(receipt),
          WardwrightWeb.ReceiptBuilder.chat_response(request, receipt, decision, provider)
        )
      end
    else
      {:error, message} ->
        error(conn, 400, message, "invalid_request", "bad_request")

      {:error, :model_auth, status, message, code} ->
        error(conn, status, message, model_auth_error_type(status), code)
    end
  end

  post "/v1/wardwright/simulate" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, request} <- require_json_object(Map.get(body, "request")),
         request = override_model(request, Map.get(body, "model")),
         {:ok, model} <- Wardwright.normalize_model(Map.get(request, "model")),
         {:ok, config} <- Wardwright.model_config(model),
         :ok <- require_messages(request) do
      request = apply_prompt_transforms(request, config)
      caller = WardwrightWeb.RequestContext.caller(conn, Map.get(request, "metadata", %{}))
      tool_context_opts = WardwrightWeb.RequestContext.tool_context_opts(conn)
      History.record_request(caller, request, tool_context_opts)
      {request, policy} = apply_request_policies(request, caller, tool_context_opts, config)
      {policy, fail_closed?} = deliver_policy_alerts(policy)
      decision = route_decision(request, policy, config)

      record_runtime_event(model, config, caller, "simulation.route_selected", %{
        "estimated_prompt_tokens" => decision.estimated_prompt_tokens,
        "selected_model" => decision.selected_model,
        "selected_provider" => decision.selected_provider
      })

      status =
        if fail_closed? or decision.route_blocked, do: "policy_failed_closed", else: "simulated"

      receipt =
        WardwrightWeb.ReceiptBuilder.build(
          status,
          model,
          caller,
          request,
          decision,
          false,
          policy,
          config
        )

      Wardwright.ReceiptStore.insert(receipt)
      record_counterfactual_transcript(receipt)

      record_runtime_event(model, config, caller, "receipt.finalized", %{
        "alert_count" => get_in(receipt, ["final", "alert_count"]) || 0,
        "receipt_id" => receipt["receipt_id"],
        "simulation" => true,
        "status" => get_in(receipt, ["final", "status"])
      })

      emit_receipt_sink_event(receipt, true)

      json(conn, 200, %{"receipt" => receipt})
    else
      {:error, message} ->
        error(conn, 400, message, "invalid_request", "bad_request")

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/v1/receipts" do
    case require_protected_access(conn) do
      :ok ->
        filters =
          conn.query_params
          |> Map.take([
            "model",
            "consuming_agent_id",
            "consuming_user_id",
            "session_id",
            "run_id",
            "status",
            "tenant_id",
            "application_id",
            "model_id",
            "model_version",
            "selected_provider",
            "selected_model",
            "simulation",
            "stream_policy_action",
            "tool_namespace",
            "tool_name",
            "tool_phase",
            "tool_policy_status",
            "tool_risk_class",
            "tool_source",
            "tool_call_id",
            "created_at_min",
            "created_at_max"
          ])
          |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
          |> Map.new()

        limit = parse_limit(Map.get(conn.query_params, "limit"))
        receipts = Wardwright.ReceiptStore.list(filters, limit)
        json(conn, 200, %{"data" => receipts})

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/v1/receipts/:receipt_id" do
    case require_protected_access(conn) do
      :ok ->
        case Wardwright.ReceiptStore.get(receipt_id) do
          nil -> error(conn, 404, "receipt not found", "not_found", "receipt_not_found")
          receipt -> json(conn, 200, receipt)
        end

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/admin/storage" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, Wardwright.ReceiptStore.health())

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/admin/runtime" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, Wardwright.Runtime.status())

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/admin/model-access" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, Wardwright.model_access(request_origin(conn)))

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/admin/model-api-keys" do
    with :ok <- require_protected_access(conn),
         {:ok, model} <- optional_model(Map.get(conn.query_params, "model")) do
      json(conn, 200, %{"data" => Wardwright.ModelApiKeyStore.list(model)})
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_model_api_key")
    end
  end

  post "/admin/model-api-keys" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, model} <- Wardwright.normalize_model(Map.get(body, "model")),
         {:ok, key} <- Wardwright.ModelApiKeyStore.create(model, Map.get(body, "label", "")) do
      json(conn, 201, %{"api_key" => key})
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_model_api_key")
    end
  end

  delete "/admin/model-api-keys/:key_id" do
    with :ok <- require_protected_access(conn),
         :ok <- Wardwright.ModelApiKeyStore.revoke(key_id) do
      json(conn, 200, %{"deleted" => true, "id" => key_id})
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, :not_found} ->
        error(conn, 404, "model API key not found", "not_found", "model_api_key_not_found")
    end
  end

  get "/admin/policy-alerts" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, AlertDelivery.status())

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/admin/sinks" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, Wardwright.Sinks.status())

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  post "/v1/policy-cache/events" do
    with :ok <- require_protected_access(conn),
         {:ok, event} <- Wardwright.PolicyCache.add(conn.body_params) do
      json(conn, 201, %{"event" => event})
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_policy_cache_event")
    end
  end

  get "/v1/policy-cache/recent" do
    case require_protected_access(conn) do
      :ok ->
        filter = %{
          "key" => WardwrightWeb.RequestContext.blank_to_nil(Map.get(conn.query_params, "key")),
          "kind" => WardwrightWeb.RequestContext.blank_to_nil(Map.get(conn.query_params, "kind")),
          "scope" => WardwrightWeb.RequestContext.cache_scope_from_query(conn.query_params)
        }

        limit = parse_limit(Map.get(conn.query_params, "limit"))
        json(conn, 200, %{"data" => Wardwright.PolicyCache.recent(filter, limit)})

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/v1/policy-authoring/tools" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, Map.new([{"data", WardwrightWeb.PolicyAuthoringTools.list()}]))

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/v1/policy-authoring/projections/:pattern_id" do
    with :ok <- require_protected_access(conn),
         :ok <- require_known_policy_pattern(pattern_id) do
      json(
        conn,
        200,
        Map.new([{"projection", Wardwright.PolicyProjection.projection(pattern_id)}])
      )
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 404, message, "not_found", "policy_pattern_not_found")
    end
  end

  get "/v1/policy-authoring/simulations/:pattern_id" do
    with :ok <- require_protected_access(conn),
         :ok <- require_known_policy_pattern(pattern_id) do
      json(conn, 200, Map.new([{"data", Wardwright.PolicyProjection.simulations(pattern_id)}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 404, message, "not_found", "policy_pattern_not_found")
    end
  end

  get "/v1/policy-authoring/dune-snippets" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, DuneSnippetRegistry.list())

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  post "/v1/policy-authoring/dune-snippets" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, result} <- DuneSnippetRegistry.save(body) do
      json(conn, 201, result)
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_dune_snippet")
    end
  end

  delete "/v1/policy-authoring/dune-snippets/:snippet_id" do
    with :ok <- require_protected_access(conn),
         {:ok, result} <- DuneSnippetRegistry.delete(snippet_id) do
      json(conn, 200, result)
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_dune_snippet")
    end
  end

  post "/v1/policy-authoring/dune-snippets/evaluate" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, result} <- DuneSnippetRegistry.evaluate(body) do
      json(conn, 200, result)
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_dune_snippet")
    end
  end

  post "/v1/policy-authoring/wardwright-models/draft" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params) do
      json(
        conn,
        200,
        WardwrightWeb.PolicyAuthoringDrafts.wardwright_model_draft(body, request_origin(conn))
      )
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_policy_artifact")
    end
  end

  post "/v1/policy-authoring/wardwright-models" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, result} <-
           WardwrightWeb.PolicyAuthoringDrafts.activate_wardwright_model(
             body,
             request_origin(conn)
           ) do
      json(conn, 201, result)
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message, result} ->
        json(conn, 422, WardwrightWeb.PolicyAuthoringDrafts.with_error(result, message))

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_policy_artifact")
    end
  end

  post "/v1/policy-authoring/propose-rule-change" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params) do
      json(conn, 200, WardwrightWeb.PolicyAuthoringDrafts.propose_rule_change(body))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_policy_artifact")
    end
  end

  get "/v1/policy-authoring/scenarios/:pattern_id" do
    with :ok <- require_protected_access(conn),
         true <- known_policy_pattern?(pattern_id) do
      scenarios =
        pattern_id
        |> Wardwright.PolicyScenarioStore.list()
        |> Enum.map(&Wardwright.PolicyScenario.to_map/1)

      json(conn, 200, Map.new([{"data", scenarios}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      false ->
        error(conn, 404, "policy pattern not found", "not_found", "policy_pattern_not_found")
    end
  end

  post "/v1/policy-authoring/scenarios/:pattern_id" do
    with :ok <- require_protected_access(conn),
         true <- known_policy_pattern?(pattern_id),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, scenario_body} <- scenario_payload(body),
         {:ok, scenario} <- Wardwright.PolicyScenarioStore.create(pattern_id, scenario_body) do
      json(conn, 201, Map.new([{"scenario", Wardwright.PolicyScenario.to_map(scenario)}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      false ->
        error(conn, 404, "policy pattern not found", "not_found", "policy_pattern_not_found")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_policy_scenario")
    end
  end

  delete "/v1/policy-authoring/scenarios/:pattern_id/:scenario_id" do
    with :ok <- require_protected_access(conn),
         true <- known_policy_pattern?(pattern_id),
         {:ok, scenario} <- Wardwright.PolicyScenarioStore.delete(pattern_id, scenario_id) do
      json(conn, 200, Map.new([{"scenario", Wardwright.PolicyScenario.to_map(scenario)}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      false ->
        error(conn, 404, "policy pattern not found", "not_found", "policy_pattern_not_found")

      {:error, "scenario not found"} ->
        error(conn, 404, "scenario not found", "not_found", "policy_scenario_not_found")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_policy_scenario")
    end
  end

  post "/v1/policy-authoring/scenarios/:pattern_id/from-receipt/:receipt_id" do
    with :ok <- require_protected_access(conn),
         true <- known_policy_pattern?(pattern_id),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, receipt} <- receipt_for_import(receipt_id),
         {:ok, scenario} <-
           Wardwright.PolicyScenarioStore.create_from_receipt(pattern_id, receipt, body) do
      json(conn, 201, Map.new([{"scenario", Wardwright.PolicyScenario.to_map(scenario)}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      false ->
        error(conn, 404, "policy pattern not found", "not_found", "policy_pattern_not_found")

      {:error, :receipt_not_found} ->
        error(conn, 404, "receipt not found", "not_found", "receipt_not_found")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_policy_scenario")
    end
  end

  post "/v1/policy-authoring/replay-receipts/:receipt_id" do
    with :ok <- require_protected_access(conn),
         {:ok, replay} <- Wardwright.PolicyReplay.replay_receipt_id(receipt_id) do
      json(conn, 200, Map.new([{"replay", replay}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, :receipt_not_found} ->
        error(conn, 404, "receipt not found", "not_found", "receipt_not_found")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_policy_replay")
    end
  end

  get "/v1/policy-authoring/harness-adapters" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, Map.new([{"data", WardwrightWeb.AgentHarnessAdapters.list()}]))

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  post "/v1/policy-authoring/harness-adapters/:adapter_id/export" do
    with :ok <- require_protected_access(conn),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, session_id} <- required_body_string(body, "session_id"),
         {:ok, export} <- WardwrightWeb.AgentHarnessAdapters.export(session_id, adapter_id, body) do
      json(conn, 200, Map.new([{"export", export}]))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_harness_adapter_export")
    end
  end

  get "/v1/policy-authoring/scenarios/:pattern_id/regression-export" do
    with :ok <- require_protected_access(conn),
         true <- known_policy_pattern?(pattern_id),
         {:ok, export} <- Wardwright.PolicyScenarioStore.regression_export(pattern_id) do
      format = Map.get(conn.query_params, @regression_format_key, @json_format)

      case format do
        @json_format ->
          json(conn, 200, export)

        "exunit" ->
          case WardwrightWeb.PolicyScenarioRegression.exunit_source(export) do
            {:ok, source} ->
              text(conn, 200, source)

            {:error, message} ->
              error(conn, 400, message, "invalid_request", "invalid_regression_export")
          end

        other ->
          error(
            conn,
            400,
            "unsupported regression export format #{inspect(other)}",
            "invalid_request",
            "invalid_regression_export_format"
          )
      end
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      false ->
        error(conn, 404, "policy pattern not found", "not_found", "policy_pattern_not_found")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_regression_export")
    end
  end

  post "/v1/policy-authoring/scenarios/:pattern_id/retention" do
    with :ok <- require_protected_access(conn),
         true <- known_policy_pattern?(pattern_id),
         {:ok, body} <- require_json_object(conn.body_params),
         {:ok, max_unpinned} <- retention_max_unpinned(body),
         {:ok, retention} <-
           Wardwright.PolicyScenarioStore.enforce_retention(pattern_id, max_unpinned) do
      json(conn, 200, retention)
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      false ->
        error(conn, 404, "policy pattern not found", "not_found", "policy_pattern_not_found")

      {:error, message} when is_binary(message) ->
        error(conn, 400, message, "invalid_request", "invalid_policy_scenario_retention")
    end
  end

  post "/v1/policy-authoring/validate" do
    with :ok <- require_protected_access(conn),
         {:ok, artifact, source} <- validation_artifact(conn.body_params) do
      json(conn, 200, WardwrightWeb.PolicyArtifactValidator.validate(artifact, source: source))
    else
      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")

      {:error, message} ->
        error(conn, 400, message, "invalid_request", "invalid_policy_artifact")
    end
  end

  get "/admin/providers" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, %{"data" => Wardwright.providers()})

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  get "/admin/wardwright-models" do
    case require_protected_access(conn) do
      :ok ->
        json(conn, 200, %{"data" => Wardwright.model_records()})

      {:error, :protected, message} ->
        error(conn, 403, message, "forbidden", "protected_endpoint")
    end
  end

  post "/__test/config" do
    if test_config_allowed?() do
      with {:ok, config} <- require_json_object(conn.body_params),
           {:ok, config} <- Wardwright.put_config(config) do
        Wardwright.ReceiptStore.clear()
        Wardwright.PolicyScenarioStore.clear()

        json(conn, 200, %{
          "model_id" => config["model_id"],
          "status" => "ok",
          "targets" => config["targets"]
        })
      else
        {:error, message} -> error(conn, 400, message, "invalid_request", "invalid_test_config")
      end
    else
      error(conn, 404, "not found", "not_found", "not_found")
    end
  end

  match _ do
    error(conn, 404, "not found", "not_found", "not_found")
  end

  defp require_json_object(value) when is_map(value), do: {:ok, value}
  defp require_json_object(_), do: {:error, "request body must be a JSON object"}

  defp optional_model(nil), do: {:ok, nil}
  defp optional_model(""), do: {:ok, nil}
  defp optional_model(model), do: Wardwright.normalize_model(model)

  defp scenario_payload(body) do
    # boundary-map-ok
    # boundary-map-ok
    case Map.fetch(body, "scenario") do
      {:ok, scenario} when is_map(scenario) -> {:ok, scenario}
      {:ok, _scenario} -> {:error, "scenario must be a JSON object"}
      :error -> {:ok, body}
    end
  end

  defp request_origin(conn) do
    scheme = Atom.to_string(conn.scheme)

    if default_port?(conn.scheme, conn.port) do
      "#{scheme}://#{conn.host}"
    else
      "#{scheme}://#{conn.host}:#{conn.port}"
    end
  end

  defp default_port?(:http, 80), do: true
  defp default_port?(:https, 443), do: true
  defp default_port?(_, _), do: false

  defp receipt_for_import(receipt_id) do
    case Wardwright.ReceiptStore.get(receipt_id) do
      nil -> {:error, :receipt_not_found}
      receipt -> {:ok, receipt}
    end
  end

  defp validation_artifact(body) when body == %{}, do: {:ok, Wardwright.current_config(), "current_config"}

  defp validation_artifact(body) when is_map(body) do
    case Map.fetch(body, "artifact") do
      {:ok, artifact} when is_map(artifact) -> {:ok, artifact, "submitted"}
      {:ok, _artifact} -> {:error, "artifact must be a JSON object"}
      :error -> {:ok, body, "submitted"}
    end
  end

  defp validation_artifact(_body), do: {:error, "request body must be a JSON object"}

  defp retention_max_unpinned(body) do
    case Map.get(body, @max_unpinned_key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _value -> {:error, "max_unpinned must be a non-negative integer"}
    end
  end

  defp required_body_string(body, key) do
    case body do
      %{^key => value} when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, "#{key} must be a non-empty string"}
          trimmed -> {:ok, trimmed}
        end

      _value ->
        {:error, "#{key} must be a non-empty string"}
    end
  end

  defp override_model(request, nil), do: request
  defp override_model(request, ""), do: request
  defp override_model(request, model), do: Map.put(request, "model", model)

  defp apply_prompt_transforms(request, config) do
    transforms = config["prompt_transforms"] || %{}
    messages = Map.get(request, "messages", [])

    messages =
      transforms["preamble"]
      |> WardwrightWeb.RequestContext.metadata_string()
      |> WardwrightWeb.RequestContext.blank_to_nil()
      |> case do
        nil ->
          messages

        text ->
          [%{"content" => text, "name" => "wardwright_preamble", "role" => "system"} | messages]
      end

    messages =
      transforms["postscript"]
      |> WardwrightWeb.RequestContext.metadata_string()
      |> WardwrightWeb.RequestContext.blank_to_nil()
      |> case do
        nil ->
          messages

        text ->
          messages ++
            [%{"content" => text, "name" => "wardwright_postscript", "role" => "system"}]
      end

    Map.put(request, "messages", messages)
  end

  defp apply_request_policies(request, caller, opts, config), do: Plan.evaluate_request(request, caller, config, opts)

  defp deliver_policy_alerts(%{"events" => events} = policy) do
    alert_delivery = AlertDelivery.deliver(events)

    policy =
      policy
      |> Map.put("alert_delivery", alert_delivery)
      |> Map.put(
        "failed_closed",
        Map.get(policy, "blocked", false) or
          AlertDelivery.fail_closed?(alert_delivery)
      )

    {policy, policy["failed_closed"]}
  end

  defp provider_outcome(_request, _decision, true) do
    %{
      called_provider: false,
      content: nil,
      error: "policy failed closed",
      latency_ms: 0,
      mock: true,
      status: "policy_failed_closed",
      structured_output: nil
    }
  end

  defp provider_outcome(_request, %{route_blocked: true}, false) do
    %{
      called_provider: false,
      content: nil,
      error: "route policy removed all provider targets",
      latency_ms: 0,
      mock: true,
      status: "policy_failed_closed",
      structured_output: nil
    }
  end

  defp provider_outcome(request, decision, true, _config), do: provider_outcome(request, decision, true)

  defp provider_outcome(request, %{route_blocked: true} = decision, false, _config),
    do: provider_outcome(request, decision, false)

  defp provider_outcome(request, decision, false, config) when is_map(request) do
    structured_config = config["structured_output"]

    StructuredOutput.run(structured_config, fn attempt_index ->
      request
      |> Map.put("wardwright_attempt_index", attempt_index)
      |> Wardwright.StructuredOutputRetryFeedback.add(attempt_index, structured_config)
      |> then(&Wardwright.complete_selected_model(decision.selected_model, &1, config))
      |> Map.put_new(:structured_output, nil)
    end)
  end

  defp require_messages(%{"messages" => messages}) when is_list(messages) and messages != [], do: :ok

  defp require_messages(_), do: {:error, "messages must not be empty"}

  defp require_model_access(conn, model, config) do
    cond do
      Wardwright.model_requires_api_key?(config) ->
        if Wardwright.ModelApiKeyStore.valid?(model, request_model_api_key(conn)) do
          :ok
        else
          {:error, :model_auth, 401, "valid model API key required", "model_api_key_required"}
        end

      Wardwright.unkeyed_model_access(config) == "internal" ->
        {:error, :model_auth, 403, "model is only available for internal composition", "model_internal"}

      true ->
        :ok
    end
  end

  defp model_auth_error_type(401), do: "unauthorized"
  defp model_auth_error_type(403), do: "forbidden"

  defp request_model_api_key(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> bearer_token()
    |> case do
      nil ->
        conn
        |> get_req_header("x-wardwright-model-api-key")
        |> List.first()
        |> WardwrightWeb.RequestContext.metadata_string()
        |> WardwrightWeb.RequestContext.blank_to_nil()

      token ->
        token
    end
  end

  defp require_protected_access(conn) do
    if WardwrightWeb.ProtectedAccess.authorized?(conn, allow_prototype: true) do
      :ok
    else
      message =
        if WardwrightWeb.ProtectedAccess.basic_auth_configured?(),
          do: "protected endpoint requires basic auth or admin token",
          else: "protected endpoint requires localhost or admin token"

      {:error, :protected, message}
    end
  end

  defp bearer_token("Bearer " <> token), do: WardwrightWeb.RequestContext.blank_to_nil(token)
  defp bearer_token("bearer " <> token), do: WardwrightWeb.RequestContext.blank_to_nil(token)
  defp bearer_token(_value), do: nil

  defp route_decision(request, policy, config) do
    estimate = Wardwright.estimate_prompt_tokens(Map.get(request, "messages", []))
    Wardwright.select_route(config, estimate, Map.get(policy, "route_constraints", %{}))
  end

  defp record_runtime_event(model, config, caller, type, fields) do
    version = config["version"]

    case Wardwright.Runtime.record_session_event(
           model,
           version,
           WardwrightWeb.RequestContext.session_id(caller),
           type,
           fields
         ) do
      {:ok, _event} -> :ok
      _ -> :ok
    end
  end

  defp emit_receipt_sink_event(receipt, simulation) do
    Wardwright.Sinks.emit([
      %{
        "alert_count" => get_in(receipt, ["final", "alert_count"]) || 0,
        "receipt_id" => receipt["receipt_id"],
        "selected_model" => get_in(receipt, ["decision", "selected_model"]),
        "selected_provider" => get_in(receipt, ["decision", "selected_provider"]),
        "simulation" => simulation,
        "status" => get_in(receipt, ["final", "status"]),
        "type" => "receipt.finalized"
      }
      |> Map.merge(WardwrightWeb.ReceiptBuilder.sink_usage(receipt))
    ])

    :ok
  end

  defp record_counterfactual_transcript(receipt) do
    case WardwrightWeb.CounterfactualReplay.record_gateway_receipt(receipt) do
      {:ok, _result} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp test_config_allowed? do
    Application.get_env(:wardwright, :allow_test_config, false) or
      System.get_env("WARDWRIGHT_ALLOW_TEST_CONFIG") == "1"
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(payload))
  end

  defp text(conn, status, body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  defp cors(conn, _opts) do
    if public_cors_path?(conn.request_path) do
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET, POST, DELETE, OPTIONS")
      |> put_resp_header(
        "access-control-allow-headers",
        "Authorization, Content-Type, X-Wardwright-Admin-Token, X-Wardwright-Model-Api-Key, X-Wardwright-Tenant-Id, X-Wardwright-Application-Id, X-Wardwright-Agent-Id, X-Wardwright-User-Id, X-Wardwright-Session-Id, X-Wardwright-Run-Id, X-Client-Request-Id"
      )
      |> put_resp_header(
        "access-control-expose-headers",
        "X-Wardwright-Receipt-Id, X-Wardwright-Selected-Model"
      )
    else
      conn
    end
  end

  defp public_cors_path?("/v1/models"), do: true
  defp public_cors_path?("/v1/wardwright/models"), do: true
  defp public_cors_path?("/v1/chat/completions"), do: true
  defp public_cors_path?(_path), do: false

  defp error(conn, status, message, type, code) do
    json(conn, status, %{
      "error" => %{
        "code" => code,
        "message" => message,
        "type" => type
      }
    })
  end

  defp parse_limit(nil), do: 50

  defp parse_limit(raw) do
    case Integer.parse(raw) do
      {value, ""} -> value |> max(1) |> min(500)
      _ -> 50
    end
  end

  defp require_known_policy_pattern(pattern_id) do
    if known_policy_pattern?(pattern_id) do
      :ok
    else
      {:error, "policy pattern not found"}
    end
  end

  defp known_policy_pattern?(pattern_id), do: pattern_id in Wardwright.PolicyProjection.pattern_ids()
end
