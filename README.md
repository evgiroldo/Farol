# Farol

**The Mac monitor that finds the real culprit — and proves it.**

> Status: design phase. No release yet. The architecture is documented in [`docs/adr/`](docs/adr/).

Nobody keeps a resource monitor open. You open one because your Mac *feels wrong*. Farol is built for that moment: instead of a wall of graphs, it answers three questions — **what is happening, why, and what fixes it** — and backs every answer with evidence.

## What makes Farol different

- **Proves causes instead of guessing.** Correlation over recent history narrows down suspects; then, with your confirmation, Farol pauses a suspect for up to 3 seconds and measures the effect. "Pausing *App X* dropped WindowServer load by 63%" is a proof, not a hunch.
- **Finds who is behind system processes.** `WindowServer`, `mds_stores` and friends rarely act on their own. Farol attributes their load to the app that triggered it.
- **Remembers what you missed.** A tiny always-on sentinel watches cheap system counters and records detailed data only when something unusual happens — so Farol can explain the slowdown from two minutes ago.
- **Experiments that settle debates.** Guided A/B tests on *your* usage ("does Safari really save battery for me?"), with repeats and error margins.
- **Honest numbers.** Every value is labeled *measured*, *estimated* or *inferred*. Unavailable data is shown as unavailable, never invented.
- **Lighter than the problem it diagnoses.** The sentinel targets < 0.1% of one CPU core and < 15 MB of memory; all monitoring runs on efficiency cores.

## Principles

| | |
|---|---|
| **Privacy** | Zero network access. Nothing leaves your Mac. History is minimal, local and deletable. |
| **Security** | Nothing runs as root. Hardened Runtime. No third-party dependencies. Builds are reproducible from public commits with signed provenance. |
| **Performance** | Resource budgets are enforced in CI — a change that makes Farol heavier fails the build. |

## Requirements

- Mac with Apple silicon (M1 or later)
- macOS 26 or later

## Roadmap

1. **M1 — Foundation:** low-cost sampler, incident-triggered history, processes and performance views, menu bar sentinel.
2. **M2 — Real culprit:** suspect ranking and proof by pause.
3. **M3 — Energy & thermals:** power and temperature sensors.
4. **M4 — Experiments:** guided A/B tests.

## Contributing

The project is in its design phase. Read the [architecture decision records](docs/adr/) to understand why things are the way they are. Security issues: see [SECURITY.md](SECURITY.md).

## License

Farol is free software, licensed under the [GNU General Public License v3.0](LICENSE).
