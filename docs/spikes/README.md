# Spikes

Throwaway prototypes used as evidence for architecture decisions. **Not Farol code** — do not copy into the app.

| Spike | Question | Result | ADR |
|---|---|---|---|
| [`attribution/`](attribution/) | Can we attribute daemon load to the app that caused it, without root? | Correlation alone is ambiguous. Pausing gave a strong single-trial signal for mds_stores (−99%); the WindowServer run (−63%) is not evidence: daemon load was ~0.6% and within noise. Feasibility signal only — see ADR 0019 | [0010](../adr/0010-causal-attribution-and-proof-by-pause.md) |
| [`sentinel/`](sentinel/) | Can an always-on menu bar sentinel stay under 0.1% CPU? | 0.006–0.008% idle, 12.5 MB; incident mode 0.3–0.6% (one Mac, 250 s, no SQLite or daemon reads yet) | [0011](../adr/0011-always-on-menu-bar-sentinel.md) |

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
