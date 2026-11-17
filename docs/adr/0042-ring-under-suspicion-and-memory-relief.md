# 0042. Ring sampled under suspicion; allocator memory returned

- Status: Accepted
- Date: 2026-11-16
- Amends: 0039 (ring cadence), 0021 (60-second ring)

## Context
Run 3 of the sentinel measurement (`docs/spikes/sentinel-24h/results-run3.md`, about 7.9 h awake) confirmed that the 10-second detector (ADR 0039) halves incidents, but the quiet floor stayed at about **0.107%** of a core, over the 0.1% target. Halving the ring cadence had not lowered it. A 120 s Time Profiler capture of the quiet sentinel found the ring snapshot to be the largest visible cost (51% of samples, about 4.8 ms per snapshot); about half of the measured cost was not visible in the profile.

Memory peaked at 21.7 MB, of which only 7.5 MB were live heap allocations; most of the rest was freed memory kept by the allocator. Peak + 20% (ADR 0028) would exceed the 25 MB cap.

Options considered for the floor: sample the ring only under suspicion; accept about 0.11% and raise the target.

## Decision
1. **Ring under suspicion.** The ring samples the top 20 apps every **10 s while busy cores are 0.3 or more above baseline** (the suspicion signal of ADR 0021), and every **60 s** otherwise. It still covers the last 60 s, keeps each sample's real time, does not sample during an incident and is cleared when one ends. Because an incident needs 10 s of abnormal load to start (ADR 0039), the samples just before an incident are normally taken at the fast cadence.
2. **Memory relief.** The sentinel asks the allocator to return freed memory (`malloc_zone_pressure_relief`) after each incident and once per hour.

The 0.1% idle target is kept. Both changes are confirmed by a new measurement before the README budgets are set.

## Consequences
- A slowdown with a sudden start may have its first ring sample up to 60 s old; cumulative CPU between samples still attributes the work, with coarser timing.
- If the floor stays above 0.1%, the unexplained half of the cost (kernel time, timer wake-ups, `ps` start-up) must be measured before more cadence changes.
