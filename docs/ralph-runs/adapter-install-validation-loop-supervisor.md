---
title: Adapter Install Validation Ralph Loop Supervisor
---

# Adapter Install Validation Ralph Loop Supervisor

This file is the durable tracker for the adapter install and validation Ralph
loop. The build target is
[`adapter-install-validation-requirements.md`](adapter-install-validation-requirements.html).

## Branch Policy

- Continue on `codex/pi-replay-spike` / PR #71.
- Do not create a branch or pull request per loop.
- Prefer one coherent commit per loop, pushed to the existing PR branch.
- Keep raw logs and oversized agent artifacts out of the repo. Commit only
  small reusable docs, tests, source changes, and concise evidence.

## Cadence

- Runner: `scripts/run-adapter-ralph-loop.sh`.
- Successful iterations chain immediately into the next iteration.
- Retry delay after a failed iteration: 15 minutes by default, configurable via
  `RALPH_RETRY_DELAY_SECONDS`.
- Completion sentinel:
  `$(git rev-parse --git-path ralph-runs/adapter-install-validation/complete)`.
- The loop should stop only after the exit criteria in the requirements file
  are implemented, validated, documented, and recorded here.

## Requirements Review

The requirements are complete enough to drive implementation. The important
execution constraints for the loop are:

- Build OMP first, because it already has a runtime equivalence probe and a
  concrete project-local install surface.
- Keep OpenCode support runtime-driven: Pi/OMP-backed OpenCode may inherit the
  Pi/OMP adapter, while OpenCode-native must stay lower fidelity.
- Treat Claude Code and OpenClaw as follow-up adapter surfaces unless OMP,
  gateway policy, CLI lifecycle, and OpenCode runtime resolution are already
  green.
- Bias new pure decision logic toward Gleam, especially state classification,
  runtime resolution, install-plan selection, recording-policy decisions, and
  drift classification.
- Keep filesystem, process execution, HTTP, JSON shaping, and Phoenix surfaces
  in Elixir boundary modules.
- Every committed loop must include behavior-focused tests or a clear reason
  why the change is documentation-only.
- After every commit, perform and record an adversarial review covering
  architecture, code quality/comments, and test quality.

## Ordered Backlog

1. Add a typed adapter-domain core for states, runtime resolution, install
   plans, and recording-policy decisions.
2. Add `wardwright adapters list` and `wardwright adapters doctor` with stable
   human and JSON output.
3. Add project-scoped OMP install, drift detection, repair refusal, uninstall,
   and focused CLI tests using temp homes/configs.
4. Wire OMP pairing and gateway adapter identity validation.
5. Connect adapter-scoped auto-recording to verified adapter identity, while
   keeping generic clients manual by default.
6. Extend `probe omp` to invoke the current runtime equivalence probe from the
   packaged CLI path.
7. Add OpenCode runtime resolution and ensure Pi/OMP-backed, OpenCode-native,
   and Codex-backed modes get distinct fidelity labels.
8. Add user-facing install, privacy, cleanup, and fallback docs.
9. Run a final docs pass for completeness and accuracy, including setup,
   privacy, cleanup, fallback behavior, fidelity claims, and adapter-state
   wording.
10. Run the release-candidate validation matrix from the requirements file.

## Continuation Log

### Loop 0 - Kickoff

- Timestamp: 2026-05-23T14:58-04:00.
- Starting commit: `81e772e`.
- Scope: reviewed the adapter install validation requirements and created this
  supervisor for the 15-minute Ralph continuation.
- Validation target: future loops should update this log with their commit,
  validation commands, skipped probes, and adversarial review result.
- Current status: ready to start loop 1.

### Scheduler Correction

- Timestamp: 2026-05-23T15:15-04:00.
- Scope: corrected the runner contract after kickoff. The 15-minute value is a
  retry delay after failed iterations, not a delay between successful
  iterations.
- Validation target: next runner launch should start each new iteration
  immediately after the previous `codex exec` iteration exits successfully.
- Documentation gate: completion requires a final docs pass before writing the
  sentinel.

### Runtime Correction

- Timestamp: 2026-05-23T16:43-04:00.
- Finding: the first corrected runner launch used OpenCode machinery from the
  earlier harness-resume trial, but this is the packaged Wardwright adapter
  install loop. That made progress depend on an unrelated OpenCode provider.
- Tweak: run future iterations with `codex exec` from this worktree. The loop
  remains focused on packaging, installing, testing, and documenting Wardwright
  agent adapters.
- Follow-up: the installed `codex exec` does not accept
  `--ask-for-approval`; the runner uses the supported unattended
  `--dangerously-bypass-approvals-and-sandbox` flag instead.

### Loop 1 - Typed Adapter Decision Core

- Timestamp: 2026-05-23T16:54:20-04:00.
- Starting commit: `1f736f0`.
- Ending implementation commit: `d58a7a1`.
- Scope: added `wardwright/adapter_core.gleam` as the typed pure decision core
  for adapter install validation. The slice covers adapter state
  classification, runtime-to-adapter resolution, install-plan classification,
  and adapter-scoped recording policy decisions. Added direct behavior tests in
  `app/test/gleam_adapter_core_test.exs`.
