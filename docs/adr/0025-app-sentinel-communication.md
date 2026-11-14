# 0025. App–sentinel communication over XPC

- Status: Accepted; amended by ADR 0035
- Date: 2026-11-14
- Amends: 0017 ("no XPC is needed in M1")

## Context
ADR 0017 made the SQLite file the only interface between the app (read-only) and the sentinel (only writer). The first review showed that several M1 features need to reach the sentinel: deleting history (the sentinel must stop writing and recreate the files), showing an incident in progress (writes are batched), applying settings such as retention, and restarting after an update.

## Options
1. **XPC Mach service** vended by the sentinel, with the peer's code signature checked.
2. Darwin notifications (`notify_post`) plus shared files: simpler, but any process of the user can post them and there is no reply.

## Decision
- The sentinel is registered as a **launch agent** (`SMAppService.agent`) that vends one XPC Mach service.
- Both sides **verify the peer's code signature** (same Team ID and bundle identifiers) before accepting a connection; anything else is rejected.
- The interface is small and command-oriented: `version`, `flushNow`, `deleteHistory`, `settingsChanged`, `restart`. Every request has a reply and a timeout; the protocol carries a version number.
- **Live data is sampled by the app itself** through FarolCore; the sentinel never streams measurements.
- The history file remains the way the app reads the past.

## Consequences
- XPC requires both processes to be signed; development builds use a local signing identity (handled by the tooling ADR when the Xcode project is created).
- The sentinel gains the XPC listener in its footprint; part of the planned re-measurement (ADR 0019).
