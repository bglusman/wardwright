---
layout: default
title: Agent Adapters
description: Install, verify, and remove Wardwright local agent adapters.
---

# Agent Adapters

Status: adapter install support is part of the `0.1.0-rc.1` release-candidate
work. The published `v0.0.10` release may not include every command shown here.

Wardwright works as a normal OpenAI-compatible gateway without a local agent
adapter. Adapters add local identity, install-time checks, and runtime probes
for agent tools that expose a supported integration point. They do not turn a
trace into an exact cross-agent resume unless the adapter can prove that level
of state fidelity.

## Commands

```bash
wardwright adapters list
wardwright adapters list --json
wardwright adapters doctor
wardwright adapters doctor --json
wardwright adapters install omp
wardwright adapters pair omp
wardwright adapters probe omp
wardwright adapters uninstall omp
```

Project scope is the default and only packaged install scope today. User-global
adapter installation must be explicit in the CLI contract, but user scope is not
implemented yet; `--scope user` is rejected rather than silently writing outside
the project.

## Setup

Run adapter commands from the project workspace whose agent state you want
Wardwright to inspect. `list` is a static catalog. `doctor` checks local agent
binaries, installed Wardwright-owned files, paired identity state, and probe
evidence for that workspace.

Pairing requires a running Wardwright gateway. The gateway must have
`WARDWRIGHT_ADAPTER_IDENTITY_SECRET` set to a stable value of at least 16 bytes,
and the pairing shell must have `WARDWRIGHT_ADMIN_TOKEN` set so it can call the
protected pair endpoint. Use `WARDWRIGHT_GATEWAY_URL` when the gateway is not
listening at `http://127.0.0.1:8787`.

## Adapter States

`doctor` reports the state that Wardwright is willing to act on:

| State | Meaning |
| --- | --- |
| `not_detected` | The target agent binary or config surface was not found. |
| `installable` | The runtime was detected and Wardwright knows the adapter path. |
| `installed_unverified` | Files are present, but the gateway identity or probe has not been verified. |
| `verified` | A signed adapter identity validates for this workspace/session. |
| `verified_with_probe` | The adapter identity validates and the runtime probe passed. |
| `drifted` | Installed files no longer match the Wardwright adapter pack. |
| `unsupported_runtime` | The product was detected, but its active runtime does not expose a supported adapter path. |

Only `verified` and `verified_with_probe` may enable adapter-scoped recording
defaults. Stronger replay affordances require `verified_with_probe`.

`doctor --json` is the stable machine-readable form. It includes each target's
state, detected runtime, runtime source, installed paths, install plan, fidelity
label, and next actions. Human output is for operators and may add explanatory
wording.

## OMP / oh-my-pi

OMP is the first packaged install target because it has a project-local surface
and a runtime equivalence probe.

```bash
wardwright adapters doctor
wardwright adapters install omp
wardwright adapters pair omp
wardwright adapters probe omp
```

`install omp` writes only project-local files:

- `.omp/rules/wardwright-read-before-edit.md`
- `.omp/extensions/wardwright-state-fidelity.ts`
- `.omp/wardwright-adapter.json`
- `.omp/wardwright-adapter-manifest.json`

If any Wardwright-owned OMP file is present but edited, install refuses to
replace it. Review the edit first, then run:

```bash
wardwright adapters install omp --repair
```

`pair omp` asks the gateway for a short-lived local identity and stores it in
`.omp/wardwright-adapter.json`. Set `WARDWRIGHT_ADMIN_TOKEN` in the shell or
service environment before pairing; do not pass tokens as command arguments.
Pairing uses `WARDWRIGHT_GATEWAY_URL` when set, defaulting to
`http://127.0.0.1:8787`.

After pairing, `doctor` reports `verified` only when the signed identity still
validates for the current workspace. An expired identity, a missing gateway
signing secret, or a workspace mismatch leaves the adapter below verified state
or causes the gateway to reject adapter-scoped requests.

`probe omp` runs the packaged OMP TTSR runtime equivalence probe against the
installed rule and paired config. On success it stores sanitized probe evidence:
probe name, status, timestamp, runtime, adapter version, and an output digest.
It does not store the raw probe output or gateway token in the adapter config.

The probe requires the `omp` or `oh-my-pi` runtime to be installed and available
on `PATH`. If that binary is missing, Wardwright should report the missing
runtime rather than manufacturing probe success.

## Uninstall And Cleanup

```bash
wardwright adapters uninstall omp
```

Uninstall removes only files that still match the Wardwright adapter pack. Edited
or unknown files are skipped and reported so a local rule or extension is not
destroyed silently. After matching files are removed, Wardwright prunes empty
`.omp` adapter directories when possible.

Manual cleanup is safe when you no longer want any OMP adapter state. This
removes the local adapter identity and probe evidence for the project:

```bash
rm -f .omp/rules/wardwright-read-before-edit.md
rm -f .omp/extensions/wardwright-state-fidelity.ts
rm -f .omp/wardwright-adapter.json
rm -f .omp/wardwright-adapter-manifest.json
```

Do not delete unrelated `.omp` files unless they are yours to remove.

## Privacy And Recording

Generic OpenAI-compatible clients remain manual by default. Adapter-scoped
automatic recording applies only after the gateway verifies a Wardwright adapter
identity for the current workspace/session.

The gateway must not store the signed adapter identity token in receipts.
Receipts may include sanitized adapter trace metadata such as adapter id,
runtime, target, verification state, and recording decision. Raw prompts,
completions, provider credentials, and bearer tokens must stay out of adapter
files and logs by default.

## Fallback Behavior

No adapter is required to use Wardwright. When an adapter is missing,
unverified, drifted, or unsupported, Wardwright falls back to the generic
gateway/export behavior:

- model calls still use the OpenAI-compatible gateway;
- explicit recording controls still work;
- harness handoff can still produce best-effort exported artifacts;
- adapter-scoped recording defaults do not apply to generic clients;
- runtime probes are skipped unless the relevant adapter is installed, paired,
  and runnable.

## Runtime Surfaces

| Surface | Current behavior | Fidelity wording |
| --- | --- | --- |
| OMP / oh-my-pi | Packaged install, pair, probe, doctor, and uninstall. | `tts_runtime_probe` only after the OMP probe passes; otherwise no stronger claim than installed or verified identity. |
| Pi | Runtime resolution and adapter vocabulary exist, but packaged Pi install/probe is not complete. | `state_import_probe` is the intended label; exact resume parity is not claimed. |
| OpenCode with Pi or OMP runtime | `doctor` can report coverage through the underlying runtime adapter. | `runtime_verified` means the underlying runtime path is covered; OpenCode surface verification is a separate future probe. |
| OpenCode-native | Packaged plugin install is not complete; use the current harness export scaffold. | `session_import_best_effort`; do not claim Pi/OMP runtime verification. |
| OpenCode with Codex runtime | Gateway identity support is the intended path when packaged. | `prompt_handoff`; do not run or claim the OMP TTSR probe. |
| OpenClaw | Runtime-driven support is planned for Pi, Codex, and supported CLI backends. | Unsupported or unknown runtimes report `unsupported_runtime`. |
| Claude Code | Candidate for install/doctor/pair and gateway identity after OMP. | `prompt_handoff` until a documented native state/import path proves stronger fidelity. |

Use `wardwright adapters doctor --json` when another tool needs
machine-readable state, runtime, installed paths, install plan, and next
actions.
