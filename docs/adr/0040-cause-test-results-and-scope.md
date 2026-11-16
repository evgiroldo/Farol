# 0040. Cause test results: WindowServer in 1.0, Spotlight later

- Status: Accepted
- Date: 2026-11-16
- Amends: 0029 (cause test scope), 0033 (test duration)

## Context
ADR 0033 requires the cause test to be validated and its thresholds calibrated before it ships. The attribution spike v2 ran twice on one Mac (Mac17,3, macOS 27.2.1), with synthetic culprits started by the spike: `docs/spikes/attribution-v2/results-run1.md` and `results-run2.md`.

- **Run 1** (52 min): the test window used CSS animations. WebKit hands those to the system compositor, which keeps animating while the app is paused, so WindowServer stayed at about 42% of a core with the whole app group stopped. All 16 real-cause tests were inconclusive. The Spotlight culprit rewrote the same 400 files, and Spotlight stopped indexing them.
- **Run 2** (17 min): the page drives every frame from its own script; the writer creates new files.
  - **WindowServer: 3 of 3 proven**, ratio 89–125× (threshold 3×), share 97–98%. Pausing dropped WindowServer from about 34% to 1% within 0.25 s; it recovered within 0.25 s of resuming.
  - **Spotlight (`mds_stores`): 0 of 4 proven.** The effect is real (about 32% running, 7% paused, recovery about 1.5 s after resuming), but the work comes in bursts: the fluctuation between 3-second windows (about 25% of a core) is as large as the effect, so no test passed 2×.
  - With an on/off culprit (4 s on, 3 s off), tests were inconclusive, as intended.
- **No false proofs**: 0 of 46 tests where the paused process was not the cause (both runs), and sham calibration put the thresholds below the ADR 0022 starting values (3× and 2×), which stay as floors.

## Decision
1. Version 1.0 offers **Pause to confirm only for WindowServer**. Spotlight keeps its plain explanation and the measured facts (which apps write most to disk), without a pause test. A Spotlight cause test (longer, with more cycles, recalibrated) moves to after 1.0.
2. WindowServer's lag is **0 s** (measured, 0.25 s resolution).
3. Correction to ADR 0033: the protocol (18 s observation plus 3 × 6 s) lasts **36 s**, not about 42 s.

## Consequences
- **Known blind spot:** work an app hands to the system compositor (CSS or Core Animation animations) continues while the app is paused, so the test cannot confirm it and reports "unclear". The result text must not suggest the app is innocent.
- Evidence is from one Mac and synthetic culprits; tests with real apps are still required before release (ADR 0029).
- Open decision: other Apple services attributed to a web app (`MTLCompilerService`, `SetStoreUpdateService`, `com.apple.audio.SandboxHelper`) would make ADR 0034 §3 refuse every test of such an app.
