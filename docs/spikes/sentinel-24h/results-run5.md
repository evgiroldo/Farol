# Run 5: slower background checks (ADR 0043)

30-minute instrumented run, 2026-11-17 12:46–13:17 UTC, Mac awake, normal light use (not a lab-quiet Mac). Raw data: `results-run5.csv` (totals including `ps` children) and `results-run5-breakdown.csv` (sentinel thread CPU per component).

Settings: daemon heartbeat 60 s (10 s under suspicion), sampler cache refresh 300 s, daemon discovery 15 min, ring 60 s quiet / 10 s under suspicion.

## Results (measured)

| 5-min interval | Mode | Total CPU (own + `ps`) | Own CPU | `ps` calls | Ring |
|---|---|---|---|---|---|
| 1 | quiet | 0.072% | 0.054% (includes start-up) | 5 | 21 ms |
| 2 | quiet, suspicion | 0.082% | 0.042% | 16 | 39 ms |
| 3 | incident | 0.128% | 0.069% | 23 | 26 ms |
| 4 | incident | 0.148% | 0.075% | 27 | 0 ms |
| 5 | quiet, suspicion | 0.085% | 0.039% | 15 | 30 ms |
| 6 | quiet | **0.063%** | 0.027% | 9 | 33 ms |

Before (investigation run, same instrumentation, quiet intervals): 0.075–0.117%.

Memory footprint: 13.8–14.7 MB (runs 3–4: up to 21.7 MB).

## Reading

- Every quiet interval is now **under 0.1%** (0.063–0.085%). The best quiet interval improved from 0.075% to 0.063%.
- `ps` remains the largest cost: about 11–12 ms of child CPU per call (estimated from total minus own CPU). With only the heartbeat (5 calls per 5 min) the floor would be about 0.05% (estimated); the measured intervals had 9–16 calls because the suspicion signal fired during normal use.
- Ring snapshots cost about 5–7 ms each (was about 11 ms): the cache is reused, but not every time.
- 3 incidents and 87 daemon-high events in 30 minutes: the Mac was in use, so this run says nothing new about detector noise.
