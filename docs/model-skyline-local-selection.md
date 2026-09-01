---
layout: default
title: ModelSkyline Local Selection Consumer
description: Experimental fail-closed consumption of a local ModelSkyline SelectionSnapshot.
---

# ModelSkyline Local Selection Consumer

Wardwright can experimentally consume a ModelSkyline `SelectionSnapshot` when
admitting a new agent work unit. The selector is supported only on a top-level
serving model; embedded Wardwright-model artifacts that contain one are
rejected. This phase-0 integration is intentionally a small local trust
boundary: it reads one regular JSON file, verifies the snapshot digest and a
narrow routing envelope against exact operator expectations, maps each selected
offering to an existing direct Wardwright target, and routes in the snapshot's
order.

Wardwright does not calculate a frontier, fetch a feed, publish a snapshot, or
change an admitted run when the file changes. ModelSkyline remains responsible
for evidence, frontier calculation, selection policy, and publication.

## Configuration

Add `model_skyline` to a Wardwright model definition. The source path must be
absolute. Every binding contains the complete offering key from ModelSkyline,
not just a convenient provider model name.

```json
{
  "model_id": "coding-balanced",
  "version": "2026-08-31",
  "requires_api_key": true,
  "targets": [
    {
      "model": "openai/gpt-5.4",
      "context_window": 262144,
      "provider_kind": "openai-compatible"
    },
    {
      "model": "anthropic/claude-fable-5",
      "context_window": 262144,
      "provider_kind": "openai-compatible"
    }
  ],
  "model_skyline": {
    "selection_path": "/var/lib/model-skyline/coding-agent-defaults.json",
    "expected_selection_id": "coding-agent-defaults",
    "expected_frontier_id": "coding-value",
    "expected_workload": {
      "id": "coding-session",
      "version": "v1",
      "unit": "completed_session"
    },
    "bindings": [
      {
        "offering": {
          "offering_id": "openai/gpt-5.4@direct-us",
          "model_id": "gpt-5.4",
          "provider": "openai",
          "endpoint": "responses",
          "billing_mode": null,
          "region": "us",
          "service_tier": "standard",
          "quantization": null,
          "reasoning_effort": "medium",
          "agent_harness": "wardwright",
          "capabilities": ["reasoning", "tools"]
        },
        "target_model": "openai/gpt-5.4"
      },
      {
        "offering": {
          "offering_id": "anthropic/claude-fable-5@direct-us",
          "model_id": "claude-fable-5",
          "provider": "anthropic",
          "endpoint": "messages",
          "billing_mode": "direct",
          "region": "us",
          "service_tier": "standard",
          "quantization": null,
          "reasoning_effort": null,
          "agent_harness": "wardwright",
          "capabilities": ["tools"]
        },
        "target_model": "anthropic/claude-fable-5"
      }
    ]
  }
}
```

The binding must equal the selected offering in every field, including
provider, endpoint, billing mode, region, tier, quantization, reasoning effort,
harness, and capabilities. `target_model` must name an existing direct target;
nested Wardwright-model targets are rejected. Offering IDs and target models
must each be unique in the bindings. This prevents a catalog alias from
silently mapping a provider-, region-, or tier-specific selection to a
different commercial offering. Phase 0 accepts between 1 and 64 bindings per
Wardwright model definition. A binding is an operator attestation: Wardwright
detects snapshot-versus-binding drift, but it cannot prove that a misconfigured
or behavior-changing upstream target actually serves the attested commercial
offering.

`requires_api_key` must be `true`; Wardwright rejects an unkeyed ModelSkyline
configuration. Serving callers must authenticate with a model-scoped
Wardwright API key and provide a nonblank `run_id` using the
`x-wardwright-run-id` header or request `metadata.run_id`. The stable,
content-free API-key record ID is the authenticated principal. The work-unit
identity also includes every available tenant, application, consuming agent,
consuming user, session, and run scope. A serving request without a valid key
or run ID fails closed.

## Admission And Pinning

For the first serving request with a `(Wardwright model_id, model version,
authenticated principal, available caller scopes)` combination, Wardwright:

1. reads at most 10 MiB from the configured path;
2. rejects relative paths, a final path that is a symlink, directories, special
   files, and a file whose identity changes while it is read; parent path
   components may still traverse symlinks and must remain operator-controlled;
3. validates the supported routing envelope, canonical SHA-256 digest,
   selection ID, frontier ID, workload identity, generation time, expiry, and a
   maximum one-year TTL;
