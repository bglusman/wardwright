---
layout: default
title: Tool Mediation
description: Bidirectional tool visibility, patching, replacement, and receipt model.
---

# Tool Mediation

Wardwright tool mediation is the control plane between agent-visible tools and
provider-visible tools. The goal is not only to add Wardwright-hosted tools, but
to make every tool boundary inspectable, policy-controlled, and receipted.

Two views matter:

- To the provider/model, Wardwright-hosted tools can look like ordinary
  agent-declared tools.
- To the agent/client, provider-hosted tool use should become observable tool
  evidence when the provider exposes it.

The mediation layer therefore tracks both declaration and execution:

| Field | Meaning |
| --- | --- |
| `declared_by` | Who introduced the capability: `agent`, `wardwright`, `provider`, `mcp`, or `framework`. |
| `executed_by` | Who actually runs it: `agent`, `wardwright`, `provider`, or `remote_mcp`. |
| `visible_to_provider` | Whether the tool declaration is sent to the selected provider. |
| `visible_to_agent` | Whether tool use/result evidence is surfaced back to the caller. |
| `policy_state` | `allowed`, `hidden`, `blocked`, `wrapped`, `replaced`, `deferred`, or `opaque`. |
| `fidelity` | `pass_through`, `normalized`, `emulated`, `provider_attested`, or `opaque`. |

## Extension Modes

Advanced operators may want extension code to inspect or change provider
requests. Wardwright should support that, but the mode must be explicit:

| Mode | Extension capability | Default suitability |
| --- | --- | --- |
| `observe` | Read the normalized catalog and request, return annotations only. | Safe default for diagnostics. |
| `patch` | Return a typed patch plan that Wardwright validates and receipts. | Preferred default for production. |
| `mutate` | Rewrite provider requests directly. | Trusted local operator code only. |
| `execute` | Call tools or route tool execution from extension logic. | Requires budgets, loop limits, authorization, and result redaction. |

The first implementation slice supports non-streaming request-side `patch`
rules for OpenAI-compatible Chat Completions tool declarations. `observe` mode
is currently non-mutating and does not yet emit annotations. Wardwright does
not yet execute extension logic, mediate streaming tool-call deltas, or
normalize provider-hosted tool events.

## Request-Side Patch Rules

`tool_mediation.rules[]` can match declared tools by name and patch the
provider-visible catalog before the selected provider sees it:

```yaml
tool_mediation:
  mode: patch
  rules:
    - id: hide-pr-creation
      action: hide
      match:
        name: create_pull_request
```

This removes the matched tool from the provider request, which blocks the
selected model from choosing it on that request. If no tools remain, Wardwright
also removes `tool_choice` so the provider does not receive an orphaned tool
choice.

Rules can also augment a tool schema while preserving the tool name and
execution path:

```yaml
tool_mediation:
  rules:
    - id: policy-cache-context
      action: augment
      match:
        name: wardwright_policy_cache_status
      description_append: Only call this when policy-cache status is directly relevant.
```

Replacement is reserved for trusted schemas:

```yaml
tool_mediation:
  rules:
    - id: replace-search
      action: replace
      match:
        name: web_search
      tool:
        type: function
        function:
          name: wardwright_web_search
          description: Search through Wardwright's approved search backend.
          parameters:
            type: object
            additionalProperties: false
            properties:
              query:
                type: string
```

## Receipt Evidence

When mediation runs, receipts include:

```json
{
  "wardwright_tool_mediation": {
    "schema": "wardwright.tool_mediation.v1",
    "mode": "patch",
    "applied_rules": [
      {
        "id": "hide-pr-creation",
        "action": "hide",
        "matched_tools": ["create_pull_request"]
      }
    ],
    "original_tools": [
      {
        "declared_by": "agent",
        "name": "create_pull_request",
        "type": "function",
        "schema_hash": "sha256:..."
      }
    ],
    "provider_visible_tools": []
  }
}
```

The hash records schema change without storing the full schema in every receipt.
Future slices should add argument hashes, result hashes, tool-specific timing,
approval evidence, and provider-hosted event normalization.

## Provider Tool Normalization Backlog

Provider-hosted tools are not equivalent. Web search, URL fetch, file search,
code execution, computer use, and MCP connectors vary by provider in schema,
execution location, citation metadata, privacy behavior, approvals, and
streaming events.

Wardwright should normalize those surfaces behind stable capability contracts:

- `wardwright.web_search.v1`
- `wardwright.url_fetch.v1`
- `wardwright.file_search.v1`
- `wardwright.code_exec.v1`
- `wardwright.computer_use.v1`
- `wardwright.mcp_tool.v1`

Each provider implementation should declare what Wardwright can prove:

- provider-visible request schema
- provider-returned event shape
- citation/source metadata
- hidden or opaque execution gaps
- approval and side-effect semantics
- replay and privacy limits

Do not claim parity just because two providers both call something "web search".
The receipt must say whether the behavior was pass-through, normalized,
emulated, provider-attested, or opaque.
