# 0017. Two processes: sentinel and app

- Status: Accepted (amends the "one process" part of ADR 0011)
- Date: 2026-11-14

## Context
ADR 0011 placed the always-on sentinel in the menu bar item, in a single process with the main window. A SwiftUI window loaded into that process grows its memory footprint, and the footprint does not fully shrink after the window closes. The sentinel would leave its 15 MB budget after the first use of the window.

## Options
1. One process: simpler, but the sentinel budget cannot be guaranteed.
2. Two processes: a tiny AppKit-only **sentinel** (menu bar item, login item, records history) and the **Farol app** (SwiftUI, launched on demand, reads history, terminates when closed).

## Decision
Option 2. To the user it still feels like one app: the menu bar item opens the Farol window.
- The sentinel is the only writer of the history database; the app reads it.
- Pausing a process for a proof (ADR 0010) is done by the app, only while the user is present.

## Consequences
- Two targets, two code signatures; the sentinel is embedded in the app bundle and registered with `SMAppService` as a login item.
- No XPC is needed in M1: the shared SQLite file is the interface. If live data from the sentinel becomes necessary, a new ADR decides how.
