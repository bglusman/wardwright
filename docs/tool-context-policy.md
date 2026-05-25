---
layout: default
title: Tool Context Policy
description: Tool-aware policy selectors, loop thresholds, receipts, and trust boundaries.
---

# Tool Context Policy

Wardwright normalizes request-visible tool facts before policy planning,
receipts, history, or UI projection consume them. The active prototype supports
OpenAI-compatible `tools`, `tool_choice`, assistant `tool_calls`, and `tool`
result messages by default. `metadata.tool_context` is accepted only from
trusted gateway paths such as localhost, prototype access, or requests carrying
the configured Wardwright admin token.

Tool policy is not a separate runtime or a replacement for ordinary behavioral
policy. It is one matcher dimension inside the same policy plan:

```text
state scope + lifecycle phase + tool context + caller/session/history -> action
```

Most policies use the default one-state state machine, named `active`. In that
case a tool rule simply says "when this tool context appears, take this ordinary
policy action." A more stateful policy can add `state_scope` without changing
what tool context means.

## Tool Lifecycle

Tool calls are not one uniform event. Wardwright uses phase names so policy and
UI can explain which part of the tool workflow is being governed:

- `planning`: a request declares available tools, forces `tool_choice`, or the
  model emits an assistant `tool_calls` item. This is the common "model wants a
  local agent/runtime to call a tool" case.
- `argument_repair`: a model call is producing or repairing arguments for a
  known tool schema. This is where stricter JSON/schema routing often belongs.
- `result_interpretation`: a later request includes a `tool` result message and
  the model is summarizing it, validating it, or choosing the next action.
- `loop_governance`: policy counts repeated equivalent tool facts in recent
  history, usually by session/run first and broader scopes only after durable
  privacy rules exist.
- `unknown`: Wardwright saw tool-like facts but cannot confidently classify the
  phase.

Provider-hosted tools such as built-in web search complicate this model. Some
providers return explicit events for hosted tools; for example OpenAI Responses
can include `web_search_call` output items, and Anthropic streams
`server_tool_use` / `web_search_tool_result` blocks for server-side search. If
Wardwright sees those events, it can normalize them as provider-attested tool
facts. If a provider performs internal tool work without exposing events or
usage details, Wardwright can only govern the pre-call route/provider/tool
configuration and the final visible response; it cannot inspect or stop each
hidden internal step.

Wardwright-owned server-side tools are a separate explicit extension surface.
They should not be hidden broad execution authority inside the
OpenAI-compatible Chat Completions path. Current Chat Completions tool support
mostly stays pass-through and policy evidence: clients or providers execute
tools, while Wardwright normalizes visible `tools`, `tool_choice`, `tool_calls`,
tool results, and provider-exposed hosted tool events. The `0.1.0` spike adds a
small server-tool registry and execution loop with three explicit engines:
read-only built-ins, trusted local Dune functions, and trusted BEAM modules
loaded from a local path. The first built-in tool is
`wardwright_policy_cache_status`; extension modules can be written in Elixir,
Gleam, or Erlang as long as the loaded BEAM module exports `spec/0` and
`run/2`. Every Wardwright-hosted tool must be explicit about who executes it
and what Wardwright can prove:

| Execution location | Visibility level | Meaning |
| --- | --- | --- |
| `client` | `remote_observed` | The caller or local agent executes the tool outside Wardwright, and Wardwright sees structured request/result evidence when supplied. |
| `wardwright` | `local_verified` | Wardwright executes the configured tool and receipts explicit execution metadata plus result or error metadata. Argument hashes, tool-specific timing, and richer allow/deny policy evidence remain follow-up work. |
| `provider` | `provider_attested` | A provider-hosted tool exposes structured events or result metadata that Wardwright can record but not directly control. |
| `remote_mcp` | `remote_observed` | A remote MCP or service executes the call, while Wardwright observes structured call/result evidence through an explicit integration. |
| `unknown` | `opaque` | Wardwright can govern only the pre-call request/provider choice and final visible response. |

Datalog-style or other derived history queries, if they prove useful, should sit
behind this future Wardwright-hosted read-only tool surface or behind internal
typed policy predicates. They should not become a second hidden policy engine
or a model-facing query language before the fact schema, cost bounds, and
receipt evidence are explicit.

The first registered server tool is configured per Wardwright model:

```yaml
server_tools:
  - name: wardwright_policy_cache_status
```

Trusted Dune functions are configured with either inline source or a saved
snippet id. Model-supplied tool arguments become the Dune `input` map, merged
over any configured `input` defaults:

