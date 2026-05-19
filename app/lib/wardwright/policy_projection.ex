defmodule Wardwright.PolicyProjection do
  @moduledoc false

  alias Wardwright.Policy.Action
  alias Wardwright.Policy.Plan
  alias Wardwright.PolicyProjection.Contract

  @kind_key "kind"
  @transition_to_key "transition_to"
  @then_key "then"
  @action_key "action"
  @tool_sequence_kind "tool_sequence"
  @tool_loop_threshold_kind "tool_loop_threshold"
  @state_transition_action "state_transition"
  @decision_tool_context_read "decision.tool_context"
  @policy_cache_tool_call_read "policy_cache.session.tool_call"
  @policy_cache_state_read "policy_cache.session.policy_state"
  @policy_actions_write "policy.actions"

  @patterns [
    %{
      "category" => "response.streaming",
      "id" => "tts-retry",
      "promise" =>
        "Hold a bounded stream horizon, catch prohibited output before release, then retry once with a precise reminder.",
      "title" => "Time-travel stream retry"
    },
    %{
      "category" => "response.streaming",
      "id" => "stream-rewrite-state",
      "promise" =>
        "Show related stream regex matches where one rewrites held output and a later match transitions the session into review.",
      "title" => "Regex rewrite and state transition"
    },
    %{
      "category" => "output.finalizing",
      "id" => "ambiguous-success",
      "promise" => "Detect final answers that claim completion while required artifacts or fields are missing.",
      "title" => "Ambiguous success alert"
    },
    %{
      "category" => "route.selecting",
      "id" => "route-privacy",
      "promise" => "Keep private-risk requests on approved local routes unless cloud escalation is explicitly allowed.",
      "title" => "Private context route gate"
    },
    %{
      "category" => "tool.using",
      "id" => "tool-governance",
      "promise" =>
        "Normalize tool context, expose tool-sensitive policy review points, and make tool selector/loop rules visible before enforcement.",
      "title" => "Tool call governance"
    }
  ]

  def patterns, do: @patterns

  def pattern_ids, do: Enum.map(@patterns, &Map.fetch!(&1, "id"))

  def state_ids(pattern_id) when is_binary(pattern_id) do
    :wardwright@projection_core.state_ids(pattern_id, pattern_id in pattern_ids())
  end

  def pattern(pattern_id) do
    Enum.find(@patterns, &(&1["id"] == pattern_id)) || hd(@patterns)
  end

  def projection(pattern_id, config \\ Wardwright.current_config()) do
    pattern = pattern(pattern_id)
    phases = phases(pattern["id"], config)

    %{
      "artifact" => artifact(pattern, config),
      "compiled_plan" => compiled_plan(pattern["id"], config, phases),
      "conflicts" => conflicts(pattern["id"], config),
      "effects" => effects(pattern["id"], config),
      "engine" => engine(pattern["id"], config),
      "opaque_regions" => opaque_regions(pattern["id"], config),
      "phases" => phases,
      "projection_schema" => "wardwright.policy_projection.v1",
      "state_machine" => state_machine(pattern["id"], phases, config),
      "warnings" => warnings(pattern["id"], config)
    }
  end

  def simulations(pattern_id, config \\ Wardwright.current_config()) do
    artifact_hash = artifact(pattern(pattern_id), config)["artifact_hash"]

    pattern_id
    |> simulation_records(config)
    |> Enum.map(&Map.put(&1, "artifact_hash", artifact_hash))
  end

  def simulation_inputs(pattern_id) do
    fixture_inputs =
      Enum.map(simulation_inputs(), fn input ->
        Map.put(input, "relationship", simulation_input_relationship(pattern_id, input["id"]))
      end)

    fixture_inputs ++ persisted_simulation_inputs(pattern_id)
  end

  def simulation_inputs("ambiguous-success", "structured-output-repair-gate") do
    structured_output_simulation_inputs() ++ persisted_simulation_inputs("ambiguous-success")
  end

  def simulation_inputs(pattern_id, _recipe_id), do: simulation_inputs(pattern_id)

  def simulation_inputs do
    tts_simulation_inputs() ++
      stream_rewrite_simulation_inputs() ++
      ambiguous_success_simulation_inputs()
  end

  defp tts_simulation_inputs do
    [
      %{
        "description" => "OldClient( appears across held stream chunks and should trigger retry.",
        "id" => "split-old-client",
        "model_response" => "avoid introducing Old\nClient( into the final answer",
        "title" => "TTSR: split prohibited span",
        "user_input" => "Show me the legacy adapter name in a migration note."
      },
      %{
        "description" => "No prohibited span appears, so the stream can release normally.",
        "id" => "safe-stream",
        "model_response" => "Use the current client adapter.\nAvoid legacy constructor names.",
        "title" => "TTSR: safe stream",
        "user_input" => "Write a migration note that avoids deprecated constructors."
      }
    ]
  end

  defp stream_rewrite_simulation_inputs do
    [
      %{
        "description" => "An account identifier is rewritten, then a related token forces review.",
        "history_context" => %{"policy_state" => "observing", "recent_related_secret_matches" => "0"},
        "id" => "rewrite-then-secret",
        "model_response" => "account acct_4938 appears in the answer\ntoken_live_4938 follows in the held horizon",
        "title" => "Stream: rewrite then transition",
        "user_input" => "Summarize the billing incident without exposing credentials."
      },
      %{
        "description" =>
          "Private request context is withheld from the provider, then an account identifier is redacted before release.",
        "history_context" => %{"policy_state" => "observing", "recent_related_secret_matches" => "0"},
        "id" => "input-and-output-rewrite",
        "model_response" => "The billing incident for account acct_4938 can be summarized without the private email.",
        "title" => "Stream: input and output rewrite",
        "user_input" => "Summarize the incident. private_context{customer email is alex@example.test}"
      },
      %{
        "description" => "The account identifier is redacted and the rewritten stream is released.",
        "history_context" => %{"policy_state" => "observing", "recent_related_secret_matches" => "0"},
        "id" => "rewrite-only",
        "model_response" => "account acct_4938 appears in the answer\nno related secret follows",
        "title" => "Stream: rewrite only",
        "user_input" => "Summarize the billing incident without exposing credentials."
      },
      %{
        "description" =>
          "A current account rewrite combines with three recent related matches in the last five turns, so the policy moves to review.",
        "history_context" => %{
          "policy_state" => "observing",
          "recent_related_secret_matches" => "3",
          "recent_secret_window_requests" => "5"
        },
        "id" => "history-threshold-escalation",
        "model_response" => "account acct_4938 appears in the answer with no new secret token.",
        "title" => "Stream: history threshold escalates",
        "user_input" => "Summarize the billing incident without exposing credentials."
      },
      %{
        "description" =>
          "No bytes need rewriting on this turn, but session history crosses the review threshold, so the next turn starts in review mode.",
        "history_context" => %{
          "policy_state" => "observing",
          "recent_related_secret_matches" => "3",
          "recent_secret_window_requests" => "5"
        },
        "id" => "next-turn-review-model",
        "model_response" => "No account identifiers are present in this neutral status update.",
        "title" => "Stream: next turn uses review model",
        "user_input" => "Give a short status update for the billing incident."
      },
      %{
        "description" => "No configured regex matches the held chunks.",
        "history_context" => %{"policy_state" => "observing", "recent_related_secret_matches" => "0"},
        "id" => "no-match",
        "model_response" => "ordinary response text\nwith no account ids or secret tokens",
        "title" => "Stream: no regex match",
        "user_input" => "Write a neutral status update."
      }
    ]
  end

  defp ambiguous_success_simulation_inputs do
    [
      %{
        "description" => "The final text claims completion but does not include artifact evidence.",
        "id" => "claim-without-artifact",
        "model_response" => "Done, the export is ready for download.",
        "title" => "Artifact: claim without artifact",
        "user_input" => "Export the policy audit report as a spreadsheet."
      },
      %{
        "description" => "The completion claim is backed by an artifact identifier.",
        "id" => "claim-with-artifact",
        "model_response" => "Done, the export is ready. Artifact: report-2026-05-16.xlsx",
        "title" => "Artifact: claim with metadata",
        "user_input" => "Export the policy audit report as a spreadsheet."
      }
    ]
  end

  defp structured_output_simulation_inputs do
    [
      %{
        "description" => "The provider returns something JSON-like, but Wardwright cannot parse the promised contract.",
        "id" => "json-malformed-repair",
        "model_response" => ~s({"status":"done","artifact_id":),
        "relationship" => "direct",
        "title" => "JSON: malformed response gets repair feedback",
        "user_input" => "Return a structured deployment summary."
      },
      %{
        "description" => "The JSON parses, but no accepted schema branch includes the evidence Wardwright promised.",
        "id" => "json-missing-semantic-field",
        "model_response" => ~s({"status":"done","summary":"Deployment finished."}),
        "relationship" => "direct",
        "title" => "JSON: schema branch missing evidence",
        "user_input" => "Return a structured deployment summary."
      },
      %{
        "description" =>
          "The caller accepts more than one shape, and this response satisfies the receipt-style branch.",
        "id" => "json-valid-alternate-schema",
        "model_response" => ~s({"result":{"state":"completed"},"evidence":{"artifact_id":"deploy-4938"}}),
        "relationship" => "direct",
        "title" => "JSON: alternate accepted schema",
        "user_input" => "Return a structured deployment summary."
      }
    ]
  end

  defp simulation_input_relationship("tts-retry", input_id) when input_id in ["split-old-client", "safe-stream"],
    do: "direct"

  defp simulation_input_relationship("stream-rewrite-state", input_id)
       when input_id in [
              "rewrite-then-secret",
              "input-and-output-rewrite",
              "rewrite-only",
              "history-threshold-escalation",
              "next-turn-review-model",
              "no-match"
            ], do: "direct"

  defp simulation_input_relationship("ambiguous-success", input_id)
       when input_id in ["claim-without-artifact", "claim-with-artifact"], do: "direct"

  defp simulation_input_relationship(_pattern_id, _input_id), do: "cross_policy_probe"

  defp persisted_simulation_inputs(pattern_id) do
    pattern_id
    |> Wardwright.PolicyScenarioStore.list()
    |> Enum.flat_map(&persisted_simulation_input/1)
  end

  defp persisted_simulation_input(scenario) do
    scenario
    |> Wardwright.PolicyScenario.to_map()
    |> Map.get("turn")
    |> case do
      %{} = turn ->
        [
          Map.new([
            {"id", "saved:#{scenario.id}"},
            {"title", scenario.title},
            {"description", scenario.expected_behavior},
            {"relationship", "saved_scenario"},
            {"source_model_id", scenario.model_id},
            {"source_artifact_hash", scenario.artifact_hash},
            {"user_input", Map.get(turn, "user_input", "")},
            {"model_response", Map.get(turn, "model_response", "")},
            {"response_attempts", Map.get(turn, "response_attempts", [])},
            {"history_context", Map.get(turn, "history_context", %{})}
          ])
        ]

      _ ->
        []
    end
  end

  def simulate_input(pattern_id, text, config \\ Wardwright.current_config()) do
    simulate_turn(pattern_id, "", text, config)
  end

  def simulate_turn(pattern_id, user_input, model_response, config \\ Wardwright.current_config()) do
    simulate_turn_with_context(pattern_id, user_input, model_response, %{}, config)
  end

  def simulate_turn_with_context(
        pattern_id,
        user_input,
        model_response,
        history_context,
        config \\ Wardwright.current_config()
      ) do
    artifact_hash = artifact(pattern(pattern_id), config)["artifact_hash"]

    turn = %{
      "history_context" => normalize_history_context(history_context),
      "model_response" => model_response || "",
      "user_input" => user_input || ""
    }

    pattern_id
    |> evaluated_simulation(turn, config)
    |> Map.put("turn", turn)
    |> Map.put("artifact_hash", artifact_hash)
    |> Map.put("scenario_source", "interactive")
    |> Map.put("source", "interactive")
  end

  def simulate_recipe_turn(
        pattern_id,
        recipe_id,
        user_input,
        model_response,
        history_context,
        config \\ Wardwright.current_config()
      ) do
    simulate_recipe_turn_with_attempts(
      pattern_id,
      recipe_id,
      user_input,
      model_response,
      history_context,
      [],
      config
    )
  end

  def simulate_recipe_turn_with_attempts(
        pattern_id,
        recipe_id,
        user_input,
        model_response,
        history_context,
        response_attempts,
        config \\ Wardwright.current_config()
      ) do
    artifact_hash = artifact(pattern(pattern_id), config)["artifact_hash"]

    turn =
      simulation_turn(
        user_input,
        model_response,
        history_context,
        response_attempts
      )

    pattern_id
    |> evaluated_recipe_simulation(recipe_id, turn, config)
    |> Map.put("turn", turn)
    |> Map.put("artifact_hash", artifact_hash)
    |> Map.put("scenario_source", "interactive")
    |> Map.put("source", "interactive")
  end

  defp simulation_turn(user_input, model_response, history_context, response_attempts) do
    Map.new([
      {"user_input", user_input || ""},
      {"model_response", model_response || ""},
      {"response_attempts", normalize_response_attempts(response_attempts)},
      {"history_context", normalize_history_context(history_context)}
    ])
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp artifact(pattern, config) do
    normalized = %{
      "config_version" => Map.get(config, "version"),
      "governance" => Map.get(config, "governance", []),
      "pattern_id" => pattern["id"],
      "stream_rules" => Map.get(config, "stream_rules", []),
      "structured_output" => Map.get(config, "structured_output"),
      "tool_governance" => tool_governance_rules(config)
    }

    hash =
      :sha256
      |> :crypto.hash(Jason.encode!(normalized))
      |> Base.encode16(case: :lower)

    %{
      "artifact_hash" => "sha256:#{hash}",
      "artifact_id" => "#{pattern["id"]}-#{Map.get(config, "model_id", "policy")}",
      "normalized_format" => "yaml",
      "policy_version" => "draft.#{pattern["id"]}.001"
    }
  end

  defp engine("route-privacy", config) do
    route_rules = route_governance_rules(config)
    language = route_engine_language(route_rules)

    %{
      "capabilities" => %{
        "can_emit_source_spans" => Enum.any?(route_rules, &is_map(&1["source_span"])),
        "can_explain_trace" => true,
        "can_generate_scenarios" => true,
        "can_static_analyze" => language != "opaque",
        "phases" => ["route.selecting", "request.routing", "receipt.finalized"]
      },
      "display_name" => "Request route plan",
      "engine_id" => "request-route-plan",
      "language" => language,
      "version" => "0.1"
    }
  end

  defp engine("tool-governance", config) do
    tool_rules = tool_governance_rules(config)
    language = route_engine_language(tool_rules)

    %{
      "capabilities" => %{
        "can_emit_source_spans" => Enum.any?(tool_rules, &is_map(&1["source_span"])),
        "can_explain_trace" => true,
        "can_generate_scenarios" => true,
        "can_static_analyze" => language != "opaque",
        "phases" => ["tool.planning", "tool.result_interpreting", "tool.loop_governing", "receipt.finalized"]
      },
      "display_name" => "Tool context plan",
      "engine_id" => "tool-context-plan",
      "language" => language,
      "version" => "0.1"
    }
  end

  defp engine("ambiguous-success", _config) do
    %{
      "capabilities" => %{
        "can_emit_source_spans" => true,
        "can_explain_trace" => true,
        "can_generate_scenarios" => true,
        "can_static_analyze" => true,
        "phases" => ["output.finalizing", "receipt.finalized"]
      },
      "display_name" => "Hybrid output review",
      "engine_id" => "hybrid-output-review",
      "language" => "hybrid",
      "version" => "0.1"
    }
  end

  defp engine(_pattern_id, _config) do
    %{
      "capabilities" => %{
        "can_emit_source_spans" => false,
        "can_explain_trace" => true,
        "can_generate_scenarios" => true,
        "can_static_analyze" => true,
        "phases" => ["response.streaming", "receipt.finalized"]
      },
      "display_name" => "Structured stream primitives",
      "engine_id" => "structured-stream-primitives",
      "language" => "structured",
      "version" => "0.1"
    }
  end

  defp phases("ambiguous-success", _config) do
    [
      %{
        "description" => "Compare final text claims against expected artifact facts.",
        "id" => "output.finalizing",
        "nodes" => [
          node(
            "success.claim-detector",
            "completion claim",
            "primitive",
            "output.finalizing",
            "Detects final text that claims the work is done.",
            "exact",
            ["final.text"],
            ["policy.match"],
            ["classify_claim"]
          ),
          node(
            "success.artifact-check",
            "artifact check",
            "rule",
            "output.finalizing",
            "Checks whether required artifact metadata is present.",
            "declared",
            ["expected_artifacts", "receipt.metadata"],
            ["policy.action"],
            ["alert_operator", "annotate_receipt"]
          )
        ],
        "title" => "Final Output"
      }
    ]
  end

  defp phases("route-privacy", config) do
    nodes =
      config
      |> route_governance_rules()
      |> Enum.map(&request_governance_node/1)
      |> case do
        [] -> [no_route_gate_node()]
        configured -> configured
      end

    [
      %{
        "description" => "Project configured request governance before provider selection.",
        "id" => "route.selecting",
        "nodes" => nodes,
        "title" => "Route"
      }
    ]
  end

  defp phases("tool-governance", config) do
    rules = tool_governance_rules(config)

    planning_nodes =
      rules
      |> Enum.filter(&tool_planning_rule?/1)
      |> Enum.map(&tool_governance_node(&1, "tool.planning"))
      |> case do
        [] -> [no_tool_policy_node("tool.planning", "planning")]
        configured -> configured
      end

    result_nodes =
      rules
      |> Enum.filter(&tool_result_rule?/1)
      |> Enum.map(&tool_governance_node(&1, "tool.result_interpreting"))
      |> case do
        [] -> [no_tool_policy_node("tool.result_interpreting", "result")]
        configured -> configured
      end

    loop_nodes =
      rules
      |> Enum.filter(&tool_loop_rule?/1)
      |> Enum.map(&tool_governance_node(&1, "tool.loop_governing"))
      |> case do
        [] -> [no_tool_policy_node("tool.loop_governing", "loop")]
        configured -> configured
      end

    [
      %{
        "description" => "Review declared tools, explicit tool_choice, and planned assistant tool calls.",
        "id" => "tool.planning",
        "nodes" => planning_nodes,
        "title" => "Tool Planning"
      },
      %{
        "description" => "Review tool result status and hashed result evidence before the model interprets it.",
        "id" => "tool.result_interpreting",
        "nodes" => result_nodes,
        "title" => "Tool Results"
      },
      %{
        "description" => "Review repeated tool use over session history and configured loop budgets.",
        "id" => "tool.loop_governing",
        "nodes" => loop_nodes,
        "title" => "Tool Loop"
      },
      %{
        "description" => "Persist normalized tool context dimensions without raw arguments or raw results.",
        "id" => "receipt.finalized",
        "nodes" => [
          node(
            "tool.receipt-context",
            "tool receipt context",
            "receipt_rule",
            "receipt.finalized",
            "Record namespace, name, phase, risk class, provenance, call id, and hashes for audit/search.",
            "exact",
            ["decision.tool_context"],
            ["receipt.decision.tool_context", "receipt.summary.tool_*"],
            ["annotate_receipt"]
          )
        ],
        "title" => "Receipt"
      }
    ]
  end

  defp phases("stream-rewrite-state", _config) do
    [
      %{
        "description" => "Rewrite or remove request-side spans before the provider sees them.",
        "id" => "request.preparing",
        "nodes" => [
          node(
            "request.rewrite-context",
            "context redactor",
            "primitive",
            "request.preparing",
            "Remove private context spans from the model-facing prompt while keeping receipt evidence.",
            "exact",
            ["request.messages", "policy_cache.session.regex_match"],
            ["request.model_input", "policy.events"],
            ["match_regex", "rewrite_span"]
          )
        ],
        "title" => "Request"
      },
      %{
        "description" => "Evaluate related regex matches over held chunks before bytes are released.",
        "id" => "response.streaming",
        "nodes" => [
          node(
            "stream.redact-account",
            "account redactor",
            "primitive",
            "response.streaming",
            "Rewrite account-like spans inside the holdback window before release.",
            "exact",
            ["stream.window", "policy_cache.session.regex_match"],
            ["stream.rewrite_patch", "policy.events"],
            ["match_regex", "rewrite_span"]
          ),
          node(
            "stream.secret-transition",
            "secret transition",
            "primitive",
            "response.streaming",
            "Escalate if a related secret-token pattern appears after the account rewrite.",
            "exact",
            ["stream.window", "policy_cache.session.regex_match"],
            ["policy.state", "final.status"],
            ["match_regex", "state_transition"]
          ),
          node(
            "stream.rewrite-arbiter",
            "rewrite arbiter",
            "arbiter",
            "response.streaming",
            "Applies rewrite patches while preserving enough held context to detect related later matches.",
            "declared",
            ["stream.rewrite_patch", "policy.state"],
            ["stream.release_decision", "request.review_required"],
            ["release_rewritten", "hold_for_review"]
          )
        ],
        "title" => "Stream"
      },
      %{
        "description" => "Persist rewrite, transition, and review evidence.",
        "id" => "receipt.finalized",
        "nodes" => [
          node(
            "stream.rewrite-receipt",
            "rewrite receipt",
            "receipt_rule",
            "receipt.finalized",
            "Record regex matches, applied rewrite ranges, state transition, and withheld bytes hash.",
            "exact",
            ["policy.events", "stream.rewrite_patch", "policy.state"],
            ["receipt.events"],
            ["annotate_receipt"]
          )
        ],
        "title" => "Receipt"
      }
    ]
  end

  defp phases(_pattern_id, config) do
    stream_rules = Map.get(config, "stream_rules", [])

    [
      %{
        "description" => "Evaluate bounded stream windows before bytes are released.",
        "id" => "response.streaming",
        "nodes" => [
          node(
            "tts.no-old-client",
            "no-old-client",
            "primitive",
            "response.streaming",
            stream_summary(stream_rules),
            "exact",
            ["stream.window"],
            ["attempt.abort_reason"],
            ["match_regex", "abort_attempt"]
          ),
          node(
            "tts.retry-arbiter",
            "retry arbiter",
            "arbiter",
            "response.streaming",
            "Retry once with a reminder, then block final output on repeat violation.",
            "exact",
            ["attempt.retry_count", "policy.match"],
            ["request.system_reminder", "final.status"],
            ["retry_with_reminder", "block_final"]
          )
        ],
        "title" => "Stream"
      },
      %{
        "description" => "Persist policy events for audit and future regression fixtures.",
        "id" => "receipt.finalized",
        "nodes" => [
          node(
            "tts.receipt-events",
            "receipt events",
            "rule",
            "receipt.finalized",
            "Record stream hold, match, abort, retry, and final status events.",
            "exact",
            ["policy.events", "attempt.status"],
            ["receipt.events"],
            ["annotate_receipt"]
          )
        ],
        "title" => "Receipt"
      }
    ]
  end

  defp node(id, label, kind, phase, summary, confidence, reads, writes, actions, source_span \\ nil) do
    %Contract.Node{
      actions: actions,
      annotations: node_annotations(kind, actions, confidence),
      confidence: confidence,
      id: id,
      label: label,
      node_class: kind,
      phase: phase,
      reads: reads,
      source_span: source_span,
      summary: summary,
      writes: writes
    }
    |> Contract.to_map()
  end

  defp node_annotations("plan_gap", _actions, _confidence) do
    %Contract.Annotation{
      change_when: "Add or import a recipe when this gap represents a real governance need.",
      review_hint: "Safe as a reminder, but unsafe if operators assume enforcement is active.",
      why: "This marks an explicit gap where no configured rule currently applies."
    }
  end

  defp node_annotations(_kind, [], "opaque") do
    %Contract.Annotation{
      change_when: "Replace opaque policy code with declared primitives when visual review matters.",
      review_hint: "Treat simulation evidence as required before trusting this branch.",
      why: "This part exists because the projection could not reduce the policy into exact primitives."
    }
  end

  defp node_annotations(_kind, [], confidence) do
    %Contract.Annotation{
      change_when: "Review when the policy needs different evidence, receipt fields, or routing context.",
      review_hint: "Confidence is #{confidence}; inspect reads and writes before changing this rule.",
      why: "This node records evidence or context used by nearby policy decisions."
    }
  end

  defp node_annotations(_kind, actions, confidence) do
    %Contract.Annotation{
      change_when: "Review when provider behavior, tool permissions, route costs, or policy intent changes.",
      review_hint: "Confidence is #{confidence}; inspect reads and writes before changing this rule.",
      why: "This node explains when Wardwright may #{Enum.join(actions, ", ")}."
    }
  end

  defp compiled_plan(pattern_id, config, phases) do
    %{
      "node_count" => phases |> Enum.flat_map(& &1["nodes"]) |> length(),
      "pattern_id" => pattern_id,
      "planner" => "Wardwright.Policy.Plan",
      "request_rule_count" => length(Map.get(config, "governance", [])),
      "source" => "current_config",
      "stream_rule_count" => length(Map.get(config, "stream_rules", []))
    }
  end

  defp state_machine("tts-retry", phases, config) do
    states = [
      state(
        "observing",
        "Observing",
        "Hold unreleased stream chunks while matching configured stream rules.",
        ["tts.no-old-client"],
        model_id: Wardwright.local_model(),
        model_reason:
          "The first attempt starts on the default local route while Wardwright holds a short stream horizon before release."
      ),
      state(
        "guarding",
        "Guarding",
        "A prohibited span has matched before release; current attempt must stop.",
        ["tts.no-old-client", "tts.retry-arbiter"],
        model_id: "none",
        model_reason: "The guard stops the active provider stream before any matched bytes are released to the user."
      ),
      state(
        "retrying",
        "Retrying",
        "Retry arbitration adds a reminder or resolves repeat violation to final block.",
        ["tts.retry-arbiter"],
        model_id: Wardwright.managed_model(),
        model_reason:
          "The retry attempt can be rerouted to a review-capable managed model with the policy reminder attached."
      ),
      state(
        "recording",
        "Recording",
        "Receipt facts persist the held bytes, match, abort, retry, and final status.",
        ["tts.receipt-events"],
        terminal: true,
        model_id: "none",
        model_reason: "Receipt recording does not call a provider model."
      )
    ]

    %Contract.StateMachine{
      default_projection: false,
      initial_state: "observing",
      simulation_steps: simulation_steps("tts-retry", config, states),
      states: states,
      summary: "Explicit retry loop projection for stream guard, abort, retry, and receipt recording.",
      transitions: [
        transition(
          "stream.match",
          "observing",
          "guarding",
          "stream window matches a prohibited span",
          "abort_attempt",
          "tts.no-old-client"
        ),
        transition(
          "attempt.retry",
          "guarding",
          "retrying",
          "retry budget remains",
          "retry_with_reminder",
          "tts.retry-arbiter"
        ),
        transition(
          "receipt.write",
          "retrying",
          "recording",
          "attempt outcome is known",
          "annotate_receipt",
          "tts.receipt-events"
        )
      ]
    }
    |> Contract.to_map()
    |> attach_state_node_fallback(phases)
  end

  defp state_machine("stream-rewrite-state", phases, config) do
    states = [
      state(
        "observing",
        "Observing",
        "Rewrite request-side private context, then hold chunks and scan for related regex matches.",
        ["request.rewrite-context", "stream.redact-account"],
        model_id: Wardwright.local_model(),
        model_reason:
          "Default local route while private context is being removed and streamed output is still safe to inspect locally."
      ),
      state(
        "rewriting",
        "Rewriting",
        "A safe rewrite patch is available but more related stream context is still held.",
        ["stream.redact-account", "stream.rewrite-arbiter"],
        model_id: Wardwright.local_model(),
        model_reason: "Continue local handling while Wardwright decides whether rewritten output can be released."
      ),
      state(
        "review_required",
        "Review Required",
        "A later related secret-token match prevents normal release.",
        ["stream.secret-transition", "stream.rewrite-arbiter"],
        model_id: Wardwright.managed_model(),
        model_reason:
          "Future turns in this session should use the review-capable managed route unless the policy is cleared."
      ),
      state(
        "recording",
        "Recording",
        "Persist rewrite and transition evidence for review and regression fixtures.",
        ["stream.rewrite-receipt"],
        terminal: true,
        model_id: "none",
        model_reason: "Receipt recording does not call a provider model."
      )
    ]

    %Contract.StateMachine{
      default_projection: false,
      initial_state: "observing",
      simulation_steps: simulation_steps("stream-rewrite-state", config, states),
      states: states,
      summary:
        "Explicit projection for related stream regex matches, rewrite, state transition, and receipt recording.",
      transitions: [
        transition(
          "request.rewrite",
          "observing",
          "observing",
          "private context is removed before provider dispatch",
          "rewrite_span",
          "request.rewrite-context"
        ),
        transition(
          "regex.rewrite",
          "observing",
          "rewriting",
          "account-like regex match is safe to rewrite",
          "rewrite_span",
          "stream.redact-account"
        ),
        transition(
          "regex.related-secret",
          "rewriting",
          "review_required",
          "related secret-token regex appears after a rewrite",
          "state_transition",
          "stream.secret-transition"
        ),
        transition(
          "receipt.write",
          "review_required",
          "recording",
          "review outcome is known",
          "annotate_receipt",
          "stream.rewrite-receipt"
        )
      ]
    }
    |> Contract.to_map()
    |> attach_state_node_fallback(phases)
  end

  defp state_machine(pattern_id, phases, config) do
    states = [
      state(
        "active",
        "Active",
        "Evaluate configured phases without a separate user-authored state model.",
        phase_node_ids(phases)
      )
    ]

    %Contract.StateMachine{
      default_projection: true,
      initial_state: "active",
      simulation_steps: simulation_steps(pattern_id, config, states),
      states: states,
      summary: "Default one-state projection for policies without explicit stateful control flow.",
      transitions: []
    }
    |> Contract.to_map()
  end

  defp attach_state_node_fallback(state_machine, phases) do
    known_node_ids = phase_node_ids(phases) |> MapSet.new()

    states =
      state_machine["states"]
      |> Enum.map(fn state ->
        node_ids = Enum.filter(state["node_ids"], &MapSet.member?(known_node_ids, &1))
        Map.put(state, "node_ids", node_ids)
      end)

    Map.put(state_machine, "states", states)
  end

  defp state(id, label, summary, node_ids, opts \\ []) do
    %Contract.State{
      id: id,
      label: label,
      model_id: Keyword.get(opts, :model_id),
      model_reason: Keyword.get(opts, :model_reason),
      node_ids: node_ids,
      summary: summary,
      terminal: Keyword.get(opts, :terminal, false)
    }
  end

  defp transition(id, from, to, trigger, action, node_id) do
    %Contract.Transition{
      action: action,
      from: from,
      id: id,
      node_id: node_id,
      to: to,
      trigger: trigger
    }
  end

  defp simulation_steps(pattern_id, config, states) do
    pattern_id
    |> simulation_records(config)
    |> List.first(%{})
    |> Map.get("trace", [])
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      state_id = trace_state(event, states)

      %Contract.StateStep{
        event_id: event["id"],
        node_id: event["node_id"],
        severity: event["severity"],
        state: state_id,
        step: index,
        summary: event["label"]
      }
    end)
  end

  defp trace_state(%{"state_id" => state_id}, states) when is_binary(state_id) and state_id != "" do
    if Enum.any?(states, &(&1.id == state_id)) do
      state_id
    else
      raise ArgumentError,
            "simulation trace references unknown state_id #{inspect(state_id)}"
    end
  end

  defp trace_state(%{"node_id" => node_id}, states) when is_binary(node_id) do
    states
    |> Enum.find(first_state(states), fn state -> node_id in state.node_ids end)
    |> Map.fetch!(:id)
  end

  defp trace_state(_event, states), do: first_state(states).id

  defp first_state([state | _states]), do: state

  defp phase_node_ids(phases) do
    phases
    |> Enum.flat_map(& &1["nodes"])
    |> Enum.map(& &1["id"])
  end

  defp route_governance_rules(config) do
    config
    |> Map.get("governance", [])
    |> Enum.filter(fn rule ->
      action = Map.get(rule, "action")
      kind = Map.get(rule, "kind")

      kind == "route_gate" or action in ["restrict_routes", "switch_model", "reroute"] or
        Map.get(rule, "engine") in ["starlark", "dune", "wasm", "hybrid"]
    end)
  end

  defp tool_governance_rules(config) do
    config
    |> Map.get("governance", [])
    |> Enum.filter(fn rule ->
      kind = Map.get(rule, "kind")
      phase = Map.get(rule, "phase")

      kind in [
        "tool_selector",
        "tool_allowlist",
        "tool_denylist",
        "tool_loop_threshold",
        @tool_sequence_kind,
        "tool_result_guard"
      ] or
        phase in [
          "tool.planning",
          "tool.result_interpreting",
          "tool.loop_governing",
          "tool.using"
        ]
    end)
  end

  defp tool_planning_rule?(rule) do
    Map.get(rule, "kind") in ["tool_selector", "tool_allowlist", "tool_denylist"] or
      Map.get(rule, "phase") in ["tool.planning", "tool.using"]
  end

  defp tool_result_rule?(rule) do
    Map.get(rule, "kind") == "tool_result_guard" or
      Map.get(rule, "phase") == "tool.result_interpreting"
  end

  defp tool_loop_rule?(rule) do
    Map.get(rule, @kind_key) in [@tool_loop_threshold_kind, @tool_sequence_kind] or
      Map.get(rule, "phase") == "tool.loop_governing"
  end

  defp route_engine_language([]), do: "structured"

  defp route_engine_language(rules) do
    rules
    |> Enum.map(&Map.get(&1, "engine"))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> case do
      [] -> "structured"
      [language] -> language
      _many -> "hybrid"
    end
  end

  defp request_governance_node(rule) do
    action = request_governance_action(rule)
    action_name = Map.get(action, "action", "annotate")

    node(
      "request-policy.#{safe_id(Map.get(rule, "id", action_name))}",
      Map.get(rule, "label", Map.get(rule, "id", action_name)),
      request_governance_kind(rule),
      "route.selecting",
      request_governance_summary(rule, action),
      request_governance_confidence(rule),
      request_governance_reads(rule),
      request_governance_writes(action),
      [action_name],
      Map.get(rule, "source_span")
    )
  end

  defp request_governance_action(rule) do
    %{
      "action" => Map.get(rule, "action", default_projected_action(rule)),
      "allow_fallback" => Map.get(rule, "allow_fallback"),
      "allowed_targets" => Map.get(rule, "allowed_targets"),
      "kind" => Map.get(rule, "kind", "route_gate"),
      "message" => Map.get(rule, "message", "route governance rule"),
      "rule_id" => Map.get(rule, "id", "route-policy"),
      "target_model" => Map.get(rule, "target_model", Map.get(rule, "model"))
    }
    |> Action.normalize(rule: rule)
  end

  defp default_projected_action(rule) do
    engine = Map.get(rule, "engine")

    :wardwright@projection_core.route_action("", engine not in [nil, ""])
    |> case do
      "engine_decision" -> "engine_result"
      action -> action
    end
  end

  defp request_governance_kind(%{"engine" => engine}) when engine not in [nil, ""], do: "policy_engine"

  defp request_governance_kind(rule), do: Map.get(rule, "kind", "route_gate")

  defp request_governance_summary(rule, action) do
    message = Map.get(rule, "message", Map.get(action, "message", "route governance rule"))
    "#{Map.get(action, "action", "annotate")} when #{rule_match_summary(rule)}: #{message}"
  end

  defp rule_match_summary(rule) do
    cond do
      is_binary(rule["contains"]) and rule["contains"] != "" ->
        "request contains #{inspect(rule["contains"])}"

      is_binary(rule["regex"]) and rule["regex"] != "" ->
        "request matches #{inspect(rule["regex"])}"

      is_binary(rule["pattern"]) and rule["pattern"] != "" ->
        "request contains #{inspect(rule["pattern"])}"

      true ->
        "rule matches"
    end
  end

  defp request_governance_confidence(%{"engine" => engine}) when engine not in [nil, ""] do
    if is_map(engine) or engine == "hybrid" do
      "inferred"
    else
      :wardwright@projection_core.route_confidence(true)
    end
  end

  defp request_governance_confidence(_rule) do
    :wardwright@projection_core.route_confidence(false)
  end

  defp request_governance_reads(%{"kind" => "history_threshold"}), do: ["request.messages", "policy_cache.session"]

  defp request_governance_reads(%{"kind" => "history_regex_threshold"}),
    do: ["request.messages", "policy_cache.session"]

  defp request_governance_reads(_rule), do: ["request.messages", "caller", "route.candidates"]

  defp request_governance_writes(%{"action" => "restrict_routes"}), do: ["route.allowed_targets"]

  defp request_governance_writes(%{"action" => action}) when action in ["switch_model", "reroute"],
    do: ["route.forced_model"]

  defp request_governance_writes(%{"action" => "block"}), do: ["decision.blocked"]
  defp request_governance_writes(_action), do: ["policy.actions"]

  defp no_route_gate_node do
    node(
      "request-policy.no-route-gate",
      "no route gate configured",
      "plan_gap",
      "route.selecting",
      "No route-affecting governance rule is present in the active configuration.",
      "exact",
      ["governance"],
      [],
      []
    )
  end

  defp tool_governance_node(rule, phase) do
    id = Map.get(rule, "id", Map.get(rule, "kind", "tool-policy"))
    action = Map.get(rule, "action", default_tool_action(rule))

    node(
      "tool-policy.#{safe_id(id)}",
      Map.get(rule, "label", id),
      Map.get(rule, "kind", "tool_policy"),
      phase,
      tool_governance_summary(rule, action),
      tool_governance_confidence(rule),
      tool_governance_reads(rule, phase),
      tool_governance_writes(action),
      [action],
      Map.get(rule, "source_span")
    )
  end

  defp default_tool_action(rule) do
    :wardwright@projection_core.tool_action(
      Map.get(rule, @kind_key, ""),
      Map.get(rule, @action_key, ""),
      get_in(rule, [@then_key, @action_key]) || "",
      Map.get(rule, @transition_to_key, "")
    )
  end

  defp tool_governance_summary(rule, action) do
    "#{action} when #{tool_match_summary(rule)}"
  end

  defp tool_match_summary(rule) do
    tool = Map.get(rule, "tool", %{})

    matcher =
      [
        {"namespace", Map.get(rule, "namespace", Map.get(tool, "namespace"))},
        {"name", Map.get(rule, "name", Map.get(tool, "name"))},
        {"risk_class", Map.get(rule, "risk_class", Map.get(tool, "risk_class"))},
        {"phase", Map.get(rule, "phase", Map.get(tool, "phase"))}
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)

    cond do
      matcher != "" -> matcher
      is_integer(Map.get(rule, "threshold")) -> "tool count >= #{Map.get(rule, "threshold")}"
      true -> "tool context matches"
    end
  end

  defp tool_governance_confidence(%{"engine" => engine}) when engine not in [nil, ""] do
    if is_map(engine) or engine == "hybrid", do: "inferred", else: "opaque"
  end

  defp tool_governance_confidence(_rule), do: "declared"

  defp tool_governance_reads(%{"kind" => "tool_loop_threshold"}, _phase),
    do: ["decision.tool_context", "policy_cache.session.tool_call"]

  defp tool_governance_reads(%{@kind_key => @tool_sequence_kind}, _phase),
    do: [@decision_tool_context_read, @policy_cache_tool_call_read, @policy_cache_state_read]

  defp tool_governance_reads(_rule, "tool.result_interpreting"),
    do: ["decision.tool_context", "tool.result_hash", "tool.result_status"]

  defp tool_governance_reads(_rule, _phase),
    do: ["request.tools", "request.tool_choice", "message.tool_calls", "decision.tool_context"]

  defp tool_governance_writes("deny_tool"), do: ["decision.blocked", "tool.allowed"]
  defp tool_governance_writes("fail_closed"), do: ["decision.blocked", "final.status"]
  defp tool_governance_writes("review_result"), do: ["policy.actions", "receipt.events"]

  defp tool_governance_writes(@state_transition_action), do: [@policy_actions_write, @policy_cache_state_read]

  defp tool_governance_writes(_action), do: ["tool.allowed", "policy.actions"]

  defp no_tool_policy_node(phase, label) do
    node(
      "tool-policy.no-#{safe_id(label)}-policy",
      "no #{label} tool policy",
      "plan_gap",
      phase,
      "No #{label} tool-governance rule is present in the active configuration.",
      "exact",
      ["governance", "decision.tool_context"],
      [],
      []
    )
  end

  defp stream_summary([]), do: "Match prohibited output inside the unreleased stream horizon."

  defp stream_summary(rules) do
    ids =
      rules
      |> Enum.map_join(", ", &Map.get(&1, "id", "stream-rule"))

    "Project configured stream rules into a holdback detector: #{ids}."
  end

  defp safe_id(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "policy"
      safe -> safe
    end
  end

  defp effects("ambiguous-success", _config) do
    [
      effect(
        "effect.alert",
        "success.artifact-check",
        "output.finalizing",
        "alert_operator",
        "operator",
        "declared"
      ),
      effect(
        "effect.annotate",
        "success.artifact-check",
        "receipt.finalized",
        "annotate",
        "receipt",
        "declared"
      )
    ]
  end

  defp effects("route-privacy", config) do
    config
    |> route_governance_rules()
    |> Enum.map(&request_governance_action/1)
    |> Enum.with_index()
    |> Enum.map(fn {action, index} ->
      effect(
        "effect.route-policy-#{index + 1}",
        "request-policy.#{safe_id(Map.get(action, "rule_id", "route-policy"))}",
        "route.selecting",
        Map.get(action, "action", "annotate"),
        route_effect_target(action),
        Map.get(action, "source", %{}) |> Map.get("type") |> effect_confidence()
      )
    end)
  end

  defp effects("tool-governance", config) do
    rules = tool_governance_rules(config)

    effects =
      rules
      |> Enum.map(fn rule ->
        action = Map.get(rule, "action", default_tool_action(rule))

        effect(
          "effect.tool-policy-#{safe_id(Map.get(rule, "id", action))}",
          "tool-policy.#{safe_id(Map.get(rule, "id", action))}",
          tool_rule_phase(rule),
          action,
          tool_effect_target(action),
          tool_governance_confidence(rule)
        )
      end)

    effects ++
      [
        effect(
          "effect.tool-receipt",
          "tool.receipt-context",
          "receipt.finalized",
          "annotate_receipt",
          "receipt",
          "exact"
        )
      ]
  end

  defp effects("stream-rewrite-state", _config) do
    [
      effect(
        "effect.request-rewrite",
        "request.rewrite-context",
        "request.preparing",
        "rewrite_span",
        "request",
        "exact"
      ),
      effect(
        "effect.stream-rewrite",
        "stream.redact-account",
        "response.streaming",
        "rewrite_span",
        "stream",
        "exact"
      ),
      effect(
        "effect.stream-transition",
        "stream.secret-transition",
        "response.streaming",
        "state_transition",
        "policy_state",
        "exact"
      ),
      effect(
        "effect.stream-review",
        "stream.rewrite-arbiter",
        "response.streaming",
        "hold_for_review",
        "request",
        "declared"
      ),
      effect(
        "effect.stream-receipt",
        "stream.rewrite-receipt",
        "receipt.finalized",
        "annotate_receipt",
        "receipt",
        "exact"
      )
    ]
  end

  defp effects(_pattern_id, _config) do
    [
      effect(
        "effect.abort",
        "tts.no-old-client",
        "response.streaming",
        "abort_attempt",
        "attempt",
        "exact"
      ),
      effect(
        "effect.retry",
        "tts.retry-arbiter",
        "response.streaming",
        "retry_with_reminder",
        "request",
        "exact"
      ),
      effect(
        "effect.block",
        "tts.retry-arbiter",
        "response.streaming",
        "block_final",
        "final",
        "exact"
      ),
      effect(
        "effect.receipt",
        "tts.receipt-events",
        "receipt.finalized",
        "annotate",
        "receipt",
        "exact"
      )
    ]
  end

  defp route_effect_target(action) do
    action = Map.get(action, "action", "")
    :wardwright@projection_core.route_effect_target(action)
  end

  defp tool_rule_phase(rule) do
    :wardwright@projection_core.tool_rule_phase(
      tool_loop_rule?(rule),
      tool_result_rule?(rule)
    )
  end

  defp tool_effect_target(action) do
    :wardwright@projection_core.tool_effect_target(action)
  end

  defp effect_confidence(source_type) do
    source_type = to_string(source_type || "")
    :wardwright@projection_core.effect_confidence(source_type)
  end

  defp effect(id, node_id, phase, effect, target, confidence) do
    %Contract.Effect{
      confidence: confidence,
      effect: effect,
      id: id,
      node_id: node_id,
      phase: phase,
      target: target
    }
    |> Contract.to_map()
  end

  defp conflicts("ambiguous-success", _config) do
    [
      %{
        "class" => "ambiguous",
        "id" => "conflict.block-alert-choice",
        "node_ids" => ["success.artifact-check"],
        "required_resolution" => "select alert-only or block-final before activation",
        "summary" => "The artifact can alert or block; activation needs the operator to choose the promise."
      }
    ]
  end

  defp conflicts("route-privacy", config) do
    config
    |> route_governance_rules()
    |> Enum.map(&request_governance_action/1)
    |> Action.conflicts()
    |> Enum.map(fn conflict ->
      rule_ids = Map.get(conflict, "rule_ids", [])

      %{
        "class" => Map.get(conflict, "class", "ordered"),
        "id" => "conflict.#{Map.get(conflict, "key", "policy")}",
        "node_ids" => Enum.map(rule_ids, &"request-policy.#{safe_id(&1)}"),
        "required_resolution" => Map.get(conflict, "required_resolution"),
        "summary" => Map.get(conflict, "summary")
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
      |> Map.new()
    end)
  end

  defp conflicts("tool-governance", config) do
    config
    |> tool_governance_rules()
    |> Enum.group_by(&tool_rule_phase/1)
    |> Enum.flat_map(fn {phase, rules} ->
      if length(rules) > 1 do
        [
          %{
            "class" => "ordered",
            "id" => "conflict.tool-policy.#{safe_id(phase)}",
            "node_ids" => Enum.map(rules, &"tool-policy.#{safe_id(Map.get(&1, "id", "tool-policy"))}"),
            "required_resolution" =>
              "declare priority, mutual exclusivity, or an allow/deny precedence contract before enforcement",
            "summary" =>
              "Multiple tool-governance rules can affect #{phase}; activation needs explicit priority or proof that actions do not conflict."
          }
        ]
      else
        []
      end
    end)
  end

  defp conflicts("stream-rewrite-state", _config) do
    [
      %{
        "class" => "ordered",
        "id" => "conflict.rewrite-before-transition",
        "node_ids" => ["stream.redact-account", "stream.secret-transition"],
        "required_resolution" => "preserve enough held context after rewriting to evaluate related transition rules",
        "summary" =>
          "The safe rewrite may run, but a later related secret-token match can still force review before release."
      }
    ]
  end

  defp conflicts(_pattern_id, _config) do
    [
      %{
        "class" => "ordered",
        "id" => "conflict.retry-block-order",
        "node_ids" => ["tts.no-old-client", "tts.retry-arbiter"],
        "required_resolution" => "priority order is encoded by the compiled stream plan",
        "summary" => "Abort happens before retry arbitration; repeated violation resolves to block_final."
      }
    ]
  end

  defp opaque_regions("route-privacy", config) do
    config
    |> route_governance_rules()
    |> Enum.filter(fn rule -> request_governance_confidence(rule) == "opaque" end)
    |> Enum.map(fn rule ->
      %{
        "id" => "opaque.#{safe_id(Map.get(rule, "id", "route-policy"))}",
        "node_id" => "request-policy.#{safe_id(Map.get(rule, "id", "route-policy"))}",
        "reason" =>
          "Sandboxed route policy is represented through its action contract; static adapter cannot prove every internal branch.",
        "review_requirement" => "Require scenario coverage for route denial, allowed fallback, and no-match cases."
      }
    end)
  end

  defp opaque_regions("tool-governance", config) do
    config
    |> tool_governance_rules()
    |> Enum.filter(fn rule -> tool_governance_confidence(rule) == "opaque" end)
    |> Enum.map(fn rule ->
      %{
        "id" => "opaque.#{safe_id(Map.get(rule, "id", "tool-policy"))}",
        "node_id" => "tool-policy.#{safe_id(Map.get(rule, "id", "tool-policy"))}",
        "reason" =>
          "Sandboxed tool policy is represented through its declared action contract; static adapter cannot prove every internal branch.",
        "review_requirement" =>
          "Require scenario coverage for allow, deny, loop-threshold, and result-status cases before activation."
      }
    end)
  end

  defp opaque_regions(_pattern_id, _config), do: []

  defp warnings("route-privacy", config) do
    if route_governance_rules(config) == [] do
      ["No route-affecting governance rule is configured for this projection."]
    else
      []
    end
  end

  defp warnings("tool-governance", config) do
    if tool_governance_rules(config) == [] do
      [
        "Tool context is normalized and recorded, but no tool-governance rule is configured for enforcement."
      ]
    else
      [
        "Tool-context provenance is evidence only; caller-provided metadata must not be treated as trusted execution fact."
      ]
    end
  end

  defp warnings("ambiguous-success", _config) do
    [
      "Classifier wording can drift; pin generated false-positive examples as regression fixtures."
    ]
  end

  defp warnings(_pattern_id, _config), do: ["Adds stream latency up to the configured holdback horizon."]

  defp simulation_records(pattern_id, config) do
    case Wardwright.PolicyScenarioStore.list(pattern_id) do
      [] -> simulation_cases(pattern_id, config)
      scenarios -> Enum.map(scenarios, &Wardwright.PolicyScenario.to_map/1)
    end
  end

  defp simulation_cases("ambiguous-success", config), do: ambiguous_success_simulation_cases(config)

  defp simulation_cases("route-privacy", config), do: route_privacy_simulation_cases(config)
  defp simulation_cases("tool-governance", config), do: tool_governance_simulation_cases(config)

  defp simulation_cases("stream-rewrite-state", config), do: stream_rewrite_simulation_cases(config)

  defp simulation_cases(pattern_id, config), do: default_simulation_cases(pattern_id, config)

  defp evaluated_simulation("ambiguous-success", turn, config), do: evaluated_ambiguous_success_simulation(turn, config)

  defp evaluated_simulation("stream-rewrite-state", turn, config), do: evaluated_stream_rewrite_simulation(turn, config)

  defp evaluated_simulation("tts-retry", turn, config), do: evaluated_tts_retry_simulation(turn, config)

  defp evaluated_simulation(pattern_id, _turn, config) do
    pattern_id
    |> simulations(config)
    |> List.first()
  end

  defp evaluated_recipe_simulation("ambiguous-success", "structured-output-repair-gate", turn, _config),
    do: evaluated_structured_output_simulation(turn)

  defp evaluated_recipe_simulation(pattern_id, _recipe_id, turn, config),
    do: evaluated_simulation(pattern_id, turn, config)

  defp ambiguous_success_simulation_cases(_config) do
    [
      %{
        "engine_id" => "hybrid-output-review",
        "expected_behavior" => "Receipt is annotated and operator alert is emitted.",
        "input_summary" => "Final answer says export is ready, but artifact metadata is empty.",
        "receipt_preview" => %{
          "events" => [%{"rule_id" => "missing-artifact-after-success", "type" => "policy.alert"}],
          "final_status" => "completed_with_alert"
        },
        "scenario_id" => "missing-artifact",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Completion claim missing artifact",
        "trace" => [
          trace(
            "a1",
            "output.finalizing",
            "success.claim-detector",
            "match",
            "claim detected",
            "final text contains completed/ready language",
            "warn"
          ),
          trace(
            "a2",
            "output.finalizing",
            "success.artifact-check",
            "state_read",
            "metadata missing",
            "expected artifact slot has no attached export",
            "warn"
          ),
          trace(
            "a3",
            "receipt.finalized",
            "success.artifact-check",
            "action",
            "alert emitted",
            "operator alert and receipt annotation would be recorded",
            "pass"
          )
        ],
        "verdict" => "passed"
      }
      |> fixture_case()
    ]
  end

  defp evaluated_ambiguous_success_simulation(turn, _config) do
    text = turn_response(turn)
    has_claim? = Regex.match?(~r/\b(done|ready|completed|finished|export)\b/i, text)
    has_artifact? = Regex.match?(~r/\b(artifact|attachment|download_id|file_id):\s*\S+/i, text)

    if has_claim? and not has_artifact? do
      %{
        "engine_id" => "hybrid-output-review",
        "expected_behavior" => "Completion language without artifact evidence emits an operator alert.",
        "input_summary" => summarize_turn(turn),
        "receipt_preview" => %{
          "events" => [%{"rule_id" => "missing-artifact-after-success", "type" => "policy.alert"}],
          "final_status" => "completed_with_alert",
          "input" => turn
        },
        "scenario_id" => "interactive-ambiguous-success-alert",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Edited input triggers missing artifact alert",
        "trace" => [
          trace(
            "i1",
            "output.finalizing",
            "success.claim-detector",
            "match",
            "claim detected",
            "edited final text contains completion language",
            "warn"
          ),
          trace(
            "i2",
            "output.finalizing",
            "success.artifact-check",
            "state_read",
            "metadata missing",
            "no artifact marker was found in the edited input",
            "warn"
          ),
          trace(
            "i3",
            "receipt.finalized",
            "success.artifact-check",
            "action",
            "alert emitted",
            "operator alert and receipt annotation would be recorded",
            "pass"
          )
        ],
        "verdict" => "passed"
      }
    else
      %{
        "engine_id" => "hybrid-output-review",
        "expected_behavior" => "No alert is emitted unless completion language lacks artifact evidence.",
        "input_summary" => summarize_turn(turn),
        "receipt_preview" => %{"events" => [], "final_status" => "completed", "input" => turn},
        "scenario_id" => "interactive-ambiguous-success-clear",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Edited input clears missing artifact alert",
        "trace" => [
          trace(
            "i1",
            "output.finalizing",
            "success.claim-detector",
            "input",
            "final text reviewed",
            "edited final text was evaluated for completion language and artifact evidence",
            "info"
          ),
          trace(
            "i2",
            "receipt.finalized",
            "success.artifact-check",
            "receipt_event",
            "no alert",
            "artifact evidence is present or no completion claim was made",
            "pass"
          )
        ],
        "verdict" => "passed"
      }
    end
  end

  defp evaluated_structured_output_simulation(turn) do
    text = turn_response(turn)

    case Jason.decode(text) do
      {:error, _reason} ->
        structured_output_retry_simulation(
          turn,
          "interactive-structured-output-malformed",
          "Edited JSON triggers repair retry",
          "Provider output is not parseable JSON for the promised Wardwright model contract.",
          "json parse failed",
          "retry_with_validation_feedback"
        )

      {:ok, decoded} ->
        if structured_output_has_evidence?(decoded) do
          %{
            "engine_id" => "hybrid-output-review",
            "expected_behavior" => "The parsed JSON satisfies one accepted branch of the Wardwright model contract.",
            "input_summary" => summarize_turn(turn),
            "receipt_preview" => %{
              "events" => [%{"rule_id" => "structured-output-repair-gate", "type" => "structured_output.accepted"}],
              "final_status" => "completed",
              "input" => turn
            },
            "scenario_id" => "interactive-structured-output-valid",
            "simulation_schema" => "wardwright.policy_simulation.v1",
            "title" => "Edited JSON satisfies an accepted schema branch",
            "trace" => [
              trace(
                "j1",
                "output.finalizing",
                "structured-output.parser",
                "match",
                "json parsed",
                "response decoded as JSON",
                "pass"
              ),
              trace(
                "j2",
                "output.finalizing",
                "structured-output.schema-branch",
                "state_read",
                "accepted schema branch",
                "artifact evidence field is present in an accepted output shape",
                "pass"
              ),
              trace(
                "j3",
                "receipt.finalized",
                "structured-output.receipt",
                "receipt_event",
                "contract recorded",
                "selected schema branch and evidence path would be recorded",
                "pass"
              )
            ],
            "verdict" => "passed"
          }
        else
          structured_output_retry_simulation(
            turn,
            "interactive-structured-output-missing-evidence",
            "Edited JSON parses but misses contract evidence",
            "The JSON parses, but no accepted schema branch includes artifact evidence.",
            "artifact evidence missing",
            "retry_with_validation_feedback"
          )
        end
    end
  end

  defp structured_output_retry_simulation(turn, scenario_id, title, expected_behavior, match_detail, action_label) do
    %{
      "engine_id" => "hybrid-output-review",
      "expected_behavior" => expected_behavior,
      "input_summary" => summarize_turn(turn),
      "receipt_preview" => %{
        "events" => [%{"rule_id" => "structured-output-repair-gate", "type" => "structured_output.retry_requested"}],
        "final_status" => "retry_requested",
        "input" => turn
      },
      "scenario_id" => scenario_id,
      "simulation_schema" => "wardwright.policy_simulation.v1",
      "title" => title,
      "trace" => [
        trace(
          "j1",
          "output.finalizing",
          "structured-output.parser",
          "match",
          match_detail,
          "response does not satisfy the promised structured-output contract",
          "warn"
        ),
        trace(
          "j2",
          "output.finalizing",
          "structured-output.repair",
          "action",
          action_label,
          "Wardwright would retry with validation feedback before accepting or blocking",
          "warn"
        ),
        trace(
          "j3",
          "receipt.finalized",
          "structured-output.receipt",
          "receipt_event",
          "repair evidence recorded",
          "receipt records parse/schema failure and retry request",
          "pass"
        )
      ],
      "verdict" => "passed"
    }
  end

  defp structured_output_has_evidence?(%{"artifact_id" => value}) when value not in [nil, ""], do: true

  defp structured_output_has_evidence?(%{"file_id" => value}) when value not in [nil, ""], do: true

  defp structured_output_has_evidence?(%{"download_id" => value}) when value not in [nil, ""], do: true

  defp structured_output_has_evidence?(%{"evidence" => evidence}) when is_map(evidence),
    do: structured_output_has_evidence?(evidence)

  defp structured_output_has_evidence?(%{"result" => result}) when is_map(result),
    do: structured_output_has_evidence?(result)

  defp structured_output_has_evidence?(_decoded), do: false

  defp route_privacy_simulation_cases(config) do
    rules = route_governance_rules(config)

    case rules do
      [] -> no_route_gate_simulation()
      _configured -> [route_governance_simulation(config, rules)]
    end
  end

  defp tool_governance_simulation_cases(config) do
    rules = tool_governance_rules(config)

    case rules do
      [] -> [no_tool_governance_simulation()]
      _configured -> [tool_governance_simulation(rules)]
    end
  end

  defp stream_rewrite_simulation_cases(_config) do
    [
      %{
        "engine_id" => "structured-stream-primitives",
        "expected_behavior" =>
          "Account span is rewritten, later secret-token match transitions to review_required, and no unsafe bytes are released.",
        "input_summary" =>
          "Provider emits an account identifier, then a related secret token inside the held stream horizon.",
        "receipt_preview" => %{
          "events" => [
            %{"rule_id" => "account-redactor", "type" => "stream.rewrite_applied"},
            %{"state" => "review_required", "type" => "policy.state_transition"},
            %{"reason" => "related_secret_match", "type" => "stream.release_blocked"}
          ],
          "receipt_id" => "simulated-rewrite-transition-receipt",
          "stream" => %{
            "released_to_consumer" => false,
            "rewrites" => [%{"replacement" => "[account-id]", "rule_id" => "account-redactor"}],
            "state_transition" => "review_required"
          }
        },
        "scenario_id" => "rewrite-then-transition",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Rewrite followed by related transition",
        "trace" => [
          trace(
            "r1",
            "response.streaming",
            "stream.redact-account",
            "input",
            "chunk held",
            "held chunk contains acct_4938 before release",
            "info",
            state_id: "observing"
          ),
          trace(
            "r2",
            "response.streaming",
            "stream.redact-account",
            "match",
            "account regex matched",
            "acct_4938 rewritten to [account-id] inside the holdback window",
            "pass",
            state_id: "rewriting"
          ),
          trace(
            "r3",
            "response.streaming",
            "stream.secret-transition",
            "match",
            "related secret matched",
            "token_ prefix appears after the account rewrite and triggers review_required",
            "block",
            state_id: "review_required"
          ),
          trace(
            "r4",
            "response.streaming",
            "stream.rewrite-arbiter",
            "action",
            "review hold selected",
            "rewritten output remains withheld pending review state resolution",
            "warn",
            state_id: "review_required"
          ),
          trace(
            "r5",
            "receipt.finalized",
            "stream.rewrite-receipt",
            "receipt_event",
            "rewrite receipt",
            "receipt records rewrite range, transition state, and withheld bytes hash",
            "info",
            state_id: "recording"
          )
        ],
        "verdict" => "passed"
      }
      |> fixture_case()
    ]
  end

  defp evaluated_stream_rewrite_simulation(turn, _config) do
    text = turn_response(turn)
    account_match = Regex.run(~r/\bacct_[A-Za-z0-9_]+\b/, text)
    secret_match = Regex.run(~r/\b(token|secret)_[A-Za-z0-9_]+\b/i, text)
    related_secret_history_count = related_secret_history_count(turn)
    {model_received_input, request_rewrites} = request_rewrite_result(turn_user_input(turn))
    input_preview = turn_input_preview(turn, model_received_input, request_rewrites)
    request_trace = request_rewrite_trace(request_rewrites)
    history_trace = stream_history_trace(related_secret_history_count)

    cond do
      account_match && (secret_match || related_secret_history_count >= 3) ->
        account = hd(account_match)
        secret = if secret_match, do: hd(secret_match), else: "session history"

        secret_detail =
          stream_secret_transition_detail(
            secret_match,
            secret,
            related_secret_history_count,
            turn
          )

        %{
          "engine_id" => "structured-stream-primitives",
          "expected_behavior" =>
            "Account span is rewritten, a related secret pattern or session-history threshold transitions to review_required, and release is blocked.",
          "input_summary" => summarize_turn(turn),
          "receipt_preview" => %{
            "events" => [
              %{"rule_id" => "account-redactor", "type" => "stream.rewrite_applied"},
              %{"state" => "review_required", "type" => "policy.state_transition"},
              %{"reason" => "related_secret_match", "type" => "stream.release_blocked"}
            ],
            "input" => input_preview,
            "stream" => %{
              "history" => stream_history_receipt(turn, related_secret_history_count),
              "released_to_consumer" => false,
              "rewrites" => [%{"match" => account, "replacement" => "[account-id]", "rule_id" => "account-redactor"}],
              "state_transition" => "review_required"
            }
          },
          "scenario_id" => "interactive-rewrite-then-transition",
          "simulation_schema" => "wardwright.policy_simulation.v1",
          "title" => "Edited stream rewrites then transitions",
          "trace" =>
            request_trace ++
              history_trace ++
              [
                trace(
                  "i1",
                  "response.streaming",
                  "stream.redact-account",
                  "input",
                  "chunk held",
                  "held chunks contain #{account} before release",
                  "info",
                  state_id: "observing"
                ),
                trace(
                  "i2",
                  "response.streaming",
                  "stream.redact-account",
                  "match",
                  "account regex matched",
                  "#{account} rewritten to [account-id] inside the holdback window",
                  "pass",
                  state_id: "rewriting"
                ),
                trace(
                  "i3",
                  "response.streaming",
                  "stream.secret-transition",
                  "match",
                  "related secret matched",
                  secret_detail,
                  "block",
                  state_id: "review_required"
                ),
                trace(
                  "i4",
                  "response.streaming",
                  "stream.rewrite-arbiter",
                  "action",
                  "review hold selected",
                  "rewritten output remains withheld pending review state resolution",
                  "warn",
                  state_id: "review_required"
                ),
                trace(
                  "i5",
                  "receipt.finalized",
                  "stream.rewrite-receipt",
                  "receipt_event",
                  "rewrite receipt",
                  "receipt records rewrite range, transition state, and withheld bytes hash",
                  "info",
                  state_id: "recording"
                )
              ],
          "verdict" => "passed"
        }

      account_match ->
        account = hd(account_match)

        %{
          "engine_id" => "structured-stream-primitives",
          "expected_behavior" => "Account span is rewritten and released because no related secret pattern appears.",
          "input_summary" => summarize_turn(turn),
          "receipt_preview" => %{
            "events" => [%{"rule_id" => "account-redactor", "type" => "stream.rewrite_applied"}],
            "input" => input_preview,
            "stream" => %{
              "released_to_consumer" => true,
              "rewrites" => [%{"match" => account, "replacement" => "[account-id]", "rule_id" => "account-redactor"}],
              "state_transition" => nil
            }
          },
          "scenario_id" => "interactive-rewrite-only",
          "simulation_schema" => "wardwright.policy_simulation.v1",
          "title" => "Edited stream rewrites and releases",
          "trace" =>
            request_trace ++
              history_trace ++
              [
                trace(
                  "i1",
                  "response.streaming",
                  "stream.redact-account",
                  "match",
                  "account regex matched",
                  "#{account} rewritten to [account-id] inside the holdback window",
                  "pass",
                  state_id: "rewriting"
                ),
                trace(
                  "i2",
                  "response.streaming",
                  "stream.rewrite-arbiter",
                  "action",
                  "rewritten stream released",
                  "no related secret pattern appeared before the holdback window closed",
                  "pass",
                  state_id: "rewriting"
                ),
                trace(
                  "i3",
                  "receipt.finalized",
                  "stream.rewrite-receipt",
                  "receipt_event",
                  "rewrite receipt",
                  "receipt records the rewrite without a state transition",
                  "info",
                  state_id: "recording"
                )
              ],
          "verdict" => "passed"
        }

      related_secret_history_count >= 3 ->
        %{
          "engine_id" => "structured-stream-primitives",
          "expected_behavior" =>
            "Current output releases unchanged, but session history crosses the threshold and the next turn starts in review_required with the managed model.",
          "input_summary" => summarize_turn(turn),
          "receipt_preview" => %{
            "events" => [
              %{"state" => "review_required", "type" => "policy.state_transition"},
              %{"selected_model" => Wardwright.managed_model(), "type" => "route.next_turn_model_selected"},
              %{"reason" => "no_current_match", "type" => "stream.release_allowed"}
            ],
            "input" => input_preview,
            "stream" => %{
              "final_output" => text,
              "history" => stream_history_receipt(turn, related_secret_history_count),
              "next_turn" => %{
                "reason" => "session history threshold crossed",
                "selected_model" => Wardwright.managed_model(),
                "state" => "review_required"
              },
              "released_to_consumer" => true,
              "rewrites" => [],
              "state_transition" => "review_required"
            }
          },
          "scenario_id" => "interactive-next-turn-review",
          "simulation_schema" => "wardwright.policy_simulation.v1",
          "title" => "Edited turn changes the next turn",
          "trace" =>
            request_trace ++
              history_trace ++
              [
                trace(
                  "i1",
                  "response.streaming",
                  "stream.secret-transition",
                  "match",
                  "history threshold matched",
                  "#{related_secret_history_count} prior related secret match(es) #{turn_history_window_label(turn)} transition the session for the next turn",
                  "warn",
                  state_id: "review_required"
                ),
                trace(
                  "i2",
                  "response.streaming",
                  "stream.rewrite-arbiter",
                  "action",
                  "current stream released",
                  "no current output rewrite or block is required; the state change affects subsequent turns",
                  "pass",
                  state_id: "review_required"
                ),
                trace(
                  "i3",
                  "receipt.finalized",
                  "stream.rewrite-receipt",
                  "receipt_event",
                  "state receipt",
                  "receipt records next-turn review state and managed model selection",
                  "info",
                  state_id: "recording"
                )
              ],
          "verdict" => "passed"
        }

      true ->
        no_stream_rewrite_match_simulation(turn, input_preview, request_trace)
    end
  end

  defp default_simulation_cases(_pattern_id, _config) do
    [
      %{
        "engine_id" => "structured-stream-primitives",
        "expected_behavior" =>
          "No violating bytes from the first attempt are released; the second attempt is generated with a reminder and then released.",
        "input_summary" => "Provider emits OldClient( split across held chunks.",
        "receipt_preview" => %{
          "events" => [
            %{"horizon_bytes" => 4096, "rule_id" => "no-old-client", "type" => "stream.window_held"},
            %{"match_kind" => "regex", "rule_id" => "no-old-client", "type" => "stream.rule_matched"},
            %{"reason" => "tts_rule_matched", "type" => "attempt.aborted"},
            %{"reminder_id" => "no-old-client.reminder", "type" => "attempt.retry_requested"},
            %{"attempt" => 2, "reason" => "retry_passed_guard", "type" => "stream.released"}
          ],
          "model_id" => Wardwright.model_id(),
          "policy_version" => "draft.ttsr.001",
          "receipt_id" => "simulated-policy-receipt",
          "stream" => %{
            "abort_offset" => 42,
            "attempts" => [
              %{
                "index" => 1,
                "model_output" => "avoid introducing Old\nClient( into the final answer",
                "policy_result" => "prohibited span matched inside the held horizon",
                "status" => "withheld_and_aborted",
                "user_output" => ""
              },
              %{
                "index" => 2,
                "model_output" => "Use the current client adapter in the migration note.",
                "policy_result" => "retry output passed the stream guard",
                "retry_instruction" => "Do not emit OldClient(. Use current client adapter wording instead.",
                "status" => "released_after_retry",
                "user_output" => "Use the current client adapter in the migration note."
              }
            ],
            "final_output" => "Use the current client adapter in the migration note.",
            "released_to_consumer" => true,
            "retry_attempted" => true,
            "rule_matched" => "no-old-client"
          }
        },
        "scenario_id" => "split-trigger",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Split trigger before release",
        "trace" => [
          trace("t1", "response.streaming", "tts.no-old-client", "input", "chunk held", "avoid introducing Old", "info",
            state_id: "observing"
          ),
          trace(
            "t2",
            "response.streaming",
            "tts.no-old-client",
            "match",
            "regex matched",
            "Client( completes the prohibited span inside the holdback window",
            "block",
            state_id: "guarding"
          ),
          trace(
            "t3",
            "response.streaming",
            "tts.retry-arbiter",
            "action",
            "retry selected",
            "attempt aborted before release and retry reminder injected",
            "pass",
            state_id: "retrying"
          ),
          trace(
            "t4",
            "response.streaming",
            "tts.no-old-client",
            "output",
            "retry stream released",
            "second model attempt avoids the prohibited span and can be released",
            "pass",
            state_id: "retrying"
          ),
          trace(
            "t5",
            "receipt.finalized",
            "tts.receipt-events",
            "receipt_event",
            "receipt preview",
            "stream.rule_matched, attempt.retry_requested, and final release events recorded",
            "info",
            state_id: "recording"
          )
        ],
        "verdict" => "passed"
      }
      |> fixture_case()
    ]
  end

  defp evaluated_tts_retry_simulation(turn, _config) do
    text = turn_response(turn)

    if Regex.match?(~r/Old\s*Client\(/, text) do
      %{
        "engine_id" => "structured-stream-primitives",
        "expected_behavior" =>
          "No violating bytes from the first attempt are released; the second attempt is generated with a reminder and then released.",
        "input_summary" => summarize_turn(turn),
        "receipt_preview" => %{
          "events" => [
            %{"rule_id" => "no-old-client", "type" => "stream.rule_matched"},
            %{"reason" => "tts_rule_matched", "type" => "attempt.aborted"},
            %{"reminder_id" => "no-old-client.reminder", "type" => "attempt.retry_requested"},
            %{"attempt" => 2, "reason" => "retry_passed_guard", "type" => "stream.released"}
          ],
          "input" => turn_input_preview(turn),
          "stream" => %{
            "attempts" => [
              %{
                "index" => 1,
                "model_output" => text,
                "policy_result" => "prohibited span matched inside the held horizon",
                "status" => "withheld_and_aborted",
                "user_output" => ""
              },
              %{
                "index" => 2,
                "model_output" => tts_retry_final_output(turn),
                "policy_result" => "retry output passed the stream guard",
                "retry_instruction" => "Do not emit OldClient(. Use current client adapter wording instead.",
                "status" => "released_after_retry",
                "user_output" => tts_retry_final_output(turn)
              }
            ],
            "final_output" => tts_retry_final_output(turn),
            "released_to_consumer" => true,
            "retry_attempted" => true,
            "rule_matched" => "no-old-client"
          }
        },
        "scenario_id" => "interactive-tts-retry",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Edited stream triggers retry",
        "trace" => [
          trace(
            "i1",
            "response.streaming",
            "tts.no-old-client",
            "input",
            "chunk held",
            "edited chunks are held before release",
            "info",
            state_id: "observing"
          ),
          trace(
            "i2",
            "response.streaming",
            "tts.no-old-client",
            "match",
            "regex matched",
            "Client( completes the prohibited span inside the holdback window",
            "block",
            state_id: "guarding"
          ),
          trace(
            "i3",
            "response.streaming",
            "tts.retry-arbiter",
            "action",
            "retry selected",
            "attempt aborted before release and retry reminder injected",
            "pass",
            state_id: "retrying"
          ),
          trace(
            "i4",
            "response.streaming",
            "tts.no-old-client",
            "output",
            "retry stream released",
            "second model attempt avoids the prohibited span and can be released",
            "pass",
            state_id: "retrying"
          ),
          trace(
            "i5",
            "receipt.finalized",
            "tts.receipt-events",
            "receipt_event",
            "receipt preview",
            "stream.rule_matched, attempt.retry_requested, and final release events recorded",
            "info",
            state_id: "recording"
          )
        ],
        "verdict" => "passed"
      }
    else
      %{
        "engine_id" => "structured-stream-primitives",
        "expected_behavior" => "No prohibited span appears inside the holdback window, so the stream can release.",
        "input_summary" => summarize_turn(turn),
        "receipt_preview" => %{
          "events" => [%{"reason" => "no_policy_match", "type" => "stream.released"}],
          "input" => turn_input_preview(turn),
          "stream" => %{"released_to_consumer" => true, "retry_attempted" => false, "rule_matched" => nil}
        },
        "scenario_id" => "interactive-tts-safe-release",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "Edited stream releases normally",
        "trace" => [
          trace(
            "i1",
            "response.streaming",
            "tts.no-old-client",
            "input",
            "chunk held",
            "edited chunks were scanned without matching OldClient(",
            "info",
            state_id: "observing"
          ),
          trace(
            "i2",
            "receipt.finalized",
            "tts.receipt-events",
            "receipt_event",
            "safe release receipt",
            "receipt records that no retry was requested",
            "pass",
            state_id: "recording"
          )
        ],
        "verdict" => "passed"
      }
    end
  end

  defp tts_retry_final_output(turn) do
    input = turn_user_input(turn)

    cond do
      retry_response(turn) ->
        retry_response(turn)

      String.contains?(input, "migration") ->
        "Use the current client adapter in the migration note."

      String.trim(input) == "" ->
        "Use the current client adapter."

      true ->
        "Use the current client adapter. Avoid deprecated constructor names."
    end
  end

  defp no_stream_rewrite_match_simulation(turn, input_preview, request_trace) do
    %{
      "engine_id" => "structured-stream-primitives",
      "expected_behavior" => "No rewrite or state transition is applied because no configured regex matches.",
      "input_summary" => summarize_turn(turn),
      "receipt_preview" => %{
        "events" => [%{"reason" => "no_policy_match", "type" => "stream.released"}],
        "input" => input_preview,
        "stream" => %{"released_to_consumer" => true, "rewrites" => [], "state_transition" => nil}
      },
      "scenario_id" => "interactive-stream-no-match",
      "simulation_schema" => "wardwright.policy_simulation.v1",
      "title" => "Edited stream has no regex match",
      "trace" =>
        request_trace ++
          [
            trace(
              "i1",
              "response.streaming",
              "stream.redact-account",
              "input",
              "chunk held",
              "edited chunks were scanned without an account-id match",
              "info",
              state_id: "observing"
            ),
            trace(
              "i2",
              "response.streaming",
              "stream.rewrite-arbiter",
              "action",
              "stream released",
              "no rewrite patch or review transition was produced",
              "pass",
              state_id: "observing"
            ),
            trace(
              "i3",
              "receipt.finalized",
              "stream.rewrite-receipt",
              "receipt_event",
              "no-op receipt",
              "receipt records that the stream was released without policy effects",
              "info",
              state_id: "recording"
            )
          ],
      "verdict" => "passed"
    }
  end

  defp stream_secret_transition_detail(nil, _secret, related_secret_history_count, turn) do
    window = turn_history_window_label(turn)

    "#{related_secret_history_count} prior related secret match(es) #{window} trigger review_required after this account rewrite"
  end

  defp stream_secret_transition_detail(_secret_match, secret, _related_secret_history_count, _turn) do
    "#{secret} appears after the account rewrite and triggers review_required"
  end

  defp stream_history_trace(0), do: []

  defp stream_history_trace(count) do
    [
      trace(
        "ih",
        "response.streaming",
        "stream.secret-transition",
        "history_read",
        "prior related matches read",
        "#{count} related secret match(es) found in the configured session-history window",
        "info",
        state_id: "observing"
      )
    ]
  end

  defp stream_history_receipt(turn, related_secret_history_count) do
    %{
      "recent_related_secret_matches" => related_secret_history_count,
      "recent_secret_window_requests" => related_secret_history_window(turn),
      "threshold" => 3
    }
  end

  defp request_rewrite_result(user_input) do
    Regex.scan(~r/private_context\{[^}]*\}/i, user_input)
    |> Enum.map(&hd/1)
    |> case do
      [] ->
        {user_input, []}

      matches ->
        model_received_input =
          Enum.reduce(matches, user_input, fn match, input ->
            String.replace(input, match, "[private-context omitted]")
          end)

        rewrites =
          Enum.map(matches, fn match ->
            %{
              "direction" => "request",
              "match" => match,
              "replacement" => "[private-context omitted]",
              "rule_id" => "private-context-redactor"
            }
          end)

        {model_received_input, rewrites}
    end
  end

  defp request_rewrite_trace([]), do: []

  defp request_rewrite_trace(_rewrites) do
    [
      trace(
        "i0",
        "request.preparing",
        "request.rewrite-context",
        "match",
        "request context redacted",
        "private_context{...} was removed before provider dispatch",
        "pass",
        state_id: "observing"
      )
    ]
  end

  defp summarize_turn(turn) do
    user = turn |> turn_user_input() |> String.trim()
    response = turn |> turn_response() |> String.trim()

    cond do
      user != "" and response != "" ->
        "User: #{truncate(user, 80)} / Model: #{truncate(response, 120)}"

      response != "" ->
        truncate(response, 140)

      user != "" ->
        "User: #{truncate(user, 140)}"

      true ->
        "Empty simulated turn."
    end
  end

  defp turn_input_preview(turn), do: turn_input_preview(turn, turn_user_input(turn), [])

  defp turn_input_preview(turn, model_received_input, request_rewrites) do
    %{
      "history_context" => turn_history_context(turn),
      "model_received_input" => model_received_input,
      "model_response" => turn_response(turn),
      "request_rewrites" => request_rewrites,
      "response_chunks" => input_chunks(turn_response(turn)),
      "user_input" => turn_user_input(turn)
    }
  end

  defp turn_user_input(%{"user_input" => value}) when is_binary(value), do: value
  defp turn_user_input(_turn), do: ""

  defp turn_response(%{"model_response" => value}) when is_binary(value), do: value
  defp turn_response(%{"text" => value}) when is_binary(value), do: value
  defp turn_response(_turn), do: ""

  defp turn_response_attempts(%{"response_attempts" => attempts}) when is_list(attempts),
    do: normalize_response_attempts(attempts)

  defp turn_response_attempts(_turn), do: []

  defp retry_response(turn) do
    turn
    |> turn_response_attempts()
    |> Enum.find(&(Map.get(&1, "index") == 2))
    |> case do
      %{"model_output" => output} when is_binary(output) and output != "" -> output
      _attempt -> nil
    end
  end

  defp turn_history_context(%{"history_context" => value}) when is_map(value), do: normalize_history_context(value)

  defp turn_history_context(_turn), do: %{}

  defp related_secret_history_count(turn) do
    turn
    |> turn_history_context()
    |> Map.get("recent_related_secret_matches", "0")
    |> parse_nonnegative_integer()
  end

  defp normalize_response_attempts(attempts) when is_list(attempts) do
    attempts
    |> Enum.flat_map(&normalize_response_attempt/1)
    |> Enum.sort_by(&Map.get(&1, "index", 0))
  end

  defp normalize_response_attempts(_attempts), do: []

  defp normalize_response_attempt(%{"index" => index} = attempt) when is_integer(index) do
    output = Map.get(attempt, "model_output") || Map.get(attempt, "model_response")

    if is_binary(output) and String.trim(output) != "" do
      [
        Map.new([
          {"index", index},
          {"model_output", output},
          {"status", string_or_nil(Map.get(attempt, "status"))},
          {"user_output", string_or_nil(Map.get(attempt, "user_output"))},
          {"retry_instruction", string_or_nil(Map.get(attempt, "retry_instruction"))},
          {"policy_result", string_or_nil(Map.get(attempt, "policy_result"))}
        ])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
      ]
    else
      []
    end
  end

  defp normalize_response_attempt(_attempt), do: []

  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(_value), do: nil

  defp related_secret_history_window(turn) do
    turn
    |> turn_history_context()
    |> Map.get("recent_secret_window_requests", "5")
    |> parse_nonnegative_integer()
  end

  defp turn_history_window_label(turn) when is_map(turn) do
    "in the last #{related_secret_history_window(turn)} request(s)"
  end

  defp turn_history_window_label(_turn), do: "in session history"

  defp normalize_history_context(context) when is_map(context) do
    context
    |> Enum.reject(fn {key, _value} -> String.starts_with?(to_string(key), "_unused_") end)
    |> Map.new(fn {key, value} -> {to_string(key), history_context_value(value)} end)
  end

  defp normalize_history_context(_context), do: %{}

  defp history_context_value(value) when is_binary(value), do: value
  defp history_context_value(value) when is_integer(value), do: Integer.to_string(value)
  defp history_context_value(value) when is_float(value), do: Float.to_string(value)
  defp history_context_value(value) when is_boolean(value), do: to_string(value)
  defp history_context_value(nil), do: ""
  defp history_context_value(value), do: inspect(value)

  defp parse_nonnegative_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, _rest} when integer > 0 -> integer
      _ -> 0
    end
  end

  defp parse_nonnegative_integer(value) when is_integer(value) and value > 0, do: value
  defp parse_nonnegative_integer(_value), do: 0

  defp input_chunks(text) do
    text
    |> String.split(~r/\R/, trim: true)
    |> case do
      [] -> [""]
      chunks -> chunks
    end
  end

  defp truncate(text, limit) when byte_size(text) <= limit, do: text

  defp truncate(text, limit) do
    text
    |> binary_part(0, limit)
    |> Kernel.<>("...")
  end

  defp no_route_gate_simulation do
    [
      %{
        "engine_id" => "request-route-plan",
        "expected_behavior" => "Route selection proceeds without policy constraints.",
        "input_summary" => "Active config has no route-affecting governance rules.",
        "receipt_preview" => %{"decision" => %{"policy_actions" => []}, "final_status" => "simulated"},
        "scenario_id" => "no-route-gate-configured",
        "simulation_schema" => "wardwright.policy_simulation.v1",
        "title" => "No route governance configured",
        "trace" => [
          trace(
            "p1",
            "route.selecting",
            "request-policy.no-route-gate",
            "warning",
            "no route policy",
            "No configured route-governance node could affect this scenario.",
            "warn"
          )
        ],
        "verdict" => "inconclusive"
      }
      |> fixture_case()
    ]
  end

  defp route_governance_simulation(config, rules) do
    text = route_simulation_text(rules)
    request = %{"messages" => [%{"content" => text, "role" => "user"}]}

    {_request, policy} =
      Plan.evaluate_request(request, %{"source" => "projection"}, config)

    actions = Map.get(policy, "actions", [])

    %{
      "engine_id" => "request-route-plan",
      "expected_behavior" => "Policy.Plan emits route constraints or an explicit no-match trace.",
      "input_summary" => "Generated request chosen to exercise the first configured route rule.",
      "receipt_preview" => %{
        "decision" => %{
          "policy_actions" => actions,
          "policy_conflicts" => Map.get(policy, "conflicts", []),
          "route_constraints" => Map.get(policy, "route_constraints", %{})
        },
        "final_status" => "simulated"
      },
      "scenario_id" => "configured-route-policy",
      "simulation_schema" => "wardwright.policy_simulation.v1",
      "title" => "Configured route governance path",
      "trace" => route_policy_trace(actions, rules),
      "verdict" => if(actions == [], do: "inconclusive", else: "passed")
    }
    |> fixture_case()
  end

  defp no_tool_governance_simulation do
    %{
      "engine_id" => "tool-context-plan",
      "expected_behavior" => "Tool context is normalized into receipt evidence only.",
      "input_summary" => "A request includes declared tools, but active config has no tool policy.",
      "receipt_preview" => %{
        "decision" => %{
          "tool_context" => %{
            "phase" => "planning",
            "primary_tool" => %{
              "name" => "lookup_customer",
              "namespace" => "openai.function",
              "risk_class" => "unknown",
              "source" => "declared_tool"
            },
            "schema" => "wardwright.tool_context.v1"
          }
        },
        "final_status" => "simulated"
      },
      "scenario_id" => "no-tool-policy-configured",
      "simulation_schema" => "wardwright.policy_simulation.v1",
      "title" => "No tool governance configured",
      "trace" => [
        trace(
          "g1",
          "tool.planning",
          "tool-policy.no-planning-policy",
          "warning",
          "no tool policy",
          "No configured tool-governance node can constrain this planned tool call.",
          "warn"
        ),
        trace(
          "g2",
          "receipt.finalized",
          "tool.receipt-context",
          "receipt_event",
          "tool context recorded",
          "Receipt summaries can filter namespace/name/phase/risk/source/call id without raw args.",
          "info"
        )
      ],
      "verdict" => "inconclusive"
    }
    |> fixture_case()
  end

  defp tool_governance_simulation([rule | _rules]) do
    node_id = "tool-policy.#{safe_id(Map.get(rule, "id", "tool-policy"))}"
    phase = tool_rule_phase(rule)

    %{
      "engine_id" => "tool-context-plan",
      "expected_behavior" => "Projection links normalized tool context to a declared tool policy action.",
      "input_summary" => "Generated request chosen to exercise the first configured tool rule.",
      "receipt_preview" => %{
        "decision" => %{
          "policy_actions" => [
            %{"action" => Map.get(rule, "action", default_tool_action(rule)), "rule_id" => Map.get(rule, "id")}
          ],
          "tool_context" => %{
            "phase" => tool_context_phase(phase),
            "primary_tool" => %{
              "name" => Map.get(rule, "name", "create_pull_request"),
              "namespace" => Map.get(rule, "namespace", "mcp.github"),
              "risk_class" => Map.get(rule, "risk_class", "write"),
              "source" => "declared_tool"
            },
            "schema" => "wardwright.tool_context.v1"
          }
        },
        "final_status" => "simulated"
      },
      "scenario_id" => "configured-tool-policy",
      "simulation_schema" => "wardwright.policy_simulation.v1",
      "title" => "Configured tool governance path",
      "trace" => [
        trace(
          "g1",
          phase,
          node_id,
          "match",
          Map.get(rule, "action", default_tool_action(rule)),
          tool_governance_summary(rule, Map.get(rule, "action", default_tool_action(rule))),
          "pass"
        ),
        trace(
          "g2",
          "receipt.finalized",
          "tool.receipt-context",
          "receipt_event",
          "tool context recorded",
          "Normalized tool context is available as receipt evidence and receipt-list filters.",
          "info"
        )
      ],
      "verdict" => "passed"
    }
    |> fixture_case()
  end

  defp fixture_case(simulation) do
    simulation
    |> put_string("scenario_source", "fixture")
    |> put_string("source", "fixture")
  end

  defp tool_context_phase(phase) do
    case phase do
      "tool.result_interpreting" -> :wardwright@projection_core.tool_context_phase(phase)
      "tool.loop_governing" -> :wardwright@projection_core.tool_context_phase(phase)
      "tool.planning" -> :wardwright@projection_core.tool_context_phase(phase)
      phase -> String.replace_prefix(phase, "tool.", "")
    end
  end

  defp put_string(map, key, value), do: Map.put(map, key, value)

  defp route_simulation_text([rule | _rules]) do
    cond do
      is_binary(rule["contains"]) and rule["contains"] != "" ->
        "projection simulation #{rule["contains"]}"

      is_binary(rule["pattern"]) and rule["pattern"] != "" ->
        "projection simulation #{rule["pattern"]}"

      true ->
        "projection simulation route governance request"
    end
  end

  defp route_policy_trace([], [rule | _rules]) do
    [
      trace(
        "p1",
        "route.selecting",
        "request-policy.#{safe_id(Map.get(rule, "id", "route-policy"))}",
        "warning",
        "rule did not match",
        "The configured policy plan produced no route action for the generated scenario.",
        "warn"
      )
    ]
  end

  defp route_policy_trace(actions, _rules) do
    actions
    |> Enum.with_index()
    |> Enum.map(fn {action, index} ->
      trace(
        "p#{index + 1}",
        "route.selecting",
        "request-policy.#{safe_id(Map.get(action, "rule_id", "route-policy"))}",
        "action",
        Map.get(action, "action", "policy action"),
        Map.get(action, "message", "configured policy action matched"),
        "pass"
      )
    end)
  end

  defp trace(id, phase, node_id, kind, label, detail, severity, opts \\ []) do
    opts = trace_opts(opts)

    %Contract.TraceEvent{
      detail: detail,
      id: id,
      kind: kind,
      label: label,
      node_id: node_id,
      phase: phase,
      severity: severity,
      source_span: Keyword.get(opts, :source_span),
      state_id: Keyword.get(opts, :state_id)
    }
    |> Contract.to_map()
  end

  defp trace_opts(opts) when is_list(opts), do: opts
  defp trace_opts(source_span), do: [source_span: source_span]
end
