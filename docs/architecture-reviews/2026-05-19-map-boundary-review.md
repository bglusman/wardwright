---
layout: default
title: Map Boundary Review - 2026-05-19 Workbench
description: Review note for the map-boundary ratchet update in the registered-model workbench PR.
---

# Map Boundary Review - 2026-05-19 Workbench

The map-boundary baseline increases in this PR are intentional and confined to
two existing open JSON contracts:

- `Wardwright.current_config/0` and normalized model configuration now include
  `model_definition_version`. Model definitions remain JSON-compatible maps
  because they are loaded from files, stored in SQLite, and served through the
  OpenAI-compatible model APIs.
- `Wardwright.PolicyProjection` emits additional state-machine transitions,
  retry-attempt fixtures, and projection metadata for the workbench. That module
  is still the JSON projection boundary between policy/model definitions and
  browser consumers.

The longer-term direction is unchanged: move pure projection derivation into
typed Gleam values and keep Elixir map access at the file/API/storage boundary.
This update records the current boundary count after that review rather than
normalizing the extra open shapes as a permanent preferred style.
