# 0037. Process sampler caches

- Status: Accepted; amended by ADR 0043
- Date: 2026-11-15
- Amends: 0030 (cost of a process snapshot)

## Context
The first hour of the 24-hour measurement (ADR 0028) showed the sentinel at 0.17–0.42% of one core while the Mac was in use — above the 0.1% idle target. A CPU profile (Time Profiler, 90 s, Mac quiet) put the prototype at 0.089% of a core, with **91% of that time in the per-process snapshot** taken every 10 s for the 60-second ring (ADR 0021). During incidents the same snapshot runs every 2 s, which explains the higher numbers while the Mac was busy.

Each snapshot read every process from scratch: a failing `proc_pid_rusage` call for each of the ~800 processes of other users, and for each of the ~490 readable ones a second call (`PROC_PIDTBSDINFO`) plus name decoding and sanitizing — although none of that changes during a process's life.

ADR 0030 estimated a snapshot at 1.4 ms, from a tight benchmark loop. Measured the way the sentinel actually runs — on a utility-QoS queue (efficiency cores), seconds apart, with cold caches — it cost **6.5 ms**.

## Decision
`ProcessSampler.snapshot()` keeps two caches:
- **Known processes**: identity (PID + wall-clock start time), name and owner, keyed by PID and checked on every read against the kernel's start time (`ri_proc_start_abstime`). A mismatch means the PID was reused, and the entry is replaced.
- **Unreadable PIDs**: processes of other users (`EPERM`), skipped until the next refresh.

Both caches are rebuilt every **60 seconds** (a process may change its name with `execve`; a reused PID may become readable). `sample(pid:)` stays uncached and is the only read allowed before acting on a process (ADRs 0023, 0034).

Benchmarks are measured on a utility-QoS queue with seconds between samples, never in a tight loop.

## Evidence (one Mac, 20 snapshots 2 s apart on utility QoS)
| | CPU per snapshot | Ring (every 10 s) | Incident (every 2 s) |
|---|---|---|---|
| Before | 6.5 ms | 0.065% | 0.33% |
| After | 4.0 ms | 0.040% | 0.20% |

## Consequences
- Projected idle cost of the sentinel: about 0.05–0.06% of a core (ring + heartbeat `ps` + counters), within the 0.1% target; to be confirmed by the restarted 24-hour measurement (started 2026-11-15 01:09).
- The cached path skips work for unreadable PIDs for up to 60 s; a user process that reuses such a PID is seen at most 60 s late.
