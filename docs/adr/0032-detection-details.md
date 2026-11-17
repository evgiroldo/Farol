# 0032. Detection details: suspicion sequence, "normal" work, incident limits

- Status: Accepted; amended by ADR 0039
- Date: 2026-11-15
- Amends: 0021 (trigger logic), 0024 (normal macOS work), 0018 (history size)

## Context
The second review (ADR 0030) found that the daemon trigger in ADR 0021 did not define what happens after the global CPU signal fires, that "known normal work" could hide a stuck Spotlight forever, and that no ADR capped incident detail or the history size.

## Decision
1. **Suspicion sequence.** When busy cores rise +0.3 above baseline, the sentinel takes a reference `ps` query, then queries again at **+10 s** and **+20 s**. An incident with reason `daemon` starts if a watched daemon is at **≥ 25% of one core in both windows**. At most **6 sequences per 10 minutes**; the baseline does not learn while a sequence runs. The 30 s heartbeat continues independently. Expected detection: 20–30 s after onset for loads above the trigger, up to 60 s for loads only the heartbeat sees.
2. **What counts as normal macOS work.** A daemon's work is called normal only with **evidence**: a macOS update or first boot, or a large import or file change recorded in the last 24 hours. It **expires after 6 hours** of continuous work; after that Farol stops calling it normal and may alert with the measured fact ("Spotlight has been busy for 6 hours").
3. **Incident limits.** Full per-process detail for the first **10 minutes** of an incident; after that, the top 20 apps every 10 s. The history file never exceeds **200 MB**; the oldest data is removed first.

## Consequences
- The README budget table gains a "checking a suspicion" row once measured.
- The knowledge base records, per daemon, which evidence makes its work normal.