- Validation:
  - `cd app && mise exec -- gleam format --check src`
  - `cd app && mise exec -- gleam check --target erlang`
  - `cd app && mise exec -- gleam run -m glinter`
  - `cd app && MIX_ENV=test mise exec -- mix format --check-formatted`
  - `cd app && MIX_ENV=test mise exec -- mix compile`
  - `cd app && MIX_ENV=test mise exec -- mix test --no-compile test/gleam_adapter_core_test.exs`
  - `mise run check:types`
  - Commit hook reran app format/test and gitleaks: `364 passed (21
    properties, 343 tests), 6 excluded`; staged gitleaks clean.
- Adversarial review:
  - Architecture: the pure decision logic is now in Gleam union types, while the
    exported functions still return string labels and tuples for Elixir/CLI
    boundaries. That is acceptable for this bridge slice, but the next CLI
    loop should keep JSON/human rendering in Elixir and avoid duplicating these
    state labels outside the core.
  - Architecture blocker fixed before ending: the first commit treated
    OpenClaw `claude-cli` as installable via a Claude identity path even though
    that adapter is not implemented in this loop. The amended commit now
    returns `unsupported_runtime` / `no_install` and tests the regression.
  - Code quality/comments: no comments were added because the typed variants
    and label helpers describe the decision vocabulary directly. The main
    remaining risk is positional boolean input to `adapter_state/7`; the next
    Elixir boundary should assemble those booleans from named runtime/install
    facts, not expose the positional shape to users.
  - Code quality blocker fixed before ending: the first push attempt exposed
    Dialyzer/Assay warnings from impossible generated Gleam match branches for
    unsupported install-plan labels. Unsupported resolution is now represented
    outside the install-plan union, and `mise run check:types` is clean.
  - Test quality: tests assert user-visible state labels, runtime resolution,
    scope guardrails, and recording policy isolation rather than private helper
    branches. The generic-client negative case proves adapted-agent auto
    recording cannot leak to generic clients. Integration coverage remains open
    for CLI list/doctor output and filesystem install behavior.
- Skipped probes: OMP runtime probe, OpenCode surface probe, OpenClaw runtime
  probes, and Claude gateway identity probe were skipped because this loop only
  introduced the pure core and did not wire the packaged CLI, adapter files, or
  gateway pairing surface.
- Next open item: backlog item 2, add `wardwright adapters list` and
  `wardwright adapters doctor` with stable human and JSON output backed by this
  core.

### Loop 2 - Adapter List And Doctor CLI

- Timestamp: 2026-05-23T17:11:29-04:00.
- Starting commit: `3be7712`.
- Ending implementation commit: `a96c71d`.
- Scope: added `Wardwright.CLI.Adapters` and wired
  `wardwright adapters list`, `wardwright adapters list --json`,
  `wardwright adapters doctor`, and `wardwright adapters doctor --json` into
  the packaged CLI. The CLI boundary detects candidate binaries through an
  injectable executable finder, accepts injectable runtime hints for tests and
  later config resolution, and delegates adapter state/install labels to
  `wardwright/adapter_core.gleam`. OpenCode and OpenClaw remain
  runtime-dependent and unsupported until a supported runtime is actually
  detected or supplied.
