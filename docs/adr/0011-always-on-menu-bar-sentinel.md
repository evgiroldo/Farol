# 0011. Always-on sentinel in the menu bar

- Status: Accepted; process model amended by ADR 0017; budgets amended by ADR 0019; daemon watching added by ADR 0021; budget policy in ADR 0028; clarified by ADR 0030
- Date: 2026-11-14

## Context
Attribution needs history, but nobody keeps a monitor open, and problems are often gone by the time the user opens one. A continuously running sampler, however, must not become a problem itself.

## Evidence (prototype, see `docs/spikes/`)
A menu bar sentinel (86 KB binary) reading only cheap global counters (`host_statistics` CPU and VM, `thermalState`) on a 2 s utility-QoS timer with leeway:
- Idle: **0.006–0.008% of one core**, 12.5 MB, ~0.7 wakeups/s, ~0 mW.
- Incident mode (per-process sampling at 1 Hz): 0.3–0.6% of one core, up to 14.2 MB.
- A synthetic overload was detected in ~9 s.
- Known gaps: detector hysteresis and baseline contamination during incidents; memory close to the limit; disk persistence and daemon reads not yet included.

## Decision
- The sentinel is **the menu bar item** (one process), installed as a login item the user approves.
- Idle mode reads global counters only; **detailed per-process capture starts only when an anomaly is detected** (CPU above baseline, swapping, thermal pressure, and later memory and disk signals) and stops after it ends.
- All monitoring runs at `utility`/`background` QoS so it lands on efficiency cores; only the UI has priority.
- The menu bar icon redraws only when its state changes.
- Budgets: idle < 0.1% of a core and < 15 MB; incident < 1% of a core. App launch < 0.5 s and first answer < 5 s even under load. Farol shows its own cost.

## Consequences
- Baseline learning must freeze during incidents; detection needs hysteresis.
- The incident buffer needs a compact, capped representation.
