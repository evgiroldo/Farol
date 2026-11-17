# 0039. Quieter detection and slower sampling

- Status: Accepted; amended by ADR 0042
- Date: 2026-11-16
- Amends: 0021 (ring cadence), 0032 (incident sampling cadence), detector defaults

## Context
The 24-hour measurement with sampler caches (ADR 0037; `docs/spikes/sentinel-24h/results-run2.md`) covered about 13 h of awake time on one Mac. The sentinel used a median of **0.24%** of one core, against an idle target of 0.1% (ADR 0028); only 1% of the 5-minute intervals met it.

- The detector opened **122 incidents** (about 9 per awake hour), all for CPU, on a Mac that never felt slow. Half lasted under a minute. Two samples 2 s apart above the threshold (4 s) were enough to start one.
- During an incident every process was sampled every 2 s, which is most of the excess.
- In intervals with no incident the floor was **0.105–0.113%**, just above target; the ring (top 20 apps every 10 s) is the largest part of it. ADR 0037 had projected 0.05–0.06%; the measured floor is about twice that.

## Decision
1. **Detector:** an incident starts only after **5 consecutive abnormal samples (10 s)**, instead of 2 (4 s). Margins, exit rule and minimum duration are unchanged.
2. **Incident sampling:** full per-process detail every **5 s** instead of every 2 s, still for the first 10 minutes (ADR 0032).
3. **Ring:** top 20 apps every **20 s** instead of 10 s, still covering the last 60 s (3 samples). The ring does not sample while an incident is open, and is cleared when one ends.

These are initial values. They are confirmed by a new measurement before the budgets in the README are final.

## Consequences
- Slowdowns shorter than 10 s are not recorded. A slowdown a person notices and opens Farol for usually lasts longer.
- Incident detail is coarser (5 s). Attribution uses cumulative CPU between samples, so no work is missed, only time resolution is lower.
- The ring before an incident has 3 samples, 20 s apart, instead of 6, 10 s apart.
- Expected cost: floor about 0.08%, incident mode about 0.08% on top of it while one is open; to be measured.
- Memory: footprint grew from 14.5 MB to a peak of 16.4 MB and was flat for the last 6 h. The budget per ADR 0028 (peak + 20%) is **20 MB**, under the 25 MB cap, pending the new measurement.
