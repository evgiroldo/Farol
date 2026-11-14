# 0018. Bundle identifier, history store and retention

- Status: Accepted; amended by ADR 0019
- Date: 2026-11-14

## Decision

### Bundle identifier
`io.github.evgiroldo.farol` (app) and `io.github.evgiroldo.farol.sentinel` (sentinel). The project has no domain of its own; the GitHub Pages convention avoids squatting on someone else's domain.

### History store: SQLite
SQLite ships with macOS, so it keeps the zero-dependency rule (ADR 0014). It is crash-safe, battle-tested and queryable, which M2 (suspect ranking) and M4 (experiments) need.
- Rejected: custom binary files (smaller and faster, but much more code to maintain and audit) and SwiftData (too heavy for the sentinel budget).
- WAL journal mode; batched writes; `secure_delete` on, so "Delete history" overwrites data.
- Database directory `0700`, file `0600` (ADR 0013).

### Sampling (validated by the sentinel spike)
- Idle: global counters every 2 s.
- Incident: per-process sampling at 1 Hz.

### Retention
**7 days** by default for both aggregates and incident details, configurable in settings.
