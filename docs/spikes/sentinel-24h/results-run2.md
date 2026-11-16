# Sentinel spike, run 2 (with sampler caches, ADR 0037)

Run: 2026-11-15 00:09Z to 2026-11-16 00:12Z (24 h wall clock). Raw data: `results-run2-cached.csv`
(one row per 5 minutes of awake time; CPU is measured over awake time and includes `ps` children).
155 rows, so about 13 h of awake time; the Mac slept for the rest.

Excluded from the CPU figures: 10:25–10:51Z (smoke tests) and 13:25–13:45Z (builds).

## Measured

| | Value |
|---|---|
| CPU, intervals with no new incident (quiet floor) | 0.105–0.113% |
| CPU, all intervals | median 0.24%, p90 0.36%, max 0.60% |
| CPU, intervals marked idle / incident | median 0.19% / 0.28% |
| Intervals under the 0.1% target | 1% |
| `ps` children | 0.016% of total time; 1,253 calls |
| Wake-ups | median 0.85/s, max 2.6/s |
| Memory (physical footprint) | 14.50 MB at start, peak 16.38 MB, flat at 16.0–16.1 MB for the last 6 h |
| Incidents | 122 (about 9 per awake hour); all triggered by CPU only |
| Incident duration | median under 60 s (65 of 122), mean 393 s, max 57 min |

## Findings

1. The CPU target is missed mainly because the detector opens an incident about every 7 minutes of awake time,
   and an open incident samples every process every 2 s. With no incident, the floor is just above 0.1%.
2. Memory grew 1.9 MB in the first 19 h and then stayed flat. This looks like caches and allocator growth reaching
   a plateau, not a leak, but 24 h is not enough to prove it.
3. Every incident recorded every process for its first 10 minutes. This is what ADR 0032 decided (full detail,
   then the top 20); the history reached 21 MB in 24 h, well under the 200 MB cap.
4. `ps` is cheap at this cadence (0.016%).