4. requires exact full-offering bindings for every selected choice; and
5. stores an immutable in-memory lease and restricts the request's route graph
   to those mapped targets in snapshot order.

The in-memory key contains separate domain-separated SHA-256 digests for the
authenticated principal and complete caller-scope identity. It retains neither
the API-key record ID nor raw caller identities. Once admitted, the work unit
keeps its lease even if the source file is replaced or becomes unreadable. It
does not silently move to a newer snapshot before `valid_until`.

`valid_until` ends the pin. Expired leases are pruned, and the next request is
a fresh admission: it fails if the configured artifact is still expired or
invalid, while a newer valid artifact may be admitted. A local selection
configuration or target-definition change still fails an active pin closed.

Context-window checks still apply. They can skip an ordered candidate that
cannot fit the request. The existing cascade currently describes ordered
selection candidates; it does **not** retry the next ModelSkyline candidate
after an operational provider error. Phase 0 makes no provider-error-fallback
claim.

## Receipt Evidence

The decision section records a `model_skyline` object with status, selection
and frontier IDs, snapshot and policy hashes, frontier snapshot ID, workload,
valid-until time, pin scope, and ordered offering IDs. It deliberately omits the
source path, raw run ID, and Wardwright target names. Wardwright's normal
`caller` receipt section may still contain caller identity fields, including a
run ID, under the existing receipt policy.

Admission failures record a stable content-free error code such as
`missing_run_id`, `invalid_selection_digest`, `selection_binding_mismatch`, or
`expired_selection`; they do not include the source path or file contents.

Protected `/v1/wardwright/simulate` calls and serving requests already failed
closed by policy resolve the current artifact read-only. They never consult or
create a pin, and their selection receipt metadata uses
`status: preview_unpinned` and `pin_scope: none`.

## Phase-0 Trust Boundary And Limits

This is a local-file consumer for an operator-controlled publisher, not a
general distribution protocol.

- There is no HTTPS source, signature verification, publisher identity,
  transparency log, or durable anti-rollback state. A valid digest proves
  internal consistency, not authenticity. Protect the directory and publish by
  replacing a temporary regular file atomically.
- Pins are process memory only. A Wardwright restart forgets them, so a repeated
  authenticated work-unit identity can be admitted against the then-current
  file. Do not claim durable work-unit pinning in phase 0.
- Expired leases are pruned on pin lookup, insertion, and runtime status. Each
  authenticated principal may hold at most 64 live pins per model/version
  process, and each model/version process may hold at most 1,024 live pins in
  total. New work units fail closed at either capacity. There is no rate limiter
  or durable quota in phase 0. Restarting clears the pins, with the durability
  consequence above.
- The parser accepts the current publisher-normal
  `model-skyline/v1alpha1` selection shape and a fail-closed RFC 8785 subset:
  no duplicate object names, no floating-point JSON values, integers only in
  the interoperable safe range, bounded nesting and node count, and valid
  I-JSON strings. Every selected choice must contain 1–64 named axes, and every
  axis must be a non-null estimate object with a bounded decimal-string `value`
  and nonblank string `unit`; known optional evidence fields receive bounded
  type checks. Unknown fields and unsupported future selection strategies are
  rejected.
- This is routing-envelope validation, not complete verification of every
  invariant in ModelSkyline's release JSON Schema. Wardwright does not
  recompute frontier math, quality evidence, ordering scores, or selection
  policy. The digest binds those publisher-provided values but does not make
  them true.
- Wardwright accepts both the current digest form, which omits a null
  `billing_mode`, and the earlier explicit-null compatibility form. Golden
  fixtures generated by ModelSkyline lock the cross-language canonical bytes,
  including UTF-16 object-key ordering.

The Elixir map-boundary baseline increases for this slice are intentional and
confined to adapters for operator configuration, the external JSON snapshot,
and existing caller-provenance maps. Those adapters validate into
`SelectionSnapshot`, `Choice`, `Lease`, and `WorkUnit` structs before routing or
runtime state uses the values. Axis names remain dynamic by product contract;
their estimate maps are validated at the snapshot boundary and used only as
digest-bound receipt evidence, not as routing arithmetic in Wardwright.

The next integration phase needs an authenticated publisher transport, durable
pin/anti-rollback storage, an explicit compatibility/version negotiation story,
and separately specified provider-attempt fallback semantics.
