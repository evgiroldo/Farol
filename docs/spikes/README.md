# Spikes

Throwaway prototypes used as evidence for architecture decisions. **Not Farol code** — do not copy into the app.

| Spike | Question | Result | ADR |
|---|---|---|---|
| [`attribution/`](attribution/) | Can we attribute daemon load to the app that caused it, without root? | Correlation alone is ambiguous. Pausing gave a strong single-trial signal for mds_stores (−99%); the WindowServer run (−63%) is not evidence: daemon load was ~0.6% and within noise. Feasibility signal only — see ADR 0019 | [0010](../adr/0010-causal-attribution-and-proof-by-pause.md) |
| [`sentinel/`](sentinel/) | Can an always-on menu bar sentinel stay under 0.1% CPU? | 0.006–0.008% idle, 12.5 MB; incident mode 0.3–0.6% (one Mac, 250 s, no SQLite or daemon reads yet) | [0011](../adr/0011-always-on-menu-bar-sentinel.md) |
| [`sentinel-24h/`](sentinel-24h/) | Do the budgets hold with every part of the real sentinel (SQLite, `ps`, 60 s ring, notifications, XPC, menu) over 24 h? | First hour (uncached sampler, `results-run1-uncached.csv`): 0.17–0.42% CPU while in use, caused by the process snapshot (ADR 0037). Restarted 2026-11-15 01:09 with caches; results when done | [0028](../adr/0028-budget-policy.md) |
| [`attribution-v2/`](attribution-v2/) | Can the cause test be trusted with real WebKit drawing and real file indexing, and which thresholds keep false proofs under 1%? Does Farol's own window hide the load? | Built 2026-11-15, not run yet; see `attribution-v2/RUN.md` | [0033](../adr/0033-cause-test-statistics.md), [0034](../adr/0034-pause-safety-details.md) |

## Reproducing

Requires the Swift toolchain (Xcode or Command Line Tools) on Apple silicon.

```bash
cd attribution
swiftc -O sampler.swift -o sampler
swiftc -O stimulus.swift -o farol-render
for m in burn-sync burn-random write write-decoy; do cp farol-render farol-$m; done
# Test 1: rendering culprit + decoys (a window appears for 60 s)
(./farol-render & ./farol-burn-sync & ./farol-burn-random & wait) & sleep 2; ./sampler 40 --intervene
```

```bash
cd sentinel
swiftc -O sentinel.swift -o farol-sentinel
./farol-sentinel 2 270   # prints its own cost every 30 s
```

Results were measured on a single Mac with synthetic load; they indicate feasibility, not guaranteed accuracy.

### 24-hour sentinel measurement

```bash
docs/spikes/sentinel-24h/build.sh && open docs/spikes/sentinel-24h/FarolSpike.app
```

It appends one line every 5 minutes to `~/Library/Application Support/FarolSpike/measure.csv` (CPU % including `ps` children, memory footprint, wakeups, `ps` calls, incidents). Quit it from its menu bar item. Its history lives in the same folder, separate from Farol's.