- Validation:
  - `cd app && mise exec -- mix format --check-formatted`
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/cli_adapters_test.exs test/cli_test.exs test/gleam_adapter_core_test.exs'`
  - `mise run check:maps`
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile'`
  - `mise run check:types` after rerunning without concurrent build-directory
    work.
  - Commit hook reran app format/test and staged gitleaks:
    `371 passed (21 properties, 350 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: the new CLI module is an Elixir boundary for executable
    detection, option parsing, human rendering, and JSON rendering. It keeps
    runtime/state/install decisions backed by the typed Gleam core and uses
    atom-keyed internal rows so it does not increase the Elixir map-boundary
    baseline. The main architectural limitation is intentional: real OpenCode
    and OpenClaw runtime config inspection is not implemented in this loop, so
    detected unknown runtimes report `unsupported_runtime` instead of claiming
    install support.
  - Architecture blocker fixed before ending: the first implementation used
    string-keyed maps internally and failed `mise run check:maps`. The committed
    version keeps string-keyed data at the JSON boundary and passes the ratchet.
  - Code quality/comments: the module is larger than ideal for a CLI boundary
    but still owns one concern: adapter CLI rendering/detection. No comments
    were added because target definitions, output rows, and helper names carry
    the contract directly. The next install loop should split filesystem
    manifest ownership into a separate module instead of expanding this one
    into an installer.
  - Test quality: tests use injected executable/runtime facts, so they do not
    inspect or mutate the user's real agent state. They assert stable human and
    JSON output, empty-environment `not_detected`, OMP native installability,
    OpenCode covered through OMP runtime, unsupported detected OpenCode runtime,
    and main CLI routing. The post-commit review found that `doctor --json` was
    not directly tested; the amended commit adds that machine-readable contract
    regression.
- Skipped probes: OMP runtime probe, OpenCode surface probe, OpenClaw runtime
  probes, and Claude gateway identity probe were skipped because this loop only
  added list/doctor detection output. It does not install adapter files, pair
  with the gateway, or run runtime probes.
- Next open item: backlog item 3, add project-scoped OMP install, drift
  detection, repair refusal, uninstall, and focused CLI tests using temp
  homes/configs.

### Loop 3 - Project OMP Install Lifecycle

- Timestamp: 2026-05-23T17:21:54-04:00.
- Starting commit: `8c0f8e0`.
- Ending implementation commit: `0e4cc65`.
- Scope: added the project-scoped OMP adapter file pack and installer boundary,
  wired `wardwright adapters install omp` and
  `wardwright adapters uninstall omp`, and taught doctor to report installed
  OMP files as `installed_unverified` or `drifted` based on the packaged file
  manifest. The OMP read-before-edit rule and state-fidelity extension are now
  shared between harness exports, project install, and the runtime probe source.
- Validation:
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/cli_adapters_test.exs test/cli_test.exs test/agent_harness_adapters_test.exs'`
  - `cd app && MIX_ENV=test mise exec -- mix format --check-formatted`
  - `mise run check:maps`
  - `mise exec -- node --check scripts/omp-ttsr-runtime-equivalence.mjs`
  - `mise run check:types` after rerunning without concurrent build-directory
    work.
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran app format/test and staged gitleaks:
    `376 passed (21 properties, 355 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: filesystem mutation is isolated in
    `Wardwright.AgentAdapters.OmpInstaller`, while packaged adapter content and
    hashes live in `Wardwright.AgentAdapters.OmpPack`. The CLI still owns option
    parsing and human output. This keeps impure filesystem work in Elixir and
    continues to use the Gleam adapter core for state labels. The main residual
    limitation is intentional: `install omp` writes an unpaired local config
    with a safe localhost gateway placeholder, so gateway identity, trust-link
    refresh, and token validation remain backlog item 4.
  - Code quality/comments: no comments were needed; the module names and return
    fields describe the install boundary. The CLI module grew again but did not
    absorb manifest hashing or file mutation. A future multi-adapter install
    loop should avoid adding more target-specific branches to this CLI module
    and should route through per-target installers or a small dispatcher.
  - Test quality: tests use temp workspaces and fake executable detection, so
    they do not inspect or mutate real OMP/Pi/OpenCode state. They assert
    product behavior: project-local file writes, `installed_unverified` doctor
    state before pair/probe evidence, drift detection after local edits, repair
    refusal without `--repair`, explicit repair replacement, and uninstall that
    removes only matching Wardwright-owned files while leaving edited files.
    The tests would fail for silent generic overwrites, missing manifest files,
    incorrect state classification, or unsafe uninstall behavior.
- Skipped probes: the blocking OMP runtime probe was skipped because neither
  `omp` nor `oh-my-pi` is installed in this environment. OpenCode surface
  probe, OpenClaw runtime probes, and Claude gateway identity probe remain
  skipped because this loop only installs/uninstalls the OMP project files and
  does not implement gateway pairing, probe invocation, or runtime-specific
  OpenCode/OpenClaw/Claude integration.
- Next open item: backlog item 4, wire OMP pairing and gateway adapter identity
  validation.

### Loop 4 - OMP Gateway Pairing And Identity Validation

- Timestamp: 2026-05-23T17:38:45-04:00.
- Starting commit: `4cd18d6`.
- Ending implementation commit: `b87a0bd`.
- Scope: added `wardwright adapters pair omp`, a gateway pairing request
  client, signed short-lived adapter identities, OMP config refresh during
  pairing, and gateway pair/verify endpoints. The gateway now mints only OMP
  identities for this slice and rejects malformed, expired, wrong-workspace, or
  unsupported-target identities. Doctor can report an installed OMP adapter as
  `verified` when the paired identity validates for the current workspace.
- Validation:
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/cli_adapters_test.exs test/agent_adapter_identity_test.exs test/cli_test.exs'`
  - `cd app && mise exec -- mix format --check-formatted`
  - `mise run check:maps`
  - `cd app && MIX_ENV=test mise exec -- mix test --no-compile`
  - `mise run check:types`
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran app format/test and staged gitleaks:
    `381 passed (21 properties, 360 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: signing and validation live in a focused adapter identity
    boundary, HTTP pairing stays in an impure Elixir gateway client, filesystem
    mutation remains in `OmpInstaller`, and CLI rendering stays in
    `Wardwright.CLI.Adapters`. This keeps pure adapter state classification in
    the existing Gleam core while avoiding a broader CLI installer dispatcher in
    this loop.
  - Architecture blocker fixed before commit: the first pair endpoint shape
    would have minted identities for arbitrary adapter targets. The committed
    version restricts this loop to OMP identities and tests that unsupported
    OpenCode-native pairing is rejected.
  - Code quality/comments: the JSON-shaped identity code uses named key
    constants to satisfy the Elixir map-boundary ratchet without increasing the
    baseline. No inline comments were added; function names and error codes
    carry the contract. Residual design concern: local `doctor` marks
    `verified` only when it can validate the signed identity with the configured
    signing secret. A later loop should decide whether doctor should call the
    gateway verify endpoint instead of requiring shared local secret context.
  - Test quality: tests exercise product behavior rather than private helper
    branches: missing gateway token leaves config unpaired, pairing writes an
    identity without printing the token, doctor only reports `verified` for a
    valid current-workspace identity, the gateway accepts a minted identity,
    and the gateway rejects wrong-workspace, expired, malformed, and
    unsupported-target identities. The tests would fail for silent token leaks,
    unsigned/unchecked config trust, or overbroad pair minting.
  - Post-commit review of `b87a0bd` found no additional blockers.
- Skipped probes: the blocking OMP runtime probe was skipped because neither
  `omp` nor `oh-my-pi` is installed in this environment. OpenCode surface
  probe, OpenClaw runtime probes, and Claude gateway identity probe remain
  skipped because this loop only wires OMP pairing/identity validation and does
  not implement probe invocation or runtime-specific OpenCode/OpenClaw/Claude
  integration.
- Next open item: backlog item 5, connect adapter-scoped auto-recording to
  verified adapter identity while keeping generic clients manual by default.

### Loop 5 - Adapter-Scoped Gateway Recording

- Timestamp: 2026-05-23T17:54:58-04:00.
- Starting commit: `12adb22`.
- Ending implementation commit: `3146741`.
- Scope: added the gateway request boundary for adapter identity and recording
  policy. The chat completion path now classifies generic clients, declared
  unverified adapters, and verified OMP adapter identities before receipt
  creation. Verified adapters can trigger adapter-scoped full-session recording
  through the existing Gleam recording-policy decision, while generic clients
  remain metadata-only unless they explicitly request recording. Receipts record
  sanitized adapter trace metadata without storing the signed identity token.
- Validation:
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/agent_adapter_recording_test.exs test/agent_adapter_identity_test.exs test/gleam_adapter_core_test.exs'`
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/agent_adapter_recording_test.exs test/agent_adapter_identity_test.exs'`
  - `cd app && mise exec -- mix format --check-formatted`
  - `mise run check:maps`
  - `mise run check:types`
  - `cd app && MIX_ENV=test mise exec -- mix test --no-compile`
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran app format/test and staged gitleaks:
    `386 passed (21 properties, 365 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: the new `WardwrightWeb.AdapterRequestContext` is an HTTP
    boundary for headers, signed identity parsing, request-scoped recording
    policy application, and sanitized caller metadata. Pure recording-mode
    selection still delegates to `wardwright/adapter_core.gleam`, and receipt
    construction continues to consume the existing config/VCR contract instead
    of learning adapter-specific branches.
  - Architecture blocker fixed before ending: the first committed version let a
    request header provide the workspace fingerprint used to validate that same
    identity. The amended implementation now prefers a gateway-configured
    `:adapter_workspace_fingerprint` or `WARDWRIGHT_WORKSPACE_FINGERPRINT`, and
    the test proves a wrong-workspace identity is rejected even when the request
    header matches the identity.
  - Code quality/comments: no inline comments were added; function and field
    names carry the boundary contract. The central config normalization adds a
    small recording policy map using module attributes so the map-boundary
    ratchet stays flat. Residual design concern: only OMP identity is accepted
    in this slice, and gateway URL binding is not yet enforced during request
    verification.
  - Test quality: tests assert product-visible behavior: generic clients do not
    get adapted-agent auto-recording, verified adapters do get full-session
    recording, unverified adapter declarations stay manual, wrong-workspace and
    expired identities are rejected, explicit recording still works for generic
    clients, and receipts do not contain the signed identity token. These tests
    would fail for adapter auto-recording leaking to generic clients, accepting
    wrong-workspace identities, or persisting adapter credentials in receipts.
- Skipped probes: the blocking OMP runtime probe was skipped because neither
  `omp` nor `oh-my-pi` is installed in this environment. OpenCode surface
  probe, OpenClaw runtime probes, and Claude gateway identity probe remain
  skipped because this loop only connects gateway recording policy to verified
  OMP identity and does not implement probe invocation or additional adapter
  surfaces.
- Next open item: backlog item 6, extend `probe omp` to invoke the current
  runtime equivalence probe from the packaged CLI path.

### Loop 6 - OMP Adapter Probe CLI

- Timestamp: 2026-05-23T18:06-04:00.
- Starting commit: `67d9a01`.
- Ending implementation commit: `93e0647`.
- Scope: added `wardwright adapters probe omp`, packaged the OMP TTSR runtime
  equivalence probe under `app/priv/agent_adapters`, and kept the repository
  `scripts/omp-ttsr-runtime-equivalence.mjs` path as a thin wrapper around the
  packaged probe implementation. The CLI now runs the probe against the
  project-installed OMP rule and paired adapter config, records sanitized probe
  evidence in `.omp/wardwright-adapter.json`, and lets doctor report
  `verified_with_probe` only when both the gateway identity validates and the
  runtime probe has passed.
- Validation:
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/cli_adapters_test.exs test/cli_test.exs test/agent_adapter_identity_test.exs test/gleam_adapter_core_test.exs'`
  - `cd app && MIX_ENV=test mise exec -- mix format --check-formatted`
  - `mise run check:maps`
  - `mise run check:types`
  - `mise exec -- node --check scripts/omp-ttsr-runtime-equivalence.mjs`
  - `mise exec -- node --check app/priv/agent_adapters/omp-ttsr-runtime-equivalence.mjs`
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran app format/test and staged gitleaks:
    `388 passed (21 properties, 367 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: filesystem/config mutation and subprocess execution stay in
    `Wardwright.AgentAdapters.OmpInstaller`; the CLI boundary only parses
    options, detects the OMP binary, and renders outcomes. Probe evidence is a
    sanitized status/digest record, not raw output or adapter credentials. The
    state classification still goes through the Gleam adapter core, so probe
    success cannot override drifted files or an unverified identity.
  - Architecture concern reviewed: the CLI module continues to grow, but this
    slice did not put process execution or manifest hashing into it. Future
    non-OMP probes should move through per-target adapter modules rather than
    adding target-specific probe branches directly to the CLI module.
  - Code quality/comments: the root script is now a wrapper so there is one
    runtime-probe implementation to maintain. No comments were added; function
    names and evidence keys carry the contract. Probe failures currently print
    the synthetic probe subprocess output; that is acceptable for this probe
    because it uses Wardwright-controlled fixture prompts, but future probes
    that can surface real agent content must redact or hash output before
    printing.
  - Test quality: tests assert product behavior with temp workspaces and an
    injected process runner: probe refuses unpaired installs, uses the installed
    rule and paired config path, does not print or store the gateway token in
    probe evidence, and only reaches `verified_with_probe` when doctor can
    validate the identity. These tests would fail for source-only rule probing,
    token leakage, skipping pairing, or marking probe verification without
    identity verification.
  - Post-commit review of `93e0647` found no blockers.
- Skipped probes: the real OMP TTSR subprocess probe was skipped because
  neither `omp` nor `oh-my-pi` is installed in this environment. OpenCode
  surface probe, OpenClaw runtime probes, and Claude gateway identity probe
  remain skipped because this loop only wires the OMP packaged CLI probe path.
- Next open item: backlog item 7, add OpenCode runtime resolution and ensure
  Pi/OMP-backed, OpenCode-native, and Codex-backed modes get distinct fidelity
  labels.

### Loop 7 - OpenCode Runtime Resolution

- Timestamp: 2026-05-23T18:16:36-04:00.
- Starting commit: `c6a0702`.
- Ending implementation commit: `d75023b`.
- Scope: added a focused OpenCode runtime detection boundary,
  `Wardwright.AgentAdapters.OpenCodeRuntime`, that reads the normalized
  project-local `.opencode/wardwright-runtime.json` marker and resolves
  Pi/OMP bridge runtimes, OpenCode-native, Codex-backed, and unsupported
  runtime ids. `wardwright adapters doctor` now reports OpenCode coverage,
  fidelity, install strategy, and next actions from that runtime resolution:
  Pi/OMP-backed OpenCode is covered through the runtime adapter,
  OpenCode-native stays `session_import_best_effort`, and Codex-backed
  OpenCode stays gateway-identity/prompt-handoff without OMP probe claims.
- Validation:
  - `cd app && mise exec -- gleam format --check src`
  - `cd app && mise exec -- gleam check --target erlang`
  - `cd app && mise exec -- gleam run -m glinter`
  - `cd app && MIX_ENV=test mise exec -- mix format --check-formatted`
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/cli_adapters_test.exs test/gleam_adapter_core_test.exs'`
  - `mise run check:maps`
  - `mise run check:types`
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran app format/test and staged gitleaks:
    `391 passed (21 properties, 370 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: runtime config parsing is isolated in an adapter boundary
    module, while CLI doctor still owns executable detection, row rendering,
    and next-action wording. Pure product-to-runtime-to-adapter decisions
    continue to come from the typed Gleam adapter core. The deliberate
    limitation is that this loop reads Wardwright's normalized project marker
    or injected runtime hints; it does not yet inspect every upstream OpenCode
    provider/config format.
  - Architecture concern reviewed: the CLI module gained OpenCode-specific
    next-action clauses. This is acceptable for one doctor slice, but future
    install/probe work should not keep growing the CLI module with per-target
    lifecycle behavior; that should move behind per-target adapter modules.
  - Code quality/comments: no comments were added. The new parser uses named
    key constants and atom-keyed return data, so `mise run check:maps` stays
    clean without expanding the string-map baseline. Unsupported runtime ids
    are preserved as unsupported labels instead of being collapsed into
    `unknown`.
  - Test quality: tests use temp workspaces and fake executable detection, so
    they do not inspect or mutate the user's real OpenCode state. They assert
    product-visible doctor behavior for OMP hints, Pi bridge config,
    OpenCode-native lower fidelity, and Codex-backed gateway identity. The
    negative coverage would fail if OpenCode-native claimed Pi/OMP runtime
    verification or if Codex-backed OpenCode directed users to the OMP probe.
  - Post-commit review of `d75023b` found no blockers.
- Skipped probes: the real OMP TTSR subprocess probe remains skipped because
  neither `omp` nor `oh-my-pi` is installed in this environment. OpenCode
  surface verification is skipped because this loop resolves the runtime and
  labels the fidelity but does not invoke OpenCode through the resolved
  runtime. OpenClaw runtime probes and Claude gateway identity probe remain
  skipped because this loop only covers OpenCode doctor resolution.
- Next open item: backlog item 8, add user-facing install, privacy, cleanup,
  and fallback docs.

### Loop 8 - User-Facing Adapter Lifecycle Docs

- Timestamp: 2026-05-23T18:23:13-04:00.
- Starting commit: `da024b4`.
- Ending implementation commit: `363fa1c`.
- Scope: added `docs/agent-adapters.md` as the user-facing adapter lifecycle
  guide and linked it from the public docs index, site nav, and README. The
  guide covers adapter commands, project-scope behavior, adapter states, OMP
  install/pair/probe/uninstall, repair refusal, privacy and recording
  boundaries, generic fallback behavior, cleanup, and fidelity limits for OMP,
  Pi, OpenCode, OpenClaw, and Claude Code.
- Validation:
  - `mise run check:docs`
  - `git diff --check`
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran docs-site checks and staged gitleaks; both passed.
- Adversarial review:
  - Architecture: this is intentionally documentation-only. The new page
    reflects the current boundary split instead of adding product logic: OMP is
    the only packaged install/pair/probe lifecycle, OpenCode is currently
    runtime-resolution and fidelity labeling, and missing or unsupported
    adapters fall back to generic gateway/export behavior.
  - Architecture concern reviewed: the page is linked from the public site even
    though the published `v0.0.10` release may not include every adapter
    command. The page now opens with release-candidate status wording so it does
    not overstate published package capability.
  - Code/comment quality: no code comments were touched. Post-commit review
    found one security wording blocker: the first OMP pairing example showed
    `WARDWRIGHT_ADMIN_TOKEN` inline with the command. The amended commit removes
    that pattern and tells users to set the token in the shell or service
    environment instead of passing tokens as command arguments.
  - Test quality: no behavior tests were added because this slice changes only
    docs and navigation. The relevant failing check is `mise run check:docs`,
    which would fail for missing front matter, broken local docs links, or
    source-Markdown links inside the docs site.
- Skipped probes: OMP runtime probe, OpenCode surface probe, OpenClaw runtime
  probes, and Claude gateway identity probe were skipped because this loop only
  documents the lifecycle and does not change adapter runtime behavior.
- Next open item: backlog item 9, run a final docs pass for completeness and
  accuracy, including setup, privacy, cleanup, fallback behavior, fidelity
  claims, and adapter-state wording.

### Loop 9 - Adapter Docs Accuracy Pass

- Timestamp: 2026-05-23T18:27:40-04:00.
- Starting commit: `93ae9ac`.
- Ending implementation commit: `eda8596`.
- Scope: tightened the user-facing adapter guide around the actual packaged
  CLI and gateway behavior. The docs now call out the required project
  workspace context, `doctor` versus `list`, `doctor --json` machine-readable
  fields, gateway signing-secret setup for pairing, admin-token handling
  without argv exposure, workspace-bound verification, and the requirement that
  a real `omp` or `oh-my-pi` binary be available before the OMP probe can pass.
- Validation:
  - `mise run check:docs`
  - `git diff --check`
  - Commit hook reran docs-site checks and staged gitleaks; both passed.
- Adversarial review:
  - Architecture: this is documentation-only and does not alter adapter
    runtime behavior. The added setup text matches the current boundary split:
    CLI/docs handle operator guidance, the gateway mints signed identities,
    and runtime probe success remains evidence rather than product truth by
    assertion.
  - Code/comment quality: no code comments were changed. The new wording is
    intentionally operator-facing and avoids private endpoints, real
    deployment identifiers, or example credentials.
  - Test quality: no behavior tests were added because this loop only changes
    docs. The relevant checks are the docs-site checker, whitespace diff check,
    pre-commit docs gate, and staged gitleaks. Post-commit review found no
    blocker or overclaim: Pi/OpenCode/OpenClaw/Claude remain explicitly
    fidelity-limited where they are not packaged install/probe surfaces.
- Skipped probes: OMP runtime probe, OpenCode surface probe, OpenClaw runtime
  probes, Claude gateway identity probe, browser smoke, and packaged
  clean-temp-home demos were skipped because this loop was the final docs
  accuracy pass and did not change runtime behavior. Completion sentinel was
  not written because the release-candidate validation matrix remains open.
- Next open item: backlog item 10, run the release-candidate validation matrix
  from the requirements file.

### Loop 10 - Release-Candidate Validation Matrix

- Timestamp: 2026-05-23T18:35:41-04:00.
- Starting commit: `2ecc605`.
- Ending implementation commit: `2ecc605` (validation-only loop; no product
  code or docs content changed before this supervisor record).
- Scope: ran the release-candidate validation matrix that was still open after
  the docs pass. This loop validated the baseline checks, packaged Burrito
  binary smoke, packaged adapter CLI lifecycle from a clean temp home, live
  local adapter detection status, and staged secret scan. The completion
  sentinel was not written because the real OMP runtime probe cannot run on
  this machine without `omp` or `oh-my-pi`, and live OpenCode/OpenClaw/Claude
  surfaces still do not have packaged surface probes or installable adapter
  support beyond the documented fallback states.
- Validation:
  - `mise run check`: passed. App tests reported `391 passed (21 properties,
    370 tests), 6 excluded`; docs, map, style, type, and browser smoke checks
    also passed.
  - `mise run package:smoke:darwin-arm64`: passed; built
    `app/burrito_out/wardwright_darwin_arm64` and the smoke script reported
    `Burrito smoke passed for app/burrito_out/wardwright_darwin_arm64`.
  - Packaged clean-temp adapter lifecycle demo: passed with isolated `HOME`,
    XDG directories, temp workspace, temp gateway service, and fake `omp`
    binary. The packaged CLI reached `installable`, `installed_unverified`,
    `verified`, and `verified_with_probe`; pair/probe output and adapter config
    did not contain the generated admin token or adapter signing secret;
    uninstall removed Wardwright-owned files while preserving an unrelated
    `.omp/local-note.txt`.
  - Real OMP runtime probe check:
    `if command -v omp ...; else echo 'skip OMP runtime probe: neither omp nor oh-my-pi is installed'; fi`.
    Result: skipped because neither `omp` nor `oh-my-pi` is installed.
  - Live packaged `adapters doctor --json`: OMP and Pi reported
    `not_detected`; OpenCode and OpenClaw binaries were detected but reported
    `unsupported_runtime` with runtime `unknown`; Claude Code was detected as
    `claude-cli` but reported `unsupported_runtime`.
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`: passed with
    no leaks found.
