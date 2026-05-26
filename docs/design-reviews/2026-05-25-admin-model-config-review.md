---
title: Admin Model Config UX Review
date: 2026-05-25
status: draft
---

# Admin Model Config UX Review

Scope: latest `release/docs-and-version-prep` admin UI, focused on the Models &
access page after server-tool configuration and advertisement controls were
added.

Artifacts:

- Current-state screenshots were captured locally during review and used for
  findings; the committed durable artifact is the mockup below.
- Balsamiq-style concept mockups:
  [`model-config-wireframes.html`](../assets/design-review-2026-05-25/model-config-wireframes.html)
  and
  [`model-config-wireframes.png`](../assets/design-review-2026-05-25/model-config-wireframes.png).

External guidance used:

- [UXPin progressive disclosure guide](https://www.uxpin.com/studio/blog/what-is-progressive-disclosure/):
  show only essential current-task information first, then reveal advanced
  details on demand.
- [USWDS form guidance](https://designsystem.digital.gov/components/form/):
  keep complex form groups in simple vertical order, use helper text instead of
  unclear disabled states, and make validation/action feedback contextual.
- [USWDS alert guidance](https://designsystem.digital.gov/components/alert/):
  give the next step in human language and avoid excessive notifications.
- [USWDS table guidance](https://designsystem.digital.gov/components/table/):
  tables help compare structured data, but dense tables should be used only
  when row/column comparison is the main task.
- [Baymard inline validation research](https://baymard.com/blog/inline-form-validation):
  inline validation helps users recover sooner, but premature validation
  creates avoidable friction.

## Findings

### 1. Release-scope UX risk: model config now has too many primary tasks on one page

The current page combines access policy, debug recording, server-tool
advertisement, provider support, lifecycle controls, key creation, key listing,
and archive management in one continuous surface. Desktop is workable, but the
mobile page becomes a long inspection stack of roughly five viewports before the
operator finishes the server-tool area.

Recommendation: keep the top of the page decision-oriented: selected model,
stable advertised capability, and clear risk summary. Move access, recording,
keys, and lifecycle into tabs or accordions below the primary model contract
summary.

### 2. Server-tool advertisement is technically accurate but not yet cognitively simple

The current summary exposes `Advertise intersection`, `Guaranteed tools 0`, and
`Conditional tools 2`, which is the right conservative product claim. The
problem is that the page asks the operator to synthesize this from six metric
tiles plus a dense routing note and a table.

Recommendation: make the top-level state read like an operating decision:
`Conditional: 2 server tools`, followed by one sentence: `Advertise intersection
unless routing can force a compatible target.` Keep the exact counts and target
details visible, but subordinate them to that decision.

### 3. Mobile controls pass overflow checks but some inputs collapse visually

The captured mobile page has no horizontal overflow, but several radio inputs
render as tiny visible controls beside large option cards. The surrounding cards
are tappable-looking, but the actual visible control affordance is too small and
visually noisy.

Recommendation: use segmented-card controls where the entire card is the target,
and visually suppress the tiny native radio except for an accessible checked
state. Confirm keyboard and screen-reader behavior after any styling change.

### 4. Server tools need a task-card mobile layout, not a table-transformed layout

The current mobile stacked table is readable and is a strong improvement over
the prior collapsed columns. It still reads like a table translated into cards:
Tool, Engine, State, Source, Dune limits, Schema, Action. On mobile, the
operator likely needs status, availability, and the one action first.

Recommendation: use mobile task cards:

- tool name
- status dot and engine
- guaranteed/conditional/not advertised availability
- primary enable/disable action
- expandable details for source, schema, and limits

### 5. Session replay is serviceable but less focused than Models & access

The session replay page has clear capabilities, but its first screen presents
scenario creation, replay summary, what-if replay, adapter export, adapter
status, and trace inspector in one vertical story. This is not a release blocker
for the server-tool release, but it is another candidate for a tabbed
task-first pass.

Recommendation: split session replay into three primary tasks: `Inspect`,
`Fork/replay`, and `Export/handoff`.

## Mockup Direction

The included wireframe proposes:

1. A selected-model summary that keeps operational state above configuration
   mechanics.
2. An `Advertised capability` panel that names conditional availability before
   showing details.
3. A tab strip for Server tools, Access, Recording, Keys, and Lifecycle.
4. A mobile version that turns server tools into task cards and moves lower
   priority sections into a `Later` area.

## Release Recommendation

The current UI is not broken and the latest smoke coverage is meaningful. For
`0.0.11`, this is acceptable if the release goal is a technical RC-quality admin
surface. If the release goal is a polished first public admin experience, the
Models & access page should get the information-architecture pass shown in the
mockup before tagging.
