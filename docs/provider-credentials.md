---
layout: default
title: Provider Credentials
description: How Wardwright resolves provider API credentials and the security limits of the current prototype.
---

# Provider Credentials

Wardwright can call local Ollama targets without credentials and
OpenAI-compatible targets with bearer-token credentials. In `v0.0.5`, credential
configuration is intentionally local-operator oriented. It is useful for
development and homelab-style evaluation, but it is not yet a complete hosted or
multi-user authentication model.

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
Wardwright-hosted Wardwright model. If an untrusted caller can reach
`/v1/chat/completions`, they may be able to spend or use whatever provider
credentials Wardwright is configured to use, even though they cannot read the
secret value directly.

For `v0.0.5`:

- keep Wardwright bound to `127.0.0.1` unless it is behind a trusted auth
  boundary;
- set `WARDWRIGHT_ADMIN_TOKEN` before exposing protected admin or authoring
  APIs beyond loopback;
- do not configure real provider credentials on a Wardwright instance reachable
  by untrusted users;
- treat fnox support as local secret lookup, not product authentication.

Before Wardwright is suitable for shared or remote use with real provider
credentials, the project needs an explicit authorization model for who can call
which Wardwright models, who can configure providers, and how those decisions are
audited.
