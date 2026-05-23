---
title: Agent Adapter Install and Validation Requirements
---

# Agent Adapter Install and Validation Requirements

This is the build/test target for the next Ralph loop after the Pi/OMP replay
spike. The loop should continue until Wardwright can install, configure,
verify, and safely use agent adapters from a packaged release without manual
file copying.

## Release Goal

Wardwright `0.1.0-rc.1` should be able to say:

> Wardwright records, replays, and compares agent-policy behavior. It can
> install verified local adapters that improve live-agent visibility and
> enforcement, while retaining today's generic gateway/export fallback when no
> adapter is present.

The release must not claim exact cross-agent resume equivalence. Adapter-backed
continuation remains best-effort until state-fidelity probes prove otherwise.

## Product Requirements

### Adapter CLI

Packaged Wardwright must provide:

```bash
wardwright adapters list
wardwright adapters doctor
wardwright adapters install <target> [--scope project|user]
wardwright adapters uninstall <target> [--scope project|user]
wardwright adapters probe <target>
wardwright adapters pair <target>
```

`project` scope is the default. User-global installation is allowed only with
an explicit `--scope user` flag.

### Adapter States

Every adapter target must report one of these states:

- `not_detected`: required agent binary/config surface is absent.
- `installable`: agent/runtime was detected and Wardwright knows how to install
  support files.
- `installed_unverified`: files are present but Wardwright has not observed
  adapter identity or a successful probe.
- `verified`: adapter identity reached the Wardwright gateway for the current
  workspace/session.
- `verified_with_probe`: runtime probe passed.
- `drifted`: installed files/config do not match the expected adapter pack.
- `unsupported_runtime`: the product was detected, but its active runtime does
  not expose a supported Wardwright adapter path.

Only `verified` or `verified_with_probe` may enable adapter-scoped recording
defaults. Stronger replay affordances should require `verified_with_probe`.

### Runtime-Based Detection

Wardwright should detect the active runtime, not only the product name.

| Surface | Runtime detected | Required Wardwright behavior |
| --- | --- | --- |
| `omp` | OMP/Pi native | Install and probe the OMP adapter. |
| `pi` | Pi native | Install and probe the Pi adapter. |
| OpenCode | Pi-backed or OMP-backed | Reuse the Pi/OMP adapter and mark OpenCode as covered through that runtime. |
| OpenCode | OpenCode-native | Install the OpenCode plugin/import scaffold only; report lower fidelity. |
| OpenCode | Codex-backed | Install Codex/gateway identity support only; do not claim Pi/OMP TTSR behavior. |
| OpenClaw | `agentRuntime.id = pi` or `auto -> pi` | Reuse the Pi adapter. |
| OpenClaw | `agentRuntime.id = codex` | Install Codex/gateway identity support. |
| OpenClaw | CLI backend, such as Claude CLI | Install the target CLI adapter when available; otherwise report `unsupported_runtime`. |

The `doctor` output must explain the resolution. Example:

```text
OpenCode: detected
  runtime: pi via pi-opencode-bridge
  adapter: wardwright-omp
  status: installable
```

### Gateway Adapter Policy

The gateway must be able to distinguish:

- generic OpenAI-compatible clients;
- clients that declare a Wardwright adapter identity;
- verified adapters for the current workspace/session;
- verified adapters with passing runtime/state probes.

Recording policy must support at least:

```yaml
recording:
  default: manual
  adapted_agents: auto
  generic_clients: manual
```

Adapter-scoped auto-recording must not silently apply to generic clients.
Explicit recording controls must keep working for all clients.

### Pairing and Identity

`wardwright adapters pair <target>` must create or refresh a local trust link
between the adapter and gateway.

The adapter identity must include:

- adapter id, such as `wardwright-omp`;
- adapter version;
- target surface, such as `omp`, `pi`, `opencode`, or `openclaw`;
- detected runtime, such as `pi`, `omp`, `opencode-native`, or `codex`;
- workspace root or stable workspace fingerprint;
- gateway URL;
- short-lived token or revocable local credential.

The gateway must reject malformed, expired, or wrong-workspace identities.

### Install Targets

#### OMP

The OMP adapter install must write project-local files by default:

- `.omp/rules/wardwright-read-before-edit.md`
- `.omp/extensions/wardwright-state-fidelity.ts`
- any adapter identity/config file required for gateway pairing

`probe omp` must run the OMP TTSR runtime equivalence probe against the current
installed rule and adapter identity.

#### Pi

The Pi adapter install must provide:

- session/import helper configuration when needed;
- adapter identity/pairing support;
- state-fidelity probe support for exported/imported sessions.

If Pi has no persistent project extension surface for a particular behavior,
`install pi` must report which pieces are export-only.

#### OpenCode

OpenCode support must first resolve the active runtime:

- if OpenCode uses a Pi/OMP-compatible runtime, install the Pi/OMP adapter and
  report OpenCode as covered through that runtime;
- if OpenCode is OpenCode-native, install only the current plugin/import
  scaffold and report `session_import_best_effort`;
- if OpenCode uses Codex as its core runtime, install Codex/gateway identity
  support and do not run the Pi/OMP TTSR probe.

OpenCode may report both:

- `runtime_verified`: the underlying runtime probe passed;
- `surface_verified`: invoking through OpenCode actually reaches the runtime
  with Wardwright identity visible to the gateway.

