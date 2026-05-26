---
title: Freeform Admin UX Concepts
date: 2026-05-25
status: exploratory
---

# Freeform Admin UX Concepts

Scope: alternate UX directions for the Wardwright admin model configuration
surface. This pass intentionally treats the current UI as functional
requirements only, not as the visual or layout baseline.

Artifacts:

- [`freeform-admin-concepts.html`](../assets/design-review-2026-05-25/freeform-admin-concepts.html)
- [`freeform-admin-concepts.png`](../assets/design-review-2026-05-25/freeform-admin-concepts.png)

The earlier
[`model-config-wireframes.html`](../assets/design-review-2026-05-25/model-config-wireframes.html)
artifact is a near-term refactor sketch. This artifact is deliberately more
divergent.

External guidance used:

- [Nielsen Norman Group usability heuristics](https://media.nngroup.com/media/articles/attachments/Heuristic_Summary1_A4_compressed.pdf):
  emphasize visibility of system status, recognition over recall, error
  prevention, and a minimalist surface.
- [UXPin progressive disclosure guide](https://www.uxpin.com/studio/blog/what-is-progressive-disclosure/):
  expose only the next useful layer of complexity.
- [USWDS table guidance](https://designsystem.digital.gov/components/table/):
  use tables when comparison is the task, not as the default shape for every
  dense configuration object.
- [USWDS form guidance](https://designsystem.digital.gov/components/form/):
  keep form structure direct and avoid hiding meaning inside placeholder or
  disabled states.
- [Baymard inline validation research](https://baymard.com/blog/inline-form-validation):
  prevent late-stage surprises, but avoid premature validation noise.

## Concept 1: Capability Command Center

This concept makes Wardwright feel like an operations console. The page starts
with the model contract and the current capability risk:

- stable model tools: `0`
- conditional tools: `2`
- tool-capable targets: `1 / 2`
- replay capture: `Metadata`

The primary call to action is not `Save settings`; it is `Fix advertisement`.
This better matches the real operator question: what can agents safely believe
this model can do?

Strengths:

- Strongest for release-readiness and status visibility.
- Keeps the model contract above implementation detail.
- Gives a concrete next action when target support differs.

Risks:

- Less efficient for expert bulk editing.
- Needs a secondary detail mode for raw artifact inspection.

## Concept 2: Route Topology Map

This concept represents composed model behavior as a graph. Raw targets,
dispatchers, server tools, recording, and keys become inspectable nodes. The
operator can see that `server tools` are connected to only one compatible raw
target.

Strengths:

- Best fit for Wardwright's core product idea: route graphs, policy,
  provenance, and receipts.
- Makes target mismatch visible without reading a settings table.
- Scales naturally to composed models and future route-aware tool policies.

Risks:

- Higher implementation cost.
- Needs strong keyboard and screen-reader alternatives to the visual graph.

## Concept 3: Guided Change Review

This concept treats model configuration as a review workflow, not a settings
screen. The operator moves through:

1. What can agents do?
2. Who can call it?
3. What gets recorded?
4. Prove it works.
5. Apply change.

For the tool advertisement policy, the UI compares `Advertise intersection`,
`Conditional union`, and `Blind union` as choices with consequences.

Strengths:

- Best for risky configuration changes and first-time users.
- Encourages validation before save.
- Maps well to AI-assisted operator workflows.

Risks:

- Slower than a direct settings page for routine edits.
- Needs a fast path for expert users.

## Recommendation

For a polished public `0.0.11` admin experience, use Concept 1 as the immediate
direction and borrow the graph inspector from Concept 2 as the richer future
state. Concept 3 should influence any save flow that can materially change what
agents are allowed to do.

The current UI can still ship as a technical admin surface, but these concepts
show a stronger product direction than the incremental wireframe: Wardwright
should lead with capability state, target mismatch, and validation evidence
rather than starting from generic settings sections.
