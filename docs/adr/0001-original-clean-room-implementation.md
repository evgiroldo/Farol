# 0001. Original, clean-room implementation

- Status: Accepted
- Date: 2026-11-14

## Context
The project was inspired by TMOG (tmog.org), a cross-platform task manager. TMOG is proprietary: its bundle states "All rights reserved" and its license forbids public redistribution. The first idea was to reverse engineer it (using the REA tool) and publish an open-source "Pro" version.

## Options
1. Reverse engineer TMOG and reimplement its code and design.
2. Build an original app from public Apple documentation, with its own name, code and visual identity.

## Decision
Option 2. Farol contains no code, assets, names, file formats or visual identity derived from TMOG or any other proprietary monitor. Ideas common to the category (process lists, recording telemetry) are fair game; their expression is not. Reverse-engineering tools may be used only for black-box behavioral observation, never to copy implementation.

## Consequences
- The GPLv3 license (ADR 0002) can be applied without legal risk of a derivative work.
- Metrics are implemented from public APIs and documentation (and, where unavoidable, isolated private APIs — ADR 0008).
