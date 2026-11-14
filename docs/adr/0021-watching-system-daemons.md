# 0021. Watching system daemons without breaking the idle budget

- Status: Accepted
- Date: 2026-11-14
- Amends: 0007 (cost of `/bin/ps`), 0011 (what the sentinel watches)

## Context
The first review found that the detector cannot see Farol's signature cases: it triggers only when busy cores rise more than one full core above baseline, but `mds_stores` at 50% or `WindowServer` at 38% add less than one core. The history also stored no daemon data and no samples from before the trigger, so the onset — what correlation needs most — was lost.

System daemons run as other users, so their CPU can only be read through Apple's setuid `/bin/ps`. ADR 0007 claimed this costs "~0 ms"; that was never measured.

## Evidence (measured 2026-11-14, one Mac, 20 daemon PIDs per query)
| How `ps` is started | CPU per query | every 2 s | every 5 s | every 30 s |
|---|---|---|---|---|
| `Foundation.Process` | 10.7 ms | 0.54% | 0.21% | 0.04% |
| `posix_spawn` | 2.6 ms | 0.13% | 0.05% | 0.009% |

The idle target is < 0.1% of one core (README), so polling `ps` at the sentinel's 2 s cadence is not affordable.

## Options
1. **Adaptive**: the free global CPU signal triggers a `ps` query; plus a periodic heartbeat query.
2. Fixed `ps` query every 5 s (~0.05%).
3. No `ps` while idle; lower the global threshold (+0.4 core) instead — free, but noisier and blind to *which* daemon.

Pre-trigger memory: system + top-20 apps, system only, or none. Watch list: a known list, or every system process (~1,300, ~20 ms per query).

## Decision
1. **Adaptive watching.** Every 2 s the sentinel reads global counters (unchanged). When busy cores rise **+0.3 core** above baseline, it queries the watched daemons immediately; otherwise it queries them every **30 s** (heartbeat). A watched daemon at **≥ 25% of a core for 20 s** starts an incident with reason `daemon`. Thresholds are initial values, to be tuned with real data.
2. **60-second in-memory ring.** The sentinel keeps the last 60 s of global samples, every daemon query, and the **top 20 apps by CPU every 10 s**. It never touches disk unless an incident starts; then the ring is written as the incident's first samples.
3. **Known watch list.** About a dozen daemons that commonly cause slowdowns (e.g. `WindowServer`, `mds_stores`, `mds`, `mdworker_shared`, `photoanalysisd`, `mediaanalysisd`, `backupd`, `softwareupdated`, `cloudd`, `bird`, `coreaudiod`, `kernel_task`), kept in a data file that is easy to extend — the seed of the knowledge base (ADR 0003).
4. **`ps` is started with `posix_spawn`**, absolute path `/bin/ps`, fixed arguments, no shell, empty environment. Its output is parsed defensively (untrusted text).
5. The history gains a table for daemon samples during incidents (schema migration 1 → 2).

## Consequences
- Estimated idle cost about 0.01–0.02% of a core; detection of a daemon problem in about 10–30 s. Both must be confirmed by the re-measurement planned in ADR 0019.
- Daemons not on the list are only noticed through the global CPU signal and are not named until the list grows.
- A daemon that legitimately runs above 25% for long periods (e.g. a first Spotlight index) will open an incident; the knowledge base must explain it ("normal, ends in ~N min") rather than blame an app.
