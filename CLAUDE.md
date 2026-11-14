# Farol — guide for Claude sessions

Farol is an open-source (GPLv3) macOS system monitor: "the Mac monitor that finds the real culprit — and proves it". Read `README.md`, then `docs/adr/README.md` before changing anything architectural.

## How we work

- **The maintainer is the architect.** Present decisions as options with trade-offs and a recommendation; do not decide product or architecture questions alone. Talk to the maintainer in Brazilian Portuguese; code, comments and docs are in English (ADR 0015).
- **Every architectural decision becomes an ADR** in `docs/adr/`. Never edit an accepted ADR's content; write a new one and update only the old one's Status line (ADR 0000, 0019).
- **Honesty over marketing.** Never state a result the evidence does not support. Label values *measured*, *estimated* or *inferred*; show unavailable data as unavailable.
- **Model roles.** Day-to-day work runs on Claude Opus 5.5. Use **Claude Fable 5.2** (subagent with `model: fable`, read-only) for heavy, independent work where a fresh eye pays off:
  - architecture reviews and security audits at the end of each milestone,
  - before risky features: process pausing (M2), private APIs (M3), signing and release CI,
  - hard design spikes.
  Verify every reviewer finding in the code before acting on it, and bring disagreements to the maintainer.

## Hard rules

- Apple silicon only, macOS 26+, Swift 6 strict concurrency.
- **Zero third-party dependencies** in Farol itself (Apple frameworks only).
- **Zero network access** in Farol. No URLSession, Network.framework or sockets.
- Nothing runs as root; no privileged helper; Hardened Runtime.
- The history file is untrusted input: validate rows, bound reads, never act on a process identity read from disk.
- Undocumented APIs (including undocumented sysctls) only in the isolated private-sensor module, read-only, failing closed.

## Commands

```bash
cd FarolCore && swift build && swift test
```

```bash
xcrun swift-format lint -r FarolCore/Sources FarolCore/Tests
```

Format with `xcrun swift-format format -i -r FarolCore/Sources FarolCore/Tests` (config in `.swift-format`: 4 spaces, 120 columns).

## Layout

- `FarolCore/` — Swift package, measurement only, no UI (ADR 0006).
- `docs/adr/` — architecture decision records.
- `docs/spikes/` — throwaway prototypes kept as evidence; never copy them into the app.
