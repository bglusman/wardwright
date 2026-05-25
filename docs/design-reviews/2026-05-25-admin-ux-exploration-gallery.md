---
title: Admin UX Exploration Gallery
date: 2026-05-25
status: exploratory
---

# Admin UX Exploration Gallery

This page collects the Wardwright admin UX concepts into one tryable
exploration surface. The current app implementation mounts the same protected
Lustre server-component runtime used by `/admin`, so reviewers can compare
alternative layouts against live Wardwright model data and controls instead of
opening static screenshots.

App routes:

- `/admin/ux-exploration`
- `/admin/ux-exploration/model-config-cleanup`
- `/admin/ux-exploration/capability-command-center`
- `/admin/ux-exploration/route-topology-map`
- `/admin/ux-exploration/guided-change-review`
- `/admin/ux-exploration/holistic-control-room`

Artifacts:

- [`admin-ux-exploration.html`](../assets/design-review-2026-05-25/admin-ux-exploration.html)
- [`admin-ux-exploration.png`](../assets/design-review-2026-05-25/admin-ux-exploration.png)

Feedback and voting:

- [GitHub issue #75: UX concept voting](https://github.com/bglusman/wardwright/issues/75)

## Included Concepts

1. **Current model config cleanup**: conservative simplification of the existing
   Models & access page.
2. **Capability Command Center**: model capability and tool-advertisement
   clarity.
3. **Route Topology Map**: graph-first explanation of model composition,
   targets, tools, policy, receipts, and adapters.
4. **Guided Change Review**: a safer workflow for risky model changes.
5. **Holistic Control Room**: a whole-product admin shell covering Overview,
   Models, Policy Lab, Evidence, Integrations, and Release readiness.

The gallery and app routes keep these concepts separate from implemented
production admin behavior. They are discussion and selection surfaces, not a
claim that any concept has replaced `/admin`.

The in-app exploration now separates two axes:

- **Layout concept**: the five routes above arrange the same live model-access
  panels around different jobs: configuration, capability inspection, topology,
  guided review, and a holistic control room.
- **Visual theme**: the Lustre surface exposes independent Operations, Studio,
  Topology, and Review themes. This keeps styling experiments mixable without
  copying the behavior implementation.

The first real behavior wired into the exploration is model-level server-tool
management. The exploration page reuses the production Models & access summary,
access policy editor, and server-tool panel, so toggling a tool from a concept
view changes the same stored model configuration as the production admin page.
