# Sentinel spike, run 3 (ADR 0039: 10 s detector, ring every 20 s, incident detail every 5 s)

Run: 2026-11-16 07:08 to 19:37 CET. Raw data: `results-run3.csv`. 95 rows, so about 7.9 h of awake time.
Excluded from the CPU figures: 17:55–19:30 CET (attribution spike runs and builds).

## Measured

| | Run 2 | Run 3 |
|---|---|---|
| Incidents per awake hour | about 9 | about 4 |
| CPU, all intervals (median / p90) | 0.24% / 0.36% | 0.14% / 0.20% |
| CPU, intervals with no new incident | 0.105–0.113% | median 0.107% |
| Intervals under 0.1% | 1% | 16% |
| Memory (footprint) | 14.5 MB, peak 16.4 MB | 19.9 MB at first row, peak 21.7 MB |

## Profile of the quiet floor (Time Profiler, 120 s, 19:33 CET, Mac quiet)

57 samples of 1 ms in the sentinel process (about 0.05% of a core); the CSV row for the same 5 minutes says 0.106%
(including `ps` children). About half of the measured cost is visible in the profile; the rest is not explained yet.

| Where | Share of samples |
|---|---|
| Ring snapshot (`sampleRing` → `ProcessSampler.snapshot`), 6 per 120 s | 51% (about 4.8 ms each) |
| PID rescan (`discoverDaemons`, once per 5 min; one call fell in the window) | 26% |
| Daemon `ps` queries | 11% |
| System counters | 5% |

## Memory (footprint and heap, 19:37 CET)

- Footprint 21 MB, of which 13 MB is dirty "Malloc Small".
- Live heap allocations: 7.5 MB (48,093 blocks).
- So most of the footprint is memory that was freed but kept by the allocator after peaks, not live data. This is
  consistent with no leak, but does not prove it.
- Why run 3 started 5 MB higher than run 2 is not known.

## Findings

1. The stricter detector halved incidents and nearly halved total CPU.
2. Halving the ring cadence did not lower the quiet floor, contrary to the ADR 0039 estimate (about 0.08%).
3. With peak + 20% (ADR 0028), the memory budget would be about 26 MB, over the 25 MB cap.
