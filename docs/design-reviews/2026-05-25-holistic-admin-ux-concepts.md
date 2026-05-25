---
title: Holistic Admin UX Concepts
date: 2026-05-25
status: exploratory
---

# Holistic Admin UX Concepts

Scope: a whole-product rethink of the Wardwright admin and workbench
experience. This pass treats the current admin UI as a list of required jobs,
not as the information architecture or visual baseline.

Artifacts:

- [`holistic-admin-ux-concepts.html`](../assets/design-review-2026-05-25/holistic-admin-ux-concepts.html)
- [`holistic-admin-ux-concepts.png`](../assets/design-review-2026-05-25/holistic-admin-ux-concepts.png)

This supersedes the scope of the earlier
[`freeform-admin-concepts.html`](../assets/design-review-2026-05-25/freeform-admin-concepts.html)
artifact. That pass is useful as a model/tool-advertising study, but it is too
narrow to guide the whole Wardwright admin product.

External guidance used:

- [Nielsen Norman Group usability heuristics](https://media.nngroup.com/media/articles/attachments/Heuristic_Summary1_A4_compressed.pdf):
  keep system status, user control, recognition over recall, and error
  prevention visible.
- [UXPin progressive disclosure guide](https://www.uxpin.com/studio/blog/what-is-progressive-disclosure/):
  lead with the next decision and reveal deep mechanics only when they support
  that decision.
- [USWDS table guidance](https://designsystem.digital.gov/components/table/):
  reserve tables for comparison tasks and do not use them as the default shape
  for dense configuration.
- [USWDS form guidance](https://designsystem.digital.gov/components/form/):
  structure forms by real user tasks, with clear labels and contextual
  validation.
- [Baymard inline validation research](https://baymard.com/blog/inline-form-validation):
  show validation close to the changed control and avoid late surprise errors.

## Product Jobs

Wardwright's admin surface should make these jobs feel connected:

1. Understand whether the gateway is safe to use right now.
2. See what each stable model contract promises agents and applications.
3. Design routes and policy as a graph with typed evidence, not as scattered
   settings.
4. Validate a change before publishing it.
5. Inspect receipts, replay sessions, and export handoffs without losing
   fidelity limits.
6. Install and verify framework SDK recipes and local coding-agent adapters as
   separate integration surfaces.
7. Prepare a release from evidence rather than from manual confidence.

The current UI has working pieces for several of these jobs, but they are
distributed across `Model lab`, `Models & access`, and `Session replay` in a
way that makes the operator assemble the product story manually.

## Concept: Wardwright Control Room

The mockup proposes a cohesive operator shell with five durable work areas:

- **Overview**: release readiness, live health, recent risky changes, and the
  next useful action.
- **Models**: stable contract, route graph, capability catalog, access policy,
  and recording policy for one Wardwright model.
- **Policy Lab**: author, simulate, and compare policy behavior against saved
  scenarios before activating.
- **Evidence**: receipts, replay sessions, counterfactual runs, package smoke,
  and release checklists in one evidence ledger.
- **Integrations**: framework SDK recipes, local coding-agent adapters, install
  status, adapter identity, and fidelity limits.

The design intentionally makes the stable Wardwright model the center of the
experience. Provider targets, tools, routes, policies, receipts, and adapters
are shown as supporting surfaces around that contract.

## Key Changes From The Current UI

### 1. Replace feature-page navigation with operator workflow navigation

`Model lab`, `Models & access`, and `Session replay` are implementation-shaped
labels. A new shell should use task-shaped areas:

- Overview
- Models
- Policy Lab
- Evidence
- Integrations
- Release

This also gives server tools a natural home under model capability, not a
special-purpose top-level concept.

### 2. Make validation a first-class object

The current admin has simulation, replay, browser smoke, adapter smoke, package
smoke, and docs checks as separate mental objects. The holistic direction
creates an evidence ledger that can answer:

- what changed?
- what tests or smokes prove it?
- what adapters/frameworks were exercised?
- what fidelity limits remain?
- what release claim is still unsupported?

### 3. Keep local coding-agent adapters separate from framework SDK recipes

The Integrations area deliberately separates:

- framework SDK recipes: OpenAI Agents SDK, LangChain/LangGraph, LlamaIndex,
  Pydantic AI, Vercel AI SDK, Microsoft Extensions AI
- local coding-agent adapters: Claude Code, Codex, OpenCode, OpenClaw, Pi,
  oh-my-pi / OMP

This preserves the product distinction already required by the adapter
validation work.

### 4. Put route, policy, and receipt evidence on one model canvas

For a selected model, the operator should see:

- stable public model name
- route graph and selected raw targets
- target capability differences
- policy/governor stack
- access and caller provenance rules
- recording mode and receipt availability
- validation evidence linked directly to the model

This reduces the current page hopping between configuration, simulation, and
replay.

### 5. Treat release readiness as an evidence rollup

The Release area should not be a marketing page. It should be a compact,
operator-facing rollup of docs, package smoke, adapter install smoke, browser
smoke, mutation/property tests, known limits, and open claims.

## Recommendation

Use this holistic direction, not the prior tool-advertising concept, as the
north star for the public admin UX. For `0.1.0`, the current implemented UI can
still ship if the release is positioned as a technical first release. If the
release should present a polished product surface, implement the shell and
overview/evidence ledger first, then migrate model capability and replay into
that structure.
