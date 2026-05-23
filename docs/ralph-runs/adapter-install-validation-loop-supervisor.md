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
