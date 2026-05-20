---
layout: default
title: Provider Credentials
description: How Wardwright resolves provider API credentials and the security limits of the current prototype.
---

# Provider Credentials

Wardwright can call local Ollama targets without credentials and
OpenAI-compatible targets with bearer-token credentials. In `v0.0.10`, credential
configuration is still local-operator oriented, but model calls can now be
separately protected with Wardwright model API keys. That makes local and
single-operator remote testing more realistic, but it is not yet a complete
hosted or multi-user authorization model.

## Current Credential Sources

Provider targets support two credential reference fields:

- `credential_fnox_key`: preferred for local operator secrets. Wardwright calls
  `fnox get KEY` at request time and never stores the returned value in the
  model artifact.
- `credential_env`: acceptable for local development and live smoke tests.
  Wardwright reads the named environment variable at request time.

Ollama targets usually need no credential:

```json
{
  "model": "ollama/qwen2.5-coder:latest",
  "context_window": 32768,
  "provider_kind": "ollama",
  "provider_base_url": "http://127.0.0.1:11434"
}
```

OpenAI-compatible targets should reference a secret instead of embedding one:

```json
{
  "model": "openai/gpt-4.1-mini",
  "context_window": 128000,
  "provider_kind": "openai-compatible",
  "provider_base_url": "https://api.openai.com/v1",
  "credential_fnox_key": "WARDWRIGHT_OPENAI_API_KEY"
}
```

The repository includes a larger example at
[`config/provider-targets.example.json`](https://github.com/bglusman/wardwright/blob/main/config/provider-targets.example.json).

## Fnox

Wardwright does not bundle or install fnox yet. If a target uses
`credential_fnox_key`, the host running Wardwright must already have a working
`fnox` command on `PATH`.

The runtime contract is deliberately small:

```bash
fnox get WARDWRIGHT_OPENAI_API_KEY
```

If that command fails or returns an empty value, the provider attempt fails with
a `provider_error` before Wardwright calls the upstream provider.

One possible local setup flow is:

```bash
fnox init
fnox set WARDWRIGHT_OPENAI_API_KEY
fnox get WARDWRIGHT_OPENAI_API_KEY
```

Use fnox profiles or config files if you need different credential sets for
different projects. Wardwright currently only passes the key name to `fnox get`;
it does not manage fnox profiles, leases, or remote sync.

## Environment Variables

Environment variables are still supported because they are simple and useful for
tests:

```json
{
  "model": "openai/gpt-4.1-mini",
  "context_window": 128000,
  "provider_kind": "openai-compatible",
  "provider_base_url": "https://api.openai.com/v1",
  "credential_env": "WARDWRIGHT_LIVE_OPENAI_API_KEY"
}
```

They are not the recommended long-term storage story for remote operation. They
are acceptable for local development, CI smoke tests with tightly scoped
secrets, and short-lived experiments.

## Authentication Boundary

Encrypting provider credentials and authenticating access to Wardwright solve
different problems.

Fnox protects credential material at rest and keeps raw secrets out of model
artifacts, logs, recipes, and git. It does not decide who may call a
Wardwright-hosted Wardwright model. Model API keys do that for
`/v1/chat/completions` when a model artifact sets:

```json
{
  "requires_api_key": true,
  "auth": { "unkeyed_model_access": "public" }
}
```

Generate and revoke those keys from the protected `/admin` operator UI or the
protected admin API. Keys are scoped to one Wardwright model id and stored only
as hashes. A caller can use a valid key to spend or use the provider credentials
behind that model, but cannot read the raw provider secret.

For composition-only models, set:

```json
{
  "requires_api_key": false,
  "auth": { "unkeyed_model_access": "internal" }
}
```

Internal-only models do not appear in public model discovery and cannot be
called directly without a future explicit composition path. They are useful for
building model DAGs without exposing every intermediate model to agents.

For `v0.0.10`:

- keep Wardwright bound to `127.0.0.1` unless it is behind a trusted network or
  application auth boundary;
- set `WARDWRIGHT_ADMIN_TOKEN` before exposing protected admin or authoring
  APIs beyond loopback;
- require model API keys on every model that can reach real paid or private
  provider credentials before exposing `/v1/chat/completions` beyond loopback;
- keep intermediate composition models internal-only unless direct callers
  genuinely need them;
- treat fnox support as local secret lookup, not model-use authorization.

Before Wardwright is suitable for broad shared or hosted use with real provider
credentials, the project still needs deployment-topology-specific authorization:
who can call which Wardwright models, who can configure providers, how rate
limits and quotas are enforced, and how those decisions are audited.
