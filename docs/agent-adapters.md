---
layout: default
title: Agent Adapters
description: Install, verify, and remove Wardwright local agent adapters.
---

# Agent Adapters

Status: adapter install support is part of the `0.1.0` release line.

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
wardwright adapters install pi
wardwright adapters install claude-code
wardwright adapters pair omp
wardwright adapters pair pi
wardwright adapters pair claude-code
wardwright adapters probe omp
wardwright adapters probe pi
wardwright adapters probe opencode
wardwright adapters uninstall omp
wardwright adapters uninstall pi
wardwright adapters uninstall claude-code
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
label, `surface_probe` status, and next actions. Human output is for operators
and may add explanatory wording.

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

## OpenCode Through OMP

OpenCode support remains runtime-driven. When `.opencode/wardwright-runtime.json`
resolves OpenCode to an OMP-backed runtime, `doctor` reuses the OMP adapter
state instead of treating OpenCode as a separate rule engine. If the underlying
OMP adapter is paired and probed, OpenCode may report `verified_with_probe` with
fidelity `runtime_verified`.

That does not prove the OpenCode surface itself reached the adapted runtime.
Run this only after `wardwright adapters probe omp` succeeds:

```bash
wardwright adapters probe opencode
```

The OpenCode surface probe is fail-closed. It invokes OpenCode's packaged
surface-probe command and records sanitized evidence only when the output
contains Wardwright's explicit surface-probe pass marker. After that, `doctor`
reports `surface_probe: passed` and upgrades the OpenCode fidelity label to
`surface_verified`.

OpenCode-native and Codex-backed OpenCode do not use this probe. OpenCode-native
remains best-effort harness export/plugin scaffold work and reports
`install_plan: no_install` until that packaged lifecycle is real. Codex-backed
OpenCode uses the future gateway-identity path rather than the OMP TTSR probe.

## Pi

Pi support is packaged as project-local Wardwright metadata plus gateway
identity. It does not claim a persistent Pi project extension surface.

```bash
wardwright adapters install pi
wardwright adapters pair pi
wardwright adapters probe pi
wardwright adapters uninstall pi
```

`install pi` writes only Wardwright-owned metadata under
`.wardwright/adapters/`:

- `.wardwright/adapters/pi-adapter.json`
- `.wardwright/adapters/pi-adapter-manifest.json`

The install output and `doctor --json` list the Pi replay pieces that remain
export-only: Pi session JSONL, the state-fidelity probe JSON, and import
commands. Those artifacts are produced by the harness export flow for a chosen
trace; they are not installed into the project as live Pi hooks.

`pair pi` stores a signed gateway identity in the Pi adapter metadata. After
pairing, `doctor` may report `verified` for the Pi adapter when the identity
validates for the current workspace. `probe pi` does not manufacture runtime
verification. It points operators back to the export flow: generate a Pi session
JSONL and `wardwright-state-fidelity-probe.json`, import the session into Pi,
then submit observed imported state to Wardwright's protected state-fidelity
verifier.

## Claude Code

Claude Code support is packaged as project-local Wardwright metadata plus
gateway identity. It does not claim native Claude Code transcript import,
session fork parity, or a runtime state-fidelity probe.

```bash
wardwright adapters install claude-code
wardwright adapters pair claude-code
wardwright adapters uninstall claude-code
```

`install claude-code` writes only Wardwright-owned metadata under
`.wardwright/adapters/`:

- `.wardwright/adapters/claude-code-adapter.json`
- `.wardwright/adapters/claude-code-adapter-manifest.json`

The metadata records fidelity `prompt_handoff` and
`native_state_fidelity: false`. `pair claude-code` stores a signed gateway
identity so adapter-scoped recording can apply to verified Claude Code
requests. It still remains a prompt or model-context handoff unless a future
documented Claude Code state/import path proves stronger fidelity.

## OpenClaw

OpenClaw support is runtime resolution, not a separate rule engine. When
`.openclaw/wardwright-runtime.json` describes a supported OpenClaw runtime,
`doctor` chooses the matching Wardwright adapter:

