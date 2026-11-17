# Investigation after run 4: where the quiet floor and the memory go

2026-11-17, one Mac, Mac in light use. Spike instrumented with thread CPU time per component
(`clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`); raw rows in `investigation-breakdown.csv` (one per 5 min).

## CPU, quiet 5-minute intervals (11:02–11:12Z, no incident open)

| | Per 5 min | Share of one core |
|---|---|---|
| Sentinel's own CPU | 106–134 ms | 0.035–0.045% |
| of which inside the 2 s tick | 99–111 ms (83–93%) | |
| — ring snapshots (5 per 5 min) | 52–57 ms, about 11 ms each | about 0.018% |
| — PID rescan (`discoverDaemons`, 1 per 5 min) | 8–19 ms | about 0.005% |
| — daemon `ps` queries, parent side | 11–20 ms | about 0.005% |
| — system counters | 6–7 ms | about 0.002% |
| `ps` children | | about 0.04–0.06% |
| Total (CSV) | | 0.075–0.117% |

Corrections:
- **`ps` is the largest single cost, not negligible.** About 10–14 ms of CPU per call, as the Fable smoke test
  found; ADR 0021 said 2.6 ms. The `child_cpu_pct_total` column of the earlier runs divided by wall-clock time
  including sleep, which understated it (0.016%).
- **A ring snapshot costs about 11 ms, not 4.8 ms.** With the ring every 60 s (ADR 0042) and the sampler caches
  rebuilt every 60 s (ADR 0037), almost every quiet snapshot is a cold read.
- The Time Profiler capture missed the `ps` children (other processes) — that was the "unexplained half".

## Memory (10 min with `MallocStackLogging=lite`)

- Live heap 4.7 MB; footprint 17.6 MB (stack logging adds its own overhead).
- The largest regions come from AppKit at start-up (`NSApplication`, the status item and its SF Symbol image), a
  fixed cost of a menu bar app.
- In runs 3 and 4, 12–13 MB of the footprint was dirty "Malloc Small" with only 7.3–7.5 MB live, and
  `malloc_zone_pressure_relief` did not return it. Why those runs started near 19.8 MB while runs 2 and this one
  started near 14.6 MB is still not known.
