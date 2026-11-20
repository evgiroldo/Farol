# 0044. Preview version 0.1

- Status: Amended by 0045
- Date: 2026-11-17
- Amends: 0017 (two processes), 0029 (what comes before 1.0)

## Context
The measurement work for the sentinel (ADRs 0039–0043) is close to done, but nothing a person can use exists yet. The maintainer wants a first usable version before 1.0 to see the product take shape and to learn from using it.

Options considered for its scope: a menu bar list of the busiest apps right now (fastest, but does not answer "why is my Mac slow"); a menu bar icon plus an explanation of the slowdown (chosen); the same plus a 7-day history (more screens and decisions).

Options considered for its shape: one process; the two processes of ADRs 0017 and 0025 from the start. Options for distribution: local builds only; signed and published releases (needs the Apple Developer Program, ADR 0014).

## Decision
**Version 0.1 is a preview that answers "why is my Mac slow?" and does nothing to any app.**

1. **What it does.** A menu bar icon that changes when the Mac is slow. Clicking it opens a card (ADR 0031) that names the most likely cause in plain words, with measured evidence:
   - an app → "*App* may be slowing down your Mac. We're not sure yet." (the **suspect** card, without the "Pause to confirm" button);
   - a system process from the knowledge base → its plain explanation (the **normal macOS work** card);
   - memory pressure, swapping or heat → a plain explanation and what the person can do.
   Under "Details": the busiest apps, with the share of the Mac's processing power and memory each one uses, labelled *measured*.
2. **What it does not do.** No cause test, no Fix and no pausing of any process: they wait for the security review planned before risky features (CLAUDE.md). No alerts, no history window, no settings, no private APIs. The history database is not written.
3. **One process.** The menu bar app measures, detects and shows the card itself. There is no separate sentinel, no XPC and no start at login. The measuring code lives in FarolCore, so it moves into the sentinel unchanged before 1.0.
4. **Measurement as decided.** Detection follows ADR 0039 (10 s to start an incident). The 60 s ring follows ADR 0042 and the daemon heartbeat, cache and discovery cadences follow ADR 0043. Processes are grouped into apps by the outermost `.app` bundle in the executable path (ADR 0027, public API only).
5. **Verdict rules in FarolCore.** The rules that pick the cause are plain logic without UI, so they live in FarolCore, where they are tested and later reused by the sentinel and the app.
6. **Local builds only.** 0.1 is built from source and runs on the maintainer's Mac. It is ad-hoc signed with Hardened Runtime and not published, as ADR 0014 requires.
7. **Native Xcode project** with synchronized folders (ADR 0014), app target `Farol`, bundle identifier `io.github.evgiroldo.farol` (ADR 0018), English and Brazilian Portuguese.

## Consequences
- Moving to two processes before 1.0 means splitting the app: measurement and detection go to the sentinel, which adds XPC and lifecycle. The verdict rules and measurement code move as they are.
- Because a single daemon below one extra core does not start an incident (detector limitation noted in `AnomalyDetector`), a busy watched daemon is shown on the card from the daemon heartbeat (25% of a core for 20 s, ADR 0021) without opening an incident.
- The preview's own resource use has not been measured. It must be quit while the sentinel spike measures (`docs/spikes/sentinel-24h`), or the two disturb each other.
- The knowledge base texts that mention pausing describe 1.0. The preview does not show the "what you can do" line for entries offered the cause test.
