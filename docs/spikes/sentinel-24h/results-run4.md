# Sentinel spike, run 4 (ADR 0042: ring every 10 s under suspicion, else 60 s; allocator relief)

Run: 2026-11-16 19:51 to 2026-11-17 11:49 CET. Raw data: `results-run4.csv`. 99 rows, so about 8.2 h of awake time.
No windows excluded.

| | Run 3 | Run 4 |
|---|---|---|
| Incidents per awake hour | about 4 | about 3 |
| CPU, all intervals (median / p90) | 0.14% / 0.20% | 0.115% / 0.21% |
| CPU, intervals with no new incident (median, p10–p90) | 0.107% | 0.102% (0.077–0.165%) |
| Intervals under 0.1% | 16% | 30% |
| `ps` children (whole run) | 0.028% | 0.016% |
| Memory (footprint) | 19.9 MB first row, peak 21.7 MB | 19.8 MB first row, peak 21.5 MB |

Memory at the end: footprint 20 MB, of which 12 MB dirty "Malloc Small"; live heap 7.3 MB. Returning freed memory
(`malloc_zone_pressure_relief`) after incidents and hourly did not lower it: the kept memory is fragmented, not in
empty pages.

## Findings

1. The quiet floor dropped only slightly (0.107% to 0.102%); the ring is no longer the main cost.
2. Memory relief had no measurable effect.
3. Both remaining gaps need measurement, not more cadence changes: the CPU not visible in the Time Profiler
   capture (kernel time, timer wake-ups, `ps` start-up) and the source of the fragmented 12 MB.
