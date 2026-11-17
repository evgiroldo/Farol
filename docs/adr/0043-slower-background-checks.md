# 0043. Slower background checks while the Mac is quiet

- Status: Accepted
- Date: 2026-11-17
- Amends: 0021 (daemon heartbeat), 0037 (cache refresh)

## Context
After ADR 0042 the quiet sentinel still measured 0.075–0.117% of a core, over the 0.1% target. Per-component thread CPU accounting (`docs/spikes/sentinel-24h/investigation.md`) found:

- the `ps` children started for the daemon heartbeat cost about **0.04–0.06%** (10–14 ms per call, not the 2.6 ms assumed in ADR 0021). They are separate processes, so a Time Profiler capture of the sentinel does not see them;
- each ring snapshot cost about 11 ms (about 0.018%), because the sampler caches (ADR 0037) were rebuilt every 60 s, the same cadence as the quiet ring, so almost every snapshot started from an empty cache;
- daemon discovery every 5 minutes cost about 0.005%.

Options considered: raise the target to about 0.12%; replace `ps` (no documented way to read another user's process CPU without it, ADR 0021); slow the background checks.

## Decision
While the Mac looks quiet:
1. **Daemon heartbeat every 60 s** (was 30 s). Under suspicion (busy cores 0.3 or more above baseline) daemons are still queried at most every 10 s.
2. **Sampler caches rebuilt every 300 s** (was 60 s), the new `ProcessSampler.refreshInterval` default. Every cached entry is still checked against the kernel start time on each read, so a reused PID is never mistaken for the old process.
3. **Daemon discovery every 15 minutes** (was 5).

The 0.1% idle target is kept. A short instrumented measurement confirms the change before the README budgets are set.

## Consequences
- Estimated quiet floor about 0.05% of a core (estimated, to be measured).
- A system process that becomes busy without raising the whole Mac's load is noticed later: detection can take up to about two heartbeats (about 2 minutes) instead of about 1.
- A process whose name changes (after `execve`) can show its old name for up to 5 minutes.
- A newly started watched system process is watched within 15 minutes instead of 5.