```yaml
server_tools:
  - engine: dune
    name: dune_echo_tool
    description: Echo a value through a trusted local Dune function.
    source: |
      %{"echo" => input["value"]}
    parameters:
      type: object
      additionalProperties: false
      properties:
        value:
          type: string
```

Trusted BEAM modules are loaded from an explicit local `.ex/.exs`, `.erl`, or
`.beam` path, then called through `spec/0` and `run/2`:

```yaml
server_tools:
  - engine: beam_module
    module: MyApp.WardwrightTools.ReverseTool
    path: /opt/wardwright/tools/reverse_tool.exs
```

`elixir_module` is accepted as a compatibility alias for `beam_module`; Gleam
and Erlang modules use the same BEAM contract. These modules run inside the
Wardwright BEAM and are trusted operator code, not a sandbox boundary.

In non-streaming Chat Completions, Wardwright advertises that tool to the
selected provider, executes a matching model-requested call once, appends a tool
result message, and asks the provider for the final answer. Receipts record
`final.provider_metadata.wardwright_server_tools[]` with the call id, tool name,
`execution_location: wardwright`, `visibility_level: local_verified`, status,
engine, and result or error metadata. Extension authors should return
receipt-safe metadata because Wardwright does not yet redact arbitrary local tool
output. Streaming, side-effecting tools, remote MCP passthrough, and hidden
provider tools remain deferred.

Tool mediation is the broader control plane around this first server-tool
surface. Request-side mediation can inspect agent-declared and Wardwright-added
tool declarations, patch the provider-visible catalog, and record original vs
final tool schema hashes under
`final.provider_metadata.wardwright_tool_mediation`. See
[Tool Mediation](tool-mediation.html) for the extension modes and backlog.

Tool-aware governance currently has four built-in rule shapes:

- `allowed_tools` declares the first-class tool surface for a state and phase.
  Matching tools pass silently; unlisted requested tools emit the existing
  `block` action with receipt evidence and fail closed before provider
  execution.
- `tool_selector` matches normalized tool context and emits ordinary policy
  actions such as `restrict_routes`, `switch_model`, `reroute`, `block`,
  `annotate`, or `alert_async`.
- `tool_loop_threshold` counts repeated normalized tool facts in bounded policy
  history and emits ordinary policy actions when the threshold fires.
- `tool_sequence` evaluates ordered relationships between scoped tool/state
  facts. It can transition policy state after a matched tool event, or apply a
  later action when an `after` event is still inside the configured window and no
  `until` reset has occurred.

Those rule shapes cover explicit tool surfaces, current-event matching,
repeated-tool counting, and a first pass at ordered sequence control. The
sequence implementation deliberately uses explicit state/window predicates so
authors can see why a later tool was blocked.

Receipts expose normalized `request.tool_context`, `decision.tool_context`,
`decision.tool_policy_selectors`, and `final.tool_policy` when relevant. Receipt
summaries can filter by tool namespace, name, phase, risk class, source, call
ID, and tool-policy status.

## Sequence Policy

Searchable history is the foundation for sequence control. Sequence-aware policy
makes ordering, scope, windows, and reset conditions first-class:

- `after`: a prior tool event that must have occurred. Prior-state and receipt
  predicates are useful future extensions, but are not sequence starters yet.
- `before`: the later/current event facet that is being governed, usually
  expressed as `then.tool` when the rule also names an action.
- `within`: the turn, event-count, or wall-clock window where the prior event is
  still relevant. Wall-clock windows accept `ms` or `milliseconds`.
- `until`: the state transition or tool event that clears the condition.
- `cache_scope`: the caller/session/run boundary that owns the sequence.
- `then`: the ordinary policy action applied when the later tool facet appears.

Example:

```yaml
state_machine:
  initial_state: active
  states:
    - id: active
    - id: reviewing_untrusted_tool_result

governance:
  - id: enter-untrusted-review
    kind: tool_sequence
    after:
      tool:
        namespace: browser
        phase: result_interpretation
    within:
      milliseconds: 30000
    transition_to: reviewing_untrusted_tool_result

  - id: block-shell-while-reviewing
    kind: tool_selector
    state_scope: reviewing_untrusted_tool_result
    action: block
    tool:
      namespace: shell
      risk_class: irreversible
      phase: planning
```

The current runtime supports this scoped shape for tool facts and policy-state
facts. It is still intentionally narrow: windows are recent event/turn or
wall-clock windows, state is represented by the latest scoped `policy_state`
fact, and raw tool payloads stay out of history. Multiple independent state
machines in the same session should use disjoint state names for now; a future
`state_machine_id` facet should make that isolation explicit.