- Adversarial review:
  - Architecture: this loop does not change architecture. The validation
    evidence supports the current boundary split: pure decisions remain behind
    the Gleam core, filesystem/process behavior stays in Elixir adapter
    boundaries, and the packaged binary can run the OMP lifecycle when an OMP
    runtime path is available. The completion blocker is environmental/product
    coverage, not a new architecture defect: real OMP runtime equivalence still
    must be observed before claiming the loop complete.
  - Code quality/comments: no code comments or implementation files changed.
    The temp lifecycle demo intentionally used an isolated fake `omp` binary
    only to validate packaging, CLI wiring, pairing, probe evidence recording,
    and cleanup behavior; it is not recorded as real OMP TTSR fidelity.
  - Test quality: automated tests and the packaged demo cover behavior visible
    to users and operators, including secret non-disclosure and cleanup
    boundaries. The fake-runtime demo is capable of failing the packaged CLI
    path but cannot replace the required real OMP probe. Browser smoke passed
    for the existing workbench routes, but adapter-status-specific UI smoke
    remains limited to the current non-adapter workbench coverage unless a
    future loop adds an adapter status page or fixture route.
  - Completion review: exit criteria are not fully complete because OMP has
    not reached real `verified_with_probe` in this environment, OpenCode
    surface verification remains unimplemented/skipped, and OpenClaw/Claude
    remain documented follow-up surfaces. No completion sentinel was created.
