# 0005. Milestones

- Status: Superseded by ADR 0029
- Date: 2026-11-14

## Context
After the positioning change (ADR 0003), history became the base of every feature, and recording could no longer be the last milestone.

## Decision
1. **M1 — Foundation:** optimized `FarolCore` sampler within budget, incident-triggered on-disk history, processes and performance views, menu bar sentinel, provenance labels.
2. **M2 — Real culprit:** suspect ranking for system daemons and the "Prove it" pause.
3. **M3 — Energy & thermals:** power and temperature sensors (ADR 0008).
4. **M4 — Experiments:** guided A/B tests over hours or days. It follows M3 because the most wanted experiment ("which app drains my battery?") needs energy data.

All four milestones form the MVP; each one ships something testable.

## Consequences
- The history store is designed in M1 with M2–M4 in mind.
