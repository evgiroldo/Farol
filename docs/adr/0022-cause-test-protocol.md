# 0022. Cause test protocol: repeated pause and resume

- Status: Accepted
- Date: 2026-11-14
- Amends: 0010 (a single 3-second pause is no longer the proof)

## Context
ADR 0010 proved a cause with one 3-second pause. The first review showed this is not evidence: daemon load fluctuates on its own (WindowServer went from 0.7% to 2.7% between two runs with no intervention), there was no check that load returns when the app resumes, and at very low load `ps` (10 ms resolution) cannot measure a difference at all. Pausing only the main process of a multi-process app (e.g. a browser) leaves the helper doing the work, and wrongly clears the app.

## Options
- Cycles: 2 (~18 s), 3 (~24 s), or adaptive 2–5.
- Minimum daemon load to offer a test: 5%, 10% or 20% of one core.
- What to pause: the suspect process only, or the whole app (main process and helpers).

## Decision
1. **Protocol** (one user confirmation covers the whole test, ~24 s):
   - 6 s observation with the app running, to measure the daemon's natural fluctuation;
   - then **3 cycles** of 3 s paused / 3 s running (the last cycle ends with the app running).
   - The daemon's CPU is sampled every 0.5 s through `ps` (ADR 0021); the user is present, so this short burst of cost is acceptable.
2. **Verdict rules.**
   - *Proven, high confidence*: in every cycle the load drops while paused **and** rises again when resumed, and the average effect exceeds three times the natural fluctuation.
   - *Likely, medium confidence*: every cycle points the same way and the effect exceeds twice the fluctuation.
   - Otherwise *inconclusive* — said plainly, never rounded up.
   - The result is the app's **share of the daemon's load with a range** across cycles (e.g. "about 40%, between 30% and 50%"), labeled *inferred* (ADR 0019).
3. **Minimum load.** The test is offered only when the daemon uses **at least 10% of one core**. Below that, Farol describes what it observes and does not claim proof.
4. **Whole app.** Farol pauses the app's main process and all its helper processes together, and resumes them together. How processes are grouped into apps is decided in its own ADR (review item C5). All pause safety rules (ADR 0010 and review item C3) apply to every process in the group.

## Consequences
- The paused app freezes three times for 3 seconds; Farol must say so before asking for confirmation, in plain words (ADR 0020).
- "Inconclusive" will be a common, honest outcome; the UI must make it useful (what was observed, what to try next).
- Thresholds (3× and 2× fluctuation, 10% minimum) are initial values to validate in the re-run of the attribution spike with real apps and several Macs (ADR 0019).