- Skipped probes: real OMP TTSR runtime equivalence probe skipped because
  neither `omp` nor `oh-my-pi` is installed; OpenCode surface probe skipped
  because the live runtime resolved as `unknown` and no packaged surface probe
  exists yet; OpenClaw runtime probes skipped because the live runtime resolved
  as `unknown` and support is follow-up; Claude gateway identity probe skipped
  because Claude Code adapter pairing is not packaged.
- Next open item: run the real OMP runtime equivalence probe in an environment
  with `omp` or `oh-my-pi`, then decide whether to add adapter-status-specific
  UI smoke or explicitly mark that browser requirement non-blocking for this RC
  before writing the completion sentinel.

### Loop 11 - Adapter Status Browser Smoke

- Timestamp: 2026-05-23T18:46:10-04:00.
- Starting commit: `1f5919c`.
- Ending implementation commit: `acd04f4`.
- Scope: added a read-only adapter install status panel to the control debugger
  admin surface, backed by live `wardwright adapters doctor` rows at runtime
  and an explicit browser-smoke fixture flag for deterministic UI coverage.
  Extended browser smoke to assert that `installable`, `verified`,
  `verified_with_probe`, and `drifted` states render with distinct visual
  treatment, that OpenCode through OMP and OpenCode-native lower-fidelity
  wording are visible, that adapter-scoped recording policy is visible, and
  that the control debugger page still has no responsive overflow.
