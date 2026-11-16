# 0033. Cause test statistics

- Status: Accepted; amended by ADR 0040
- Date: 2026-11-15
- Amends: 0022

## Context
The second review showed that ADR 0022's verdict rule was not statistically defined: 6 seconds of observation give only two 3-second windows to estimate natural fluctuation, 0.5 s samples at 10% load are dominated by `ps`'s 10 ms resolution, and the "drops every pause, rises every resume" pattern occurs by pure chance 272/5040 ≈ 5.4% of the time.

## Decision
1. **18 seconds of observation** (six 3-second windows) before the first pause; the whole test takes about **42 seconds**.
2. Each window's CPU share is computed from **cumulative CPU time at the window's start and end** (`ps` `time`), not from 0.5 s samples.
3. **Natural fluctuation** is the standard deviation of the six observation windows.
4. **Thresholds are calibrated, not chosen**: in the re-run of the attribution spike, the test is run on recordings with no pause, and the "high" and "medium" thresholds are set so that a test with no real effect is called *proven* less than **1%** of the time. Until calibrated, the cause test is not shipped.
5. **Per-daemon lag**: a daemon may respond to a pause with a delay (Spotlight queues work); the knowledge base sets a lag per daemon, and windows are shifted accordingly.
6. The result is phrased as "in three tries, between X% and Y%", not as a statistical interval.
7. **Occlusion**: covering the suspect's window can itself stop its drawing. The test UI is a small, static panel that does not cover other windows and shows no animation or live chart during the test; the 10% minimum is re-checked after the panel appears. The spike re-run validates this with real apps.

## Consequences
- The card text in ADR 0031 ("about 40 s") matches the test length.
