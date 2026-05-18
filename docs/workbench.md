---
layout: default
title: Policy Workbench
description: Visualize, simulate, and refine Wardwright model middleware.
---

# Policy Workbench

The Wardwright package includes a Phoenix LiveView workbench at `/policies`.
It is meant for inspecting Wardwright model middleware before wiring it into
production traffic: pick an example or local model, load a scenario, edit the
simulated request, model output, and relevant history, then step through the
resulting policy run.

The deterministic model artifact remains the source of truth. The workbench is
the review surface for understanding how that artifact compiles into routes,
state changes, stream guards, retries, tool controls, output changes, and
receipts.

<figure>
  <img src="assets/workbench/route-composition-simulator.png" alt="Wardwright workbench showing the context-window dispatcher example with route and model composition details">
  <figcaption>Route and model composition example: the simulator shows why the model graph chose a context-fit route and which larger routes remain available as fallbacks.</figcaption>
</figure>

## Simulator

The simulator follows one model call through Wardwright's boundaries:

1. Raw caller input and the input sent to the backend model.
2. Backend model output or stream chunks and the output released to the user.
3. Session history and policy memory used by threshold or sequence rules.
4. Route selection, state transitions, retries, rewrites, tool decisions, and
   receipt events.

Most simple examples have identical raw and delivered input/output. When a
policy changes a request, holds stream chunks, retries a generation, rewrites an
answer, or blocks a tool call, the simulator keeps both sides visible so the
change can be reviewed.

<figure>
  <img src="assets/workbench/stream-retry-simulator.png" alt="Wardwright workbench showing a time-travel stream retry example">
  <figcaption>Stream repair example: a held stream can trigger a retry with a targeted reminder, then release the corrected attempt instead of leaking the bad span or failing the whole request.</figcaption>
</figure>

## Example Categories

Fresh installs seed a starter workspace under
`~/.wardwright/recipes/policies`. The current `v0.0.5` example set is grouped
around the behaviors Wardwright is designed to make understandable:

- **Output evidence and contracts:** incomplete-success detection and structured
  output repair gates.
- **Route and model composition:** private-context route gates, context-window
  routing, partial-context model blends, and route-DAG delegation.
- **Stream repair and session state:** time-travel stream retry and credential
  redaction/state escalation examples.
- **Tool and workflow control:** repeated tool-call sequence detection and
  reviewable cost brakes.

<figure>
  <img src="assets/workbench/tool-governance-simulator.png" alt="Wardwright workbench showing tool-loop governance and policy simulation">
  <figcaption>Tool governance example: tool history can make an otherwise valid next call reviewable once the sequence becomes risky.</figcaption>
</figure>

## Local Models

The built-in examples are not special at runtime. The workbench reads policy
recipes from the configured workspace directory, grouping folders as example
collections. Locally authored Wardwright models that use a supported projection
shape are displayed, simulated, and inspected through the same UI as the seeded
examples.

Unsupported future policy shapes should fail clearly or remain hidden until the
projection contract supports them. That keeps the UI honest: a recipe catalog
entry can describe a model, but the simulator should only claim behavior it can
actually replay from deterministic policy data and simulation evidence.

## Agent-Assisted Authoring

Wardwright does not yet ship an in-page policy-writing agent, but it already
exposes tool discovery for external agents. After installing, run:

```bash
wardwright tools
wardwright tools --json
```

The same registry backs the protected policy-authoring API and the MCP endpoint
mounted at `/mcp`. Point a local agent at the Wardwright service, let it inspect
the available tools, and use the workbench to review the policy it creates.
See the [Agent Authoring Guide](agent-authoring.html) for the expected
inspect-simulate-draft-validate-review-activate loop.

The first useful write path is intentionally narrow:

- `draft_wardwright_model` builds and validates a Wardwright model artifact from
  supplied provider/model targets, route graph nodes, governance rules, and
  stream rules.
- `activate_wardwright_model` validates the same artifact and makes it the
  current local OpenAI-compatible model.
- `propose_rule_change` returns a draft artifact with an appended, replaced, or
  removed governance or stream rule. It is draft-only and never applies changes.

After activation, agents can call `/v1/chat/completions` with either the flat
model id such as `support-router` or the prefixed id
`wardwright/support-router`.