- Validation:
  - `cd app && mise exec -- gleam format --check src`
  - `cd app && MIX_ENV=test mise exec -- mix format --check-formatted`
  - `cd app && mise exec -- gleam check --target erlang`
  - `cd app && mise exec -- gleam run -m glinter`
  - `python3 /Users/admin/.codex/skills/gleam-lustre/scripts/check_lustre_controlled_inputs.py /Users/admin/projects/wardwright.pi-replay-spike/app/src`
  - `cd app && MIX_ENV=test mise exec -- sh -lc 'mix compile && mix test --no-compile test/workbench_test.exs'`
  - `mise run check:maps`
  - `node --check scripts/browser-smoke/lustre-workbench.mjs`
  - `git diff --check`
  - `mise run check:browser`
  - `mise run check:types` after rerunning without the browser-smoke build
    directory contention from the first parallel attempt.
  - `gitleaks protect --staged --config .gitleaks.toml --verbose`
  - Commit hook reran app format/test and staged gitleaks:
    `392 passed (21 properties, 371 tests), 6 excluded`; staged gitleaks
    clean.
- Adversarial review:
  - Architecture: the panel is a read-only projection. Filesystem/process
    detection remains in the existing Elixir CLI doctor boundary, while the
    Lustre code only renders rows and does not mutate adapter state. The browser
    fixture is gated by `WARDWRIGHT_BROWSER_ADAPTER_STATUS_FIXTURE=1` and is
    used only by the smoke server process, so normal admin rendering reports
    live doctor rows instead of canned adapter states.
  - Architecture concern reviewed: the web panel reports the gateway process
    workspace/cwd that `Adapters.doctor/1` sees. That is acceptable for this
    smoke slice because it is read-only and does not claim a separate selected
    workspace, but a later install-management UI should make the workspace root
    explicit before allowing any install, repair, pair, probe, or uninstall
    action from the browser.
  - Code quality/comments: no comments were added. The new CSS uses stable
    state classes for the product-visible state vocabulary and keeps text
    wrapping/one-column fallback explicit to avoid the overflow regressions this
    smoke covers. The Gleam external shape is still an eight-field tuple; that
    is tolerable for a small display boundary, but a future editable adapter UI
    should use a named Gleam record type rather than expanding positional
    fields.
  - Test quality: the ExUnit regression asserts the user-visible recording
    policy text on the control debugger. Browser smoke exercises the actual
    rendered server component, including shadow-DOM traversal, distinct state
    styling, OpenCode runtime/fidelity explanations, recording-policy wording,
    and responsive overflow checks. The test would fail for missing status rows,
    indistinguishable state styling, lower-fidelity OpenCode overclaims, or
    layout overflow. It intentionally does not substitute for the real OMP TTSR
    runtime probe.