- `agentRuntime.id: pi` or `agentRuntime.id: auto` resolved to Pi uses the Pi
  adapter path.
- `agentRuntime.id: codex` or `openai-codex` reports Codex gateway-identity
  support and does not run the OMP/Pi runtime probe.
- `cliBackend.id: claude-cli` uses the Claude Code gateway-identity adapter and
  keeps fidelity at `prompt_handoff`.
- Unknown runtime ids stay `unsupported_runtime`.

OpenClaw does not have packaged `install`, `pair`, `probe`, or `uninstall`
commands of its own. Follow the next action from `wardwright adapters doctor`
and install, pair, or probe the selected underlying adapter, such as `pi` or
`claude-code`. This avoids claiming OpenClaw-native state fidelity or a separate
OpenClaw TTSR path.

## Uninstall And Cleanup

```bash
wardwright adapters uninstall omp
wardwright adapters uninstall pi
wardwright adapters uninstall claude-code
```

Uninstall removes only files that still match the Wardwright adapter pack.
Static files, such as OMP rules and extensions, are matched by digest. Dynamic
adapter metadata is matched by schema, adapter id, version, target, runtime, and
required fidelity fields so pairing can refresh gateway identity without making
the file look drifted. Edited, invalid, or unknown files are skipped and
reported so local state is not destroyed silently. After matching files are
removed, Wardwright prunes empty adapter directories when possible.

Manual cleanup is safe when you no longer want any OMP adapter state. This
removes the local adapter identity and probe evidence for the project:

```bash
rm -f .omp/rules/wardwright-read-before-edit.md
rm -f .omp/extensions/wardwright-state-fidelity.ts
rm -f .omp/wardwright-adapter.json
rm -f .omp/wardwright-adapter-manifest.json
```

Do not delete unrelated `.omp` files unless they are yours to remove.

For Pi, manual cleanup removes only Wardwright-owned adapter metadata:

```bash
rm -f .wardwright/adapters/pi-adapter.json
rm -f .wardwright/adapters/pi-adapter-manifest.json
```

For Claude Code, manual cleanup removes only Wardwright-owned adapter metadata:

```bash
rm -f .wardwright/adapters/claude-code-adapter.json
rm -f .wardwright/adapters/claude-code-adapter-manifest.json
```

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
| Pi | Packaged install, pair, doctor, uninstall, and export-only probe guidance. | `state_import_probe` means exported/imported Pi state can be checked with Wardwright's verifier; exact resume parity is not claimed. |
| OpenCode with Pi or OMP runtime | `doctor` can report coverage through the underlying runtime adapter. OMP-backed OpenCode can run `probe opencode` after the OMP runtime probe passes. | `runtime_verified` means the underlying runtime path is covered; `surface_verified` requires an explicit OpenCode surface probe. |
| OpenCode-native | Packaged plugin install is not complete; use the current harness export scaffold. | `session_import_best_effort`; do not claim Pi/OMP runtime verification. |
| OpenCode with Codex runtime | Gateway identity support is the intended path when packaged. | `prompt_handoff`; do not run or claim the OMP TTSR probe. |
| OpenClaw with Pi runtime | `doctor` reports coverage through the packaged Pi adapter. | `runtime_verified` inherits the Pi adapter state; Pi replay remains export-only unless separately verified. |
| OpenClaw with Codex runtime | `doctor` reports Codex gateway-identity support when the runtime config says `codex` or `openai-codex`. | `prompt_handoff`; do not run or claim the OMP/Pi runtime probe. |
| OpenClaw with Claude CLI backend | `doctor` points operators to the packaged Claude Code gateway-identity adapter. | `prompt_handoff`; no OpenClaw-native or Claude native state/import parity is claimed. |
| OpenClaw with unknown runtime | No adapter path is selected. | `unsupported_runtime`. |
| Claude Code | Packaged install, pair, doctor, and uninstall for gateway identity metadata. | `prompt_handoff`; no native state/import or runtime-probe parity is claimed. |

Use `wardwright adapters doctor --json` when another tool needs
machine-readable state, runtime, installed paths, install plan, and next
actions.