#### OpenClaw

OpenClaw support is runtime integration, not a separate rule engine by default.
The adapter must inspect OpenClaw runtime config and choose the matching
Wardwright adapter:

- Pi runtime -> Pi adapter;
- Codex runtime -> Codex/gateway identity support;
- Claude CLI backend -> Claude adapter when implemented;
- unknown runtime -> `unsupported_runtime`.

OpenClaw is not a `0.1.0-rc.1` blocker unless the loop has already completed
OMP/OpenCode/Claude coverage.

#### Claude Code

Claude Code is a strong second adapter candidate after OMP. A first version may
be limited to:

- install/doctor/pair;
- gateway identity;
- adapter-scoped auto-recording;
- explicit fidelity label as prompt or model-context handoff unless a stronger
  native session/import path is proven.

Do not block the RC on Claude TTSR parity unless the implementation discovers a
stable hook/plugin path that can enforce the same read-before-edit behavior.

## Test Suite Specification

The Ralph loop is done only when these suites are green or explicitly marked as
non-blocking external probes with clear skip reasons.

### Unit and Contract Tests

Add tests for:

- adapter state transitions;
- runtime detection result shape;
- product-to-runtime-to-adapter resolution;
- project vs user scope path resolution;
- gateway recording policy decisions;
- adapter identity validation;
- drift detection for missing, modified, and stale files;
- uninstall manifest behavior.

Required negative cases:

- generic client does not get adapter auto-recording;
- OpenCode-native does not claim Pi/OMP runtime verification;
- OpenCode with Codex runtime does not run OMP TTSR probes;
- missing gateway token fails pairing;
- wrong workspace identity is rejected;
- stale adapter version reports `drifted`.

### CLI Integration Tests

Use temp homes, temp config dirs, and fake agent binaries/configs. Tests must
not mutate the user's real agent state.

Required scenarios:

- `adapters list` returns stable JSON and human output;
- `adapters doctor` reports no adapters detected in an empty environment;
- `install omp --scope project` writes only project-local `.omp` files;
- `uninstall omp --scope project` removes only Wardwright-owned files;
- install refuses to overwrite user-edited files unless `--repair` or
  equivalent is explicit;
- `doctor` detects a modified rule file as `drifted`;
- `pair omp` writes a revocable local credential and the gateway accepts it;
- `doctor --json` contains machine-readable state, runtime, paths, and next
  actions.

### Runtime Probes

Required blocking probe:

```bash
OMP_BIN=omp node scripts/omp-ttsr-runtime-equivalence.mjs
```

The probe must use the current installed/exported Wardwright OMP rule, not a
duplicated fixture. It must assert:

- `edit` triggers `wardwright-read-before-edit`;
- `edit_file` triggers `wardwright-read-before-edit`;
- `write` triggers `wardwright-read-before-edit`;
- `read` does not trigger;
- positive cases complete through the OMP retry path, not just the
  `ttsr_triggered` event.

Required non-blocking probes when the surfaces are available:

- OpenCode through Pi/OMP runtime reaches the same runtime probe and reports
  `surface_verified`;
- OpenCode-native plugin scaffold loads and reports lower-fidelity status;
- OpenClaw Pi runtime resolves to the Pi adapter;
- OpenClaw Codex runtime resolves to Codex/gateway identity support;
- Claude Code adapter identity reaches the gateway.

Each skipped probe must print a concrete reason, for example `opencode not
installed`, `OpenCode runtime is opencode-native`, or `Claude Code hooks disabled
by managed settings`.

### Gateway Behavior Tests

Add request-level tests for:

- generic client with recording default `manual`;
- verified adapter with `adapted_agents: auto`;
- unverified adapter does not auto-record;
- adapter identity with wrong workspace is rejected;
- adapter identity with expired token is rejected;
- explicit recording still works without an adapter;
- trace metadata records adapter id, surface, runtime, and verification state.

### Browser/UI Smoke Tests

Extend the admin/control debugger smoke tests to cover:

- adapter status list renders without overflow;
- `installable`, `verified`, `verified_with_probe`, and `drifted` states are
  visually distinguishable;
- user can see why OpenCode is covered by Pi/OMP or why it is lower fidelity;
- auto-recording policy is visible and can be disabled.

### Release Candidate Validation

Before tagging `0.1.0-rc.1`, run and record:

- full app test suite;
- docs check;
- map/style/type checks;
- browser smoke;
- OMP runtime probe;
- install/doctor/probe demo from a clean temp home;
- uninstall demo proving Wardwright-owned files are removed and unrelated files
  remain untouched.

## Ralph Loop Exit Criteria

The loop should keep iterating until:

- the adapter CLI works from a packaged Wardwright build;
- OMP reaches `verified_with_probe`;
- OpenCode Pi/OMP-backed mode reuses the Pi/OMP adapter correctly;
- OpenCode-native mode is explicitly lower fidelity;
- gateway auto-recording is adapter-scoped and opt-in;
- install, doctor, pair, probe, uninstall are covered by automated tests;
- docs explain setup, privacy, cleanup, and fallback behavior for non-expert
  users;
- no adapter path can silently mutate unrelated user config or claim stronger
  replay fidelity than the tests prove.

Anything beyond that, including Claude parity or OpenClaw polish, can ship in a
follow-up release unless it is already implemented and validated during the
loop.