- Skipped probes: real OMP TTSR runtime equivalence probe remains skipped
  because neither `omp` nor `oh-my-pi` is installed. OpenCode surface probe,
  OpenClaw runtime probes, and Claude gateway identity probe remain skipped
  because this loop only adds adapter-status UI/smoke coverage and does not add
  new runtime probe or adapter pairing surfaces.
- Next open item: run the real OMP runtime equivalence probe in an environment
  with `omp` or `oh-my-pi`; completion sentinel remains blocked until that
  blocking probe is observed or the requirements are explicitly changed.

### Loop 12 - OMP Runtime Probe Blocker Check

- Timestamp: 2026-05-23T18:50:59-04:00.
- Starting commit: `5b7ebb3`.
- Ending implementation commit: `5b7ebb3` (blocker-check loop; no product code
  or docs content changed before this supervisor record).
- Scope: attempted the highest-priority open item from loop 11: run the real
  OMP TTSR runtime equivalence probe in this environment. The probe could not
  make progress because no `omp`, `oh-my-pi`, or `pi` binary is installed on
  `PATH`; only OpenCode, OpenClaw, and Claude Code were detected.
- Validation:
  - `command -v omp || true; command -v oh-my-pi || true; command -v pi || true;
    command -v opencode || true; command -v openclaw || true; command -v claude
    || true`: detected `/opt/homebrew/bin/opencode`,
    `/opt/homebrew/bin/openclaw`, and `/Users/admin/.local/bin/claude`; OMP/Pi
    runtimes were absent.
  - `OMP_BIN=omp node scripts/omp-ttsr-runtime-equivalence.mjs`: failed before
    runtime behavior could be observed. All four cases (`edit`, `edit_file`,
    `write`, and `read`) reported `Failed to start OMP binary "omp": spawn omp
    ENOENT`.
  - `git rev-parse --git-path
    ralph-runs/adapter-install-validation/complete`: sentinel path resolved,
    and the sentinel remains absent.
