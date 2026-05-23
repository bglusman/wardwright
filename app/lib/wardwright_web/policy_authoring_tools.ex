defmodule WardwrightWeb.PolicyAuthoringTools do
  @moduledoc false

  @docs_root "https://wardwright.dev"

  def list do
    [
      tool(
        "explain_projection",
        "GET",
        "/v1/policy-authoring/projections/{pattern_id}",
        "Return the deterministic projection, including state machine, phase, effect, conflict, and opaque-region data.",
        "Use before editing when you need to understand what a policy model currently does.",
        "Read-only. The projection is explanatory; deterministic policy artifacts remain the source of truth.",
        "/agent-authoring.html#inspect-before-you-edit"
      ),
      tool(
        "simulate_policy",
        "GET",
        "/v1/policy-authoring/simulations/{pattern_id}",
        "Return persisted simulation scenarios when present, otherwise explicit fixture evidence linked to projection node ids and the current artifact hash.",
        "Use to compare the user's intended behavior with the behavior Wardwright can demonstrate.",
        "Read-only. Simulation results explain behavior but do not prove every possible input.",
        "/agent-authoring.html#simulate-before-you-activate"
      ),
      tool(
        "list_dune_snippets",
        "GET",
        "/v1/policy-authoring/dune-snippets",
        "List built-in and local workspace Dune policy snippets with source, example inputs, phases, and the structured primitives they may replace.",
        "Use when exploring whether a policy behavior is clearer as inspectable BEAM-native code than as structured primitive fields.",
        "Read-only. Dune snippets are local/trusted policy candidates, not hostile-code portability guarantees.",
        "/agent-authoring.html#try-dune-snippets"
      ),
      tool(
        "evaluate_dune_snippet",
        "POST",
        "/v1/policy-authoring/dune-snippets/evaluate",
        "Run a registry or ad hoc Dune snippet against a supplied JSON-like input map and return normalized policy-result evidence.",
        "Use before proposing any Dune-backed behavior so the user can inspect concrete results and failure modes.",
        "Read-only evaluation. Sandbox errors and malformed results fail closed; never activate snippets without scenario review.",
        "/agent-authoring.html#try-dune-snippets"
      ),
      tool(
        "save_dune_snippet",
        "POST",
        "/v1/policy-authoring/dune-snippets",
        "Persist a local trusted Dune snippet in the workspace catalog so later policies can reference it by snippet_id.",
        "Use after evaluating an ad hoc snippet and getting user approval to keep it as a reusable local behavior.",
        "Write-capable. Built-in snippets are read-only; saved snippets are trusted local code and should be reviewed before activation.",
        "/agent-authoring.html#try-dune-snippets"
      ),
      tool(
        "delete_dune_snippet",
        "DELETE",
        "/v1/policy-authoring/dune-snippets/{snippet_id}",
        "Remove a local trusted Dune snippet from the workspace catalog.",
        "Use when a workspace snippet is obsolete, misleading, or should no longer be referenced by new policies.",
        "Write-capable. Built-in snippets cannot be deleted; existing policies that reference the removed snippet will fail closed.",
        "/agent-authoring.html#try-dune-snippets"
      ),
      tool(
        "draft_wardwright_model",
        "POST",
        "/v1/policy-authoring/wardwright-models/draft",
        "Build and validate a draft Wardwright model artifact from supplied provider/model targets, route graph nodes, governance rules, and stream rules without activating it.",
        "Use when creating a new local Wardwright model or normalizing a hand-written artifact before review.",
        "Draft-only. This does not change the model served by /v1/chat/completions.",
        "/agent-authoring.html#draft-a-wardwright-model"
      ),
      tool(
        "activate_wardwright_model",
        "POST",
        "/v1/policy-authoring/wardwright-models",
        "Validate and activate a Wardwright model artifact as a registered local model so agents can call it through the OpenAI-compatible endpoint.",
        "Use only after the user has reviewed the draft, validation output, and relevant simulations.",
        "Write-capable. Requires protected local access and registers or updates one local model without replacing other active models.",
        "/agent-authoring.html#activate-only-after-review"
      ),
      tool(
        "propose_rule_change",
        "POST",
        "/v1/policy-authoring/propose-rule-change",
        "Return a draft artifact with an appended, replaced, or removed governance or stream rule; never applies the proposal.",
        "Use for small edits to existing governance or stream rules when the user wants a reviewable diff-shaped artifact.",
        "Draft-only. Never applies changes; follow with validation/simulation and explicit activation if desired.",
        "/agent-authoring.html#propose-a-rule-change"
      ),
      tool(
        "record_scenario",
        "POST",
        "/v1/policy-authoring/scenarios/{pattern_id}",
        "Persist a user/chat response pair, fixture, or live-replay scenario so simulations can use reviewed scenario records instead of demo fixtures.",
        "Use when the user identifies a representative case that should remain visible in the simulator or regression pack.",
        "Write-capable. Prefer redacted raw turns unless the user explicitly wants sensitive text retained; include model_id and artifact_hash when known.",
        "/agent-authoring.html#record-scenarios-as-regression-evidence"
      ),
      tool(
        "delete_scenario",
        "DELETE",
        "/v1/policy-authoring/scenarios/{pattern_id}/{scenario_id}",
        "Remove one persisted simulator test case from the workbench scenario library.",
        "Use when a user or authoring agent replaces a stale canned turn with a better reviewed case.",
        "Write-capable. Deletes one scenario record; pinned records are not protected from explicit deletion.",
        "/agent-authoring.html#record-scenarios-as-regression-evidence"
      ),
      tool(
        "import_receipt_scenario",
        "POST",
        "/v1/policy-authoring/scenarios/{pattern_id}/from-receipt/{receipt_id}",
        "Import an existing receipt as a pinned live-replay scenario for later simulation evidence and regression export.",
        "Use after a real run exposes behavior worth preserving as review evidence.",
        "Write-capable. Imported receipts may contain sensitive metadata; review before sharing exported packs.",
        "/agent-authoring.html#record-scenarios-as-regression-evidence"
      ),
      tool(
        "replay_receipt_policy",
        "POST",
        "/v1/policy-authoring/replay-receipts/{receipt_id}",
        "Replay the policy and route decisions recorded in an existing receipt without making any provider call.",
        "Use after importing or inspecting a receipt when you need deterministic control-layer evidence before drafting a policy change.",
        "Read-only. Replay uses metadata-only VCR fields when present and never returns raw prompts or completions.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "list_control_debugger_examples",
        "GET",
        "/v1/policy-authoring/control-debugger/examples",
        "List built-in Control Debugger counterfactual examples, their default simulator pattern, and policy overlay.",
        "Use before recording a Ralph counterfactual example from a shell or MCP agent.",
        "Read-only. Returns example metadata only; no transcript, receipt, or simulator case is written.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "record_control_debugger_example",
        "POST",
        "/v1/policy-authoring/control-debugger/examples/{example_id}/record",
        "Record a built-in Control Debugger counterfactual example session and return receipt, session, and suggested cursor facts.",
        "Use when an assisting agent needs the same starting trace the UI creates with Record example session.",
        "Write-capable. Creates local receipt and transcript evidence. Built-in examples use deterministic scripted continuation and do not require a paid provider call.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "load_control_debugger_trace",
        "POST",
        "/v1/policy-authoring/control-debugger/traces/load",
        "Load a Control Debugger trace by receipt_id or session_id, including event cursors and suggested fork points.",
        "Use after recording or selecting a trace before replaying, forking, or saving evidence.",
        "Read-only. Trace events can contain sensitive session metadata; review before sharing.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "replay_control_debugger_cursor",
        "POST",
        "/v1/policy-authoring/control-debugger/traces/replay-cursor",
        "Replay a Control Debugger trace up to a selected cursor without making a provider call.",
        "Use to prove the selected replay/fork point from non-UI tooling.",
        "Read-only. Stops before the selected cursor and reports provider_called=false.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "fork_control_debugger_cursor",
        "POST",
        "/v1/policy-authoring/control-debugger/traces/fork-cursor",
        "Fork a Control Debugger trace at a selected cursor, apply a policy overlay, and continue with deterministic scripted steps.",
        "Use to reproduce the UI's default Ralph fork/continue path without scraping buttons.",
        "Write-capable. Writes fork transcript evidence but does not call a provider.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "save_control_debugger_evidence",
        "POST",
        "/v1/policy-authoring/control-debugger/traces/save-evidence",
        "Save selected Control Debugger trace evidence as a pinned simulator case for a policy pattern.",
        "Use after replaying or forking a selected cursor that should become simulator or regression evidence.",
        "Write-capable. Saved trace events can include sensitive metadata; review scenario packs before publishing.",
        "/agent-authoring.html#record-scenarios-as-regression-evidence"
      ),
      tool(
        "list_harness_adapters",
        "GET",
        "/v1/policy-authoring/harness-adapters",
        "List available agent harness adapters, their import/export commands, and the fidelity limits that prevent claiming equivalent agent resume.",
        "Use before handing a Wardwright trace to OpenCode, Codex, Claude, or another agent runner.",
        "Read-only. Treat adapter fidelity and equivalent_agent_resume as authoritative; do not infer hidden agent state preservation from an import command.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "export_agent_harness_trace",
        "POST",
        "/v1/policy-authoring/harness-adapters/{adapter_id}/export",
        "Export a recorded full-session trace as a reviewable artifact for an external agent harness.",
        "Use after loading a trace when an agent should inspect or continue from the recorded evidence outside the Wardwright UI.",
        "Read-only unless the caller asks the UI/backend to save files. Exported artifacts can include sensitive trace metadata; equivalent resume is false unless the adapter explicitly says true.",
        "/agent-authoring.html#replay-receipts-before-changing-policy"
      ),
      tool(
        "verify_harness_state_fidelity",
        "POST",
        "/v1/policy-authoring/harness-adapters/state-fidelity/verify",
        "Compare a saved state-fidelity probe with observed imported-harness state.",
        "Use after importing or resuming an external harness session to check whether trace and tool-result fingerprints survived the handoff.",
        "Read-only. Passing this probe does not by itself prove equivalent native agent resume; it only verifies the concrete exported evidence.",
        "/agent-control-debugger.html#opencode-client-run"
      ),
      tool(
        "export_regression_pack",
        "GET",
        "/v1/policy-authoring/scenarios/{pattern_id}/regression-export?format=json|exunit",
        "Export pinned scenario records as a deterministic regression pack or generated ExUnit source for native regression review.",
        "Use when turning reviewed simulator cases into tests or sharing a minimal behavior pack.",
        "Read-only, but exported content can include scenario details the user should review before publishing.",
        "/agent-authoring.html#record-scenarios-as-regression-evidence"
      ),
      tool(
        "apply_scenario_retention",
        "POST",
        "/v1/policy-authoring/scenarios/{pattern_id}/retention",
        "Prune oldest unpinned scenario records for a policy pattern while always preserving pinned regression scenarios.",
        "Use to keep local simulator evidence small after pinning the scenarios that matter.",
        "Write-capable. Deletes unpinned scenario records only; pinned regression scenarios are preserved.",
        "/agent-authoring.html#record-scenarios-as-regression-evidence"
      ),
      tool(
        "validate_policy_artifact",
        "POST",
        "/v1/policy-authoring/validate",
        "Validate the current or submitted policy artifact for structural errors, opaque regions, missing scenario coverage, and unsupported provider stream capabilities.",
        "Use after every draft or proposed change and before asking the user to activate a model.",
        "Read-only. Validation reports errors and review gaps; it does not replace human approval.",
        "/agent-authoring.html#validate-and-explain-gaps"
      )
    ]
  end

  def cli_descriptions do
    Enum.map(list(), fn tool ->
      path = tool["path"] || "not implemented"

      """
          #{tool["name"]}
            #{tool["method"]} #{path}
            #{tool["description"]}
            When to use: #{tool["when_to_use"]}
            Safety: #{tool["safety"]}
            Docs: #{tool["docs_url"]}
      """
    end)
  end

  defp tool(name, method, path, description, when_to_use, safety, docs_path) do
    %{
      "description" => description,
      "docs_url" => @docs_root <> docs_path,
      "method" => method,
      "name" => name,
      "path" => path,
      "safety" => safety,
      "when_to_use" => when_to_use
    }
  end
end
