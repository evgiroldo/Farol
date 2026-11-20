# Run 6: one night with the ADR 0043 cadences

Six-hour unattended run, 2026-11-17 23:00 – 2026-11-18 05:00 UTC, started and stopped by a one-time launchd job. Nobody used the Mac. A second user account was logged in (fast user switching) the whole time. Raw data: `results-run6.csv` (totals including `ps` children) and `results-run6-breakdown.csv` (sentinel thread CPU per component). Settings as in run 5.

## Results (measured)

71 five-minute intervals.

| | Value |
|---|---|
| Total CPU (own + `ps`), quiet intervals, median | **0.047%** of one core |
| Same, 90th percentile | 0.068% |
| Same, highest quiet interval | 0.089% |
| Highest interval overall (incident) | 0.240% |
| Own thread CPU, quiet intervals without discovery | 57 ms per 5 min (0.019%) |
| `ps` children, whole run | 0.030% |
| Memory footprint | 13.37 MB at start, 14.17 MB from 01:31 UTC to the end |
| Wake-ups | 0.5–0.85 per second |
| Incidents | 6 (five of 30–36 s, one of 334 s) |

Per quiet interval (averages, without discovery): ring snapshots 26 ms, `ps` 8 ms of own time (the child process costs more), detector 0.1 ms, minute row 1.3 ms. Discovery every 15 min: 17–19 ms.

## Reading

- The quiet floor on an idle Mac is about **0.05%**, as estimated in run 5. Every quiet interval stayed under 0.1%.
- `ps` children are now about 60% of the cost (0.030% of 0.047%).
- Memory grew by 0.8 MB in the first 90 minutes and then stayed flat for 4.5 hours: no sign of a leak over this run.
- An incident costs more: the 334-second incident interval used 0.24%, mostly snapshots every 5 s (262 ms of incident work).

## Finding: work the sampler cannot see

The long incident (01:50–01:56 UTC) had about 2.1 busy cores for 5 minutes (system minutes, measured). The processes the sampler recorded account for 18 CPU seconds, against about 700 core-seconds of busy time (estimated from the minute rows): **over 97% of the work was not attributed**. No watched daemon crossed 25% of a core either.

Cause (measured in a check after the run): `proc_pid_rusage` fails for processes of other users, including root and the second logged-in account, so they never appear in snapshots. All 213 processes recorded in that incident belong to the user running the sentinel. `proc_pidpath` does work for those processes, and setuid `/bin/ps` reads their CPU time.

Who did the work is unknown. Cumulative CPU times after the run point at the second account's media analysis and Spotlight processes and at root daemons (inferred, not measured for that window).

Consequence for the 0.1 preview: in such an incident, the verdict would be *unclear*: no visible app reaches 0.5 core and no watched daemon reaches 0.25. The detector sees the slowdown; attribution does not.
