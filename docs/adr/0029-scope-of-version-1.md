# 0029. Scope of version 1.0

- Status: Accepted; clarified by ADR 0030
- Date: 2026-11-14
- Supersedes: 0005 (all four milestones formed the MVP)

## Context
ADR 0005 put all four milestones in the MVP: experiments with statistics, Siri and Shortcuts, a shareable report, a bilingual knowledge base, private energy and thermal sensors, signing and CI. The first review found this too broad while the foundation is unproven — the cause test has never been validated with real apps and the budgets have not been measured. Real user feedback has already proven more valuable than planning (ADR 0020), and a long road to release delays it.

## Options
- Reduced 1.0; complete 1.0 (M1–M4); minimal 1.0 (M1 only, no cause test).
- Knowledge base: ~12, ~20 or ~50 processes.
- After 1.0: decide with feedback, energy sensors first, or experiments first.

## Decision
**Version 1.0 contains:**
- Everything in M1: the sentinel with alerts, incident history, the verdict-first window, processes and performance views, the menu bar.
- The cause test (ADRs 0022, 0023) for **two daemons: WindowServer and Spotlight (`mds_stores`)** — the classic cases of a system process working on behalf of an app — validated with real apps before release.
- Heat and battery information from **public APIs only** (thermal state, battery level and drain); no private sensors.
- A knowledge base of about **20 macOS processes**, in English and Brazilian Portuguese, in a data file the community can extend.
- Signing, notarization, CI with budget checks, Homebrew and GitHub Releases (ADR 0014).

**After 1.0**, in an order decided with user feedback: private energy and temperature sensors (former M3), experiments (former M4), Siri/Shortcuts/Spotlight entry points and the shareable report, and more daemons for the cause test.

## Consequences
- The README roadmap is rewritten around version 1.0.
- Experiments and private sensors remain designed for (history schema, isolated sensor module) but are not built before 1.0.
