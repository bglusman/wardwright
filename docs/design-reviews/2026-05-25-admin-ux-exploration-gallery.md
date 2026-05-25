---
title: Admin UX Exploration Gallery
date: 2026-05-25
status: exploratory
---

# Admin UX Exploration Gallery

This page collects the Wardwright admin UX concepts into one tryable
exploration surface. The concepts are also implemented as protected
Wardwright app routes so reviewers can experience the alternatives without
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