## Allowed Tools Slice Note

Plan: add a minimal `allowed_tools` governance rule that is explicit about
`state_scope`, `phase`, and allowed tool identities. Enforcement stays in
`Wardwright.Policy.Plan` after `Wardwright.ToolContext` normalization, so
receipts, route blocking, and validation use the existing policy path.

Adversarial plan review: the unsafe shortcut would be a separate tool firewall
beside policy planning, because it would drift from route constraints, receipts,
state scope, and existing fail-closed behavior. The narrow rule also avoids
turning `tool_selector` into a denylist/allowlist grab bag whose action
semantics depend on convention.

Implementation notes: `allowed_tools` compares the normalized request
`primary_tool` plus declared `available_tools` against a non-empty allowlist for
the current phase. If every requested tool matches, the rule emits no policy
action. If any requested tool is unlisted, Wardwright records a normalized
`block` action containing `allowed_tools`, `blocked_tools`,
`allowed_tool_phase`, `state_scope`, and `tool_context`, then fails closed
through the existing provider-outcome path.

Adversarial implementation/design review: the slice is intentionally limited to
request-visible tool facts. Hidden provider-hosted tools remain governed only by
pre-call configuration and whatever provider events become visible later. The
rule currently uses the latest scoped `policy_state`, so multiple independent
state machines in one cache scope still need disjoint state names until the
runtime gains a `state_machine_id` facet.

Test evidence: focused tests cover a state transition into
`reviewing_tool_result`, an allowed review tool that passes with no action, an
unlisted shell tool that fails closed with block receipt evidence, validation
errors for missing phase/tool identity, and projection output for the new
allowed-tools node.

## Problems To Validate

These are the concrete problem hypotheses tool-aware policy should help test.
They are not all proven product value yet; each should be evaluated with
simulation, receipts, and eventually live traces.

### Write-Tool Hardening

Problem: a coding or ops agent may safely use read-only tools most of the time,
then suddenly prepare a write-capable action such as `github.create_pull_request`,
`filesystem.write`, `database.migrate`, `calendar.create_event`, or
`shell.exec`. OWASP classifies unchecked autonomy as excessive agency, and
insecure plugin/tool design can turn untrusted inputs into severe downstream
effects.

Tool policy hypothesis: keep the same public Wardwright model, but attach stricter
route, schema, audit, or approval rules only when the tool context implies write
or external side effects.

Example:

```yaml
governance:
  - id: high-risk-write-tools
    kind: tool_selector
    action: switch_model
    target_model: managed/strict-json
    attach_policy_bundle: write_tool_validation_v1
    tool:
      risk_class: write
      phase: planning
```

Falsify it if strict routing rarely catches malformed or risky arguments, adds
too much latency, or policy authors cannot predict when it fires.

### Prompt-Injection Containment

Problem: browser, email, document, and MCP tools pull untrusted content into the
agent loop. Anthropic's computer-use documentation explicitly describes an
agent loop where the application executes tool requests and returns results, and
warns that logged-in/browser use increases prompt-injection risk. Recent MCP
research also reports prompt-injection and tool-poisoning failures across real
AI-assisted development tools.

Tool policy hypothesis: treat result interpretation after untrusted tools as a
distinct phase. Route it through stronger review, block high-risk follow-on
tools, or require a clean planning step before allowing writes.

Example:

```yaml
governance:
  - id: browser-result-before-write
    kind: tool_selector
    action: restrict_routes
    routes: ["managed/injection-aware"]
    tool:
      namespace: browser
      phase: result_interpretation

  - id: no-shell-after-untrusted-page
    kind: tool_selector
    action: block
    tool:
      namespace: shell
      risk_class: irreversible
      phase: planning
```

The second rule is intentionally shown as a tool facet, not the full sequence
condition. In a stateful policy, the UI should compile "after untrusted page
result" into a post-result state or a bounded session-history predicate, then
apply the shell facet inside that state.

Falsify it if result-phase routing does not reduce bad follow-on tool proposals,
or if the policy cannot distinguish malicious instructions from legitimate page
content well enough to help.

### Tool Loop And Cost Control

Problem: tool-capable agents can loop on search, browser, shell, or API calls,
causing cost, latency, rate-limit, or operational noise. Provider docs for
computer use recommend explicit iteration limits. Hosted web search tools expose
provider-side controls such as domain filters, and some providers expose search
use caps such as `max_uses`.

Tool policy hypothesis: normalized tool facts make repeated tool attempts
visible in receipts and allow session/run-scoped budgets without hard-coding
logic into every agent.

