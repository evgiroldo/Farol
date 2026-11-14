# 0010. Causal attribution: suspects by correlation, proof by pause

- Status: Accepted; amended by ADR 0019
- Date: 2026-11-14

## Context
On macOS the process at the top of the list is often a victim: `WindowServer`, `mds_stores` and `kernel_task` work on behalf of other apps. Existing guides tell users to quit apps one by one and watch the numbers.

## Evidence (prototype, see `docs/spikes/`)
Synthetic tests on one Mac, with a known culprit and decoys:
- **Correlation alone failed.** The rendering culprit tied with a decoy that burned CPU in the same rhythm (r = 0.52 vs 0.53). In the Spotlight test, the real file writer ranked second (r = 0.29) behind an unrelated process (r = 0.89). A random-rhythm decoy was correctly rejected.
- **Pausing the suspect for 3 s proved the cause.** Pausing the renderer dropped WindowServer load by 63%; pausing the synchronized decoy had no effect (0%); pausing the file writer dropped `mds_stores` by 99% (51.7% → 0.3%).
- Reading data needs no root: `proc_pid_rusage` for the user's processes, `/bin/ps` for system daemons.

## Decision
1. Correlation over recent history (with lag and volume weighting) produces a ranked list of **suspects**.
2. A user-confirmed micro-experiment — pause the suspect (`SIGSTOP`) for ≤ 3 s, measure, resume (`SIGCONT`) — produces the **proof**.
3. The same engine, at a larger time scale, powers the experiments of M4.

### Pause safety rules
- Explicit confirmation **for every proof** (no "always allow").
- Only processes owned by the logged-in user.
- Maximum 3 seconds.
- Protected list, never paused: Finder, Dock, apps in an audio/video call, the frontmost app the user is interacting with, and apps in the middle of network or recording operations (a public report describes losing work after a `SIGSTOP`).
- A watchdog guarantees `SIGCONT` even if Farol crashes.

## Consequences
- The user sees the paused app freeze for up to 3 seconds; the UI must say so before asking.
- Causes inside root-owned processes cannot be paused; they are explained instead (knowledge base, ADR 0003).
- Results are labeled *inferred* (correlation) or *measured* (proof).
