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

- **UX concept**: the five routes above are whole-admin candidates, not single
  page mockups. Each route embeds the real Workbench/model lab, Models & access
  controls, Policy Lab authoring, Control Debugger evidence, adapter status, and
  release-readiness surfaces so reviewers can stay inside one coherent concept
  experience end to end.
- **Look and feel**: the Lustre surface exposes independent Operations, Studio,
  Topology, and Review treatments. They vary density, radius, borders, shadow,
  typography treatment, and component emphasis so reviewers can mix the UX
  concept and visual system independently.

The exploration page reuses production/admin modules rather than static copies:
model-level server-tool management, model lifecycle/key controls, simulation,
policy authoring, receipt replay, harness handoff, and adapter-status rendering
all dispatch through the same Lustre update paths as the protected admin app.

## Design Rationale

This pass follows three design constraints rather than a purely aesthetic theme
exercise:

- Complex admin products need persistent, predictable navigation. Material
  Design recommends side navigation for many top-level views and deep
  structures, and cross-links for moving directly between non-adjacent scenes.
  Wardwright's exploration now treats each concept route as its own complete
  admin shell: links stay on the active concept route and jump to embedded
  model lab, model configuration, policy, evidence, integration, and release
  sections instead of escaping back to the older `/admin?...` pages.
- Progressive disclosure is the right default for risky model configuration:
  start with the current model promise, expose access/tool/evidence controls
  where they are needed, and keep release proof adjacent to the decision. NN/g's
  application-design examples frame this as moving from dashboard-level health
  into data-intensive graph or grid detail only when a user drills in.
- Component systems should preserve functional consistency while allowing
  product-specific composition. Carbon describes components as reusable solutions
  that work together as a whole, so this exploration keeps shared live controls
  and changes the shell, density, navigation, and card treatment around them.

References used for this pass:

- [Material Design navigation patterns](https://m1.material.io/patterns/navigation.html)
- [Material Design layout structure](https://m1.material.io/layout/structure.html)
- [Carbon Design System component overview](https://carbondesignsystem.com/components/overview/components/)
- [NN/g Application Design Showcase, 2008](https://media.nngroup.com/media/reports/free/Application_Design_Showcase_1st_edition.pdf)

## Current Implementation Notes

- Every concept uses the same live Wardwright model state and action dispatchers,
  but owns its presentation. Tests assert shared behavior, embedded end-to-end
  admin surfaces, and same-concept navigation rather than fixed panel order or
  links back to older admin routes.
- The UI now includes five UX buttons and four look-and-feel buttons. Reviewers
  can compare a conservative config flow, capability-first console, topology
  map, guided review flow, and holistic control room under the same four visual
  treatments.
- The exploration remains non-production. It is a live evaluation surface for
  choosing which shell, density, and component treatment should graduate into
  the protected `/admin` app.