Example:

```yaml
governance:
  - id: repeated-searches
    kind: tool_loop_threshold
    action: switch_model
    target_model: managed/diagnostic
    threshold: 4
    cache_scope: session_id
    tool:
      namespace: provider.web_search
      phase: planning
```

Falsify it if loops are better controlled entirely by provider-native `max_uses`
or by the application runtime, with no added value from Wardwright receipts or
simulation.

### Provider-Hosted Tool Visibility

Problem: some tools run inside the provider backend, such as hosted web search
or file search. When providers expose events like OpenAI `web_search_call` or
Anthropic `server_tool_use` / `web_search_tool_result`, Wardwright can normalize
those facts. When the provider hides internal tool steps, Wardwright cannot
inspect or interrupt them.

Tool policy hypothesis: provider capability records should declare which hosted
tool events are visible, which controls can be set pre-call, and which parts are
opaque. The UI can then show "controllable", "observable", and "opaque" tool
regions instead of pretending all tool use is equally governable.

Falsify it if most high-value hosted tools expose too little event data for
receipts or simulation to improve operator decisions.

### Least-Privilege Tool Surfaces

Problem: agents often receive a broad tool list because it is easier than
building a per-step tool surface. Tool-risk research describes both excessive
agency, where agents retain unnecessary permissions, and insufficient agency,
where missing needed tools hurts task completion.

Tool policy hypothesis: tool context plus state/phase facets can compile a
narrower tool surface for each step while preserving the same model contract.
The operator should be able to compare "all tools available" versus
"phase-scoped tools only" in simulation.

Falsify it if narrowed tool surfaces break too many legitimate workflows, or if
authors cannot understand why a tool was unavailable at a given step.

## Composition Examples

The simplest tool-specific rule works in the default `active` state and only
narrows behavior for one tool family:

```yaml
governance:
  - id: github-write-planning
    kind: tool_selector
    action: switch_model
    target_model: managed/write
    tool:
      namespace: mcp.github
      name: create_pull_request
      phase: planning
      risk_class: write
```

Ordinary behavioral policy can sit beside that rule without knowing about
tools:

```yaml
governance:
  - id: private-context-route
    kind: route_gate
    action: restrict_routes
    match: "customer|credential|secret"
    routes: ["local/private"]

  - id: github-write-planning
    kind: tool_selector
    action: switch_model
    target_model: managed/write
    tool:
      namespace: mcp.github
      risk_class: write
      phase: planning
```

Those rules compose because both emit ordinary route/policy effects. A request
that mentions private context and plans a GitHub write tool may need conflict
arbitration if the rules constrain routes differently; otherwise they can be
reviewed as independent facets.

The target stateful contract adds state as another explicit scope, not as a
nested policy tree:

```yaml
state_machine:
  initial_state: observing
  states:
    - id: observing
    - id: repairing_tool_args

governance:
  - id: repair-github-pr-args
    kind: tool_selector
    state_scope: repairing_tool_args
    action: switch_model
    target_model: managed/strict-json
    attach_policy_bundle: strict_tool_argument_repair_v1
    tool:
      namespace: mcp.github
      name: create_pull_request
      phase: argument_repair
```

The current runtime already supports tool facets, phase facets, reads, writes,
effects, and conflict findings in projection data. The UI should present state
scope the same way once the engine enforces state-scoped rules. Users can keep
tool policy separate from broader behavior by giving it narrow tool matchers, or
intentionally compose it with route gates, stream guards, structured-output
rules, and alert rules.

The detailed boundary is recorded in
[`contracts/tool-context-policy-contract.md`](https://github.com/bglusman/wardwright/blob/main/contracts/tool-context-policy-contract.md).

## Provider References

- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
  includes prompt injection, insecure plugin design, excessive agency, and
  related risks for LLM applications.
- [OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search)
  exposes hosted search through Responses API tool configuration and
  `web_search_call` output items.
- [Anthropic web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
  exposes server-side search configuration plus `server_tool_use` and
  `web_search_tool_result` response blocks.
- [Anthropic computer use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool)
  describes the agent loop and security concerns around logged-in/browser
  environments.
- [AgenTRIM: Tool Risk Mitigation for Agentic AI](https://arxiv.org/abs/2601.12449)
  frames tool-driven agency risks and proposes per-step least-privilege tool
  access.
- [Are AI-assisted Development Tools Immune to Prompt Injection?](https://arxiv.org/abs/2603.21642)
  studies prompt-injection and tool-poisoning risks across MCP clients.
