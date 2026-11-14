# Farol

**The Mac monitor that finds the real culprit — and proves it.**

> Status: early development. No release yet. The architecture is documented in [`docs/adr/`](docs/adr/); the measurement core lives in [`FarolCore/`](FarolCore/).

Nobody keeps a resource monitor open. You open one because your Mac *feels wrong*. Farol is built for that moment: instead of a wall of graphs, it answers three questions — **what is happening, why, and what fixes it** — and backs every answer with evidence.

## What Farol aims to do

- **Test causes instead of guessing.** Correlation over recent history narrows down suspects; then, with your confirmation, Farol briefly pauses a suspect and measures how the system responds. The result is reported with a confidence level — or as *inconclusive* when the data does not support a conclusion. (Early prototypes showed the idea is feasible; the method is still being validated, see [ADR 0019](docs/adr/0019-corrections-after-first-review.md).)
- **Find who is behind system processes.** `WindowServer`, `mds_stores` and friends rarely act on their own. Farol tries to attribute their load to the app that triggered it.
- **Remember what you missed.** A tiny always-on sentinel watches cheap system counters and records detailed data only when something unusual happens — so Farol can explain the slowdown from two minutes ago.
- **Experiments that settle debates.** Guided A/B tests on *your* usage ("does Safari really save battery for me?"), with repeats and error margins.
- **Honest numbers.** Every value is labeled *measured*, *estimated* or *inferred*. Unavailable data is shown as unavailable, never invented.
- **Lighter than the problem it diagnoses.** See the budget targets below.

Some causes cannot be tested by pausing an app — thermal throttling, memory pressure, a full disk, work inside system processes. For those Farol explains what it sees instead of claiming proof.

## Principles

| | |
|---|---|
| **Privacy** | Zero network access. Nothing leaves your Mac. History is minimal, local, excluded from backups and deletable. |
| **Security** | Nothing runs as root. Hardened Runtime. No third-party dependencies. Release builds will be reproducible from public commits with signed provenance. |
| **Performance** | Resource budgets will be enforced in CI and checked on real hardware before each release. |

### Resource budget targets

Targets, pending measurement with the real sentinel ([ADR 0019](docs/adr/0019-corrections-after-first-review.md)). This table is the single source of truth.

| Process | State | CPU (of one core) | Memory |
|---|---|---|---|
| Sentinel (menu bar) | Idle | < 0.1% | < 15 MB |
| Sentinel (menu bar) | Recording an incident | < 1% | < 15 MB |
| Farol app | Window open, updating every second | < 1% | < 60 MB |

Monitoring runs at low priority (`utility`/`background` QoS), which keeps it mostly on the efficiency cores.

## Requirements

- Mac with Apple silicon (M1 or later)
- macOS 26 or later

## Roadmap

1. **M1 — Foundation:** low-cost sampler, incident-triggered history, processes and performance views, menu bar sentinel.
2. **M2 — Real culprit:** suspect ranking and testing causes by pause.
3. **M3 — Energy & thermals:** power and temperature sensors.
4. **M4 — Experiments:** guided A/B tests.

## Contributing

Read the [architecture decision records](docs/adr/) to understand why things are the way they are. Security issues: see [SECURITY.md](SECURITY.md).

```bash
cd FarolCore && swift test
```

## License

Farol is free software, licensed under the [GNU General Public License v3.0](LICENSE).