- Adversarial review:
  - Architecture: no architecture changed. This result confirms the remaining
    completion blocker is external runtime availability, not a reason to weaken
    the probe contract or substitute fake-runtime evidence for OMP TTSR
    fidelity.
  - Code quality/comments: no code or comments changed. The probe failure is
    clear enough for operator action: install a real `omp` or `oh-my-pi`
    runtime, or revise the requirements if the release should no longer block
    on real OMP verification.
  - Test quality: the probe did not reach behavioral assertions because process
    startup failed. The existing fake-runtime packaged demo remains useful for
    CLI wiring, pairing, sanitized evidence, and cleanup, but it still cannot
    prove OMP TTSR behavior.
- Skipped probes: OpenCode surface probe, OpenClaw runtime probes, and Claude
  gateway identity probe remain skipped because the loop stopped at the
  blocking OMP runtime requirement and did not add new runtime probe or adapter
  pairing surfaces.
- Next open item: provide a real `omp` or `oh-my-pi` runtime on `PATH` and
  rerun `OMP_BIN=omp node scripts/omp-ttsr-runtime-equivalence.mjs`, then rerun
  the packaged `wardwright adapters probe omp` lifecycle before considering the
  completion sentinel.

### Loop 13 - OMP Runtime Probe Blocker Recheck

- Timestamp: 2026-05-23T18:54:44-04:00.
- Starting commit: `c664f0f`.
- Ending implementation commit: `c664f0f` (blocker-recheck loop; no product
  code or docs content changed before this supervisor record).
- Scope: rechecked the highest-priority open item from loop 12: run the real
  OMP TTSR runtime equivalence probe in this environment. The loop still cannot
  make product progress because no `omp`, `oh-my-pi`, or `pi` binary is
  installed on `PATH`; only OpenCode, OpenClaw, and Claude Code were detected.
- Validation:
  - `git status --short --branch`: branch remained
    `codex/pi-replay-spike...origin/codex/pi-replay-spike` with no worktree
    changes before this supervisor update.
  - `command -v omp || true; command -v oh-my-pi || true; command -v pi || true;
    command -v opencode || true; command -v openclaw || true; command -v claude
    || true`: detected `/opt/homebrew/bin/opencode`,
    `/opt/homebrew/bin/openclaw`, and `/Users/admin/.local/bin/claude`; OMP/Pi
    runtimes were absent.
  - `OMP_BIN=omp node scripts/omp-ttsr-runtime-equivalence.mjs`: failed before
    runtime behavior could be observed. All four cases (`edit`, `edit_file`,
    `write`, and `read`) reported `Failed to start OMP binary "omp": spawn omp
    ENOENT`.
  - `git rev-parse --git-path
    ralph-runs/adapter-install-validation/complete`: sentinel path resolved,
    and the sentinel remains absent.
- Adversarial review:
  - Architecture: no runtime architecture changed. Repeating the failed real
    probe confirms the loop remains blocked on external OMP/Pi runtime
    availability, not on an internal Wardwright adapter boundary.
  - Code quality/comments: no source code or code comments changed. This
    supervisor update deliberately avoids replacing the real OMP probe with
    fake-runtime evidence or stronger fidelity wording.
  - Test quality: the probe is still capable of failing and did fail before
    reaching behavioral assertions because process startup failed. Existing
    automated and fake-runtime packaged checks remain useful for CLI and
    cleanup behavior, but they still do not prove real OMP TTSR fidelity.
- Skipped probes: OpenCode surface probe, OpenClaw runtime probes, and Claude
  gateway identity probe remain skipped because the loop stopped at the
  blocking real OMP runtime requirement and did not add new runtime probe or
  adapter pairing surfaces.
- Next open item: install or provide a real `omp` or `oh-my-pi` runtime on
  `PATH`, rerun `OMP_BIN=omp node scripts/omp-ttsr-runtime-equivalence.mjs`,
  then rerun the packaged `wardwright adapters probe omp` lifecycle before
  considering the completion sentinel.
