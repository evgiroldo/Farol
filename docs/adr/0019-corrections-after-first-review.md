# 0019. Corrections after the first independent review

- Status: Accepted
- Date: 2026-11-14
- Amends: 0000, 0006, 0008, 0010, 0011, 0013, 0014, 0018

## Context
An independent architecture review and a security audit of the ADRs and `FarolCore` (both run with Claude Fable 5.2, 2026-11-14) found defects, over-claims and contradictions. Security defects were reproduced by the auditor. This ADR records the corrections that need no new product decision. Open architecture questions (detector design, proof protocol, alerts wording, IPC, versioning, process grouping, budgets, MVP scope) are decided in later ADRs.

## Corrections

### Evidence and labels (amends 0010)
- The WindowServer spike result (−63%) is **not evidence**: WindowServer averaged 0.6% CPU, the baseline varied more between runs than the "effect", `ps` resolution is 10 ms, and the decoy was measured without load. The mds_stores result (−99%) is stronger but is a single trial. Both are now described as *feasibility signals*, not proof.
- A pause result is labeled **inferred (with confidence)**, never *measured*: it is a statistical conclusion from a short experiment.
- `ProcessIdentity` (pid + wall-clock start time) does not change across `execve`. Code that acts on a process must re-verify path, owner and identity immediately before and after acting, and must never act on an identity read back from the history file. macOS has no pidfd, so a small race remains and is documented.

### History store (amends 0013, 0018)
- "Delete history" closes the database and removes the database, WAL and shared-memory files, then starts an empty one. The promise is: **the data is removed from Farol's files**. It is not promised that the data is gone from APFS snapshots or backups made earlier. The history directory is excluded from backups.
- Writes run in transactions that always roll back on error; a busy timeout is set; the WAL is truncated after each purge.
- The file is readable and writable by every process running as the same user; permissions only keep other accounts out. Everything read back is treated as **untrusted input**: invalid rows are skipped, reads are bounded, the schema is not trusted (`trusted_schema=OFF`), and the schema version is checked on every open, refusing newer versions.
- Files are opened without following symlinks and must be owned by the user; the reader refuses files other users can access.
- Incidents left open by a crash or reboot are closed as *interrupted* when the sentinel starts. Incident IDs are never reused; process rows are deleted with their incident.

### Honest readings (amends 0008)
- Undocumented sysctls count as private APIs. Memory pressure now comes from the public `DispatchSource` memory-pressure events and is **unavailable** until the first event, never assumed normal.
- First-seen processes whose baseline is unknown produce no delta, so lifetime totals never appear as a burst.
- Swapping is a sustained rate (default 1 MB/s), not any single swapout. The burst after wake from sleep is suppressed.

### UI (amends 0006)
- The menu bar item belongs to the AppKit sentinel (ADR 0017), not SwiftUI.
- **Swift Charts is allowed** until profiling shows it is too expensive; custom `Canvas` charts are used only where measurement justifies them.

### Budgets and CI (amends 0011, 0014)
- No CI exists yet; the README says budgets *will be* enforced.
- The budgets in ADRs 0011 and 0014 are **targets pending re-measurement** with the real sentinel (SQLite, daemon reads, notifications). One table in the README is the single source of truth.
- CI will gate on deterministic proxies (own CPU time from `proc_pid_rusage`, wakeups, `phys_footprint` after a scripted scenario, against a stored baseline with tolerance). Absolute budgets are a release gate on real hardware. Wall-clock timing tests are only coarse guards.
- CI will also check that no networking symbols (URLSession, Network.framework, sockets) are linked, to enforce ADR 0009.
- `utility` QoS *prefers* efficiency cores; only `background` QoS is restricted to them. Wording fixed.

### ADR process (amends 0000)
- An accepted ADR's content is never edited; only its **Status** line may change, to point to the ADR that amends or supersedes it.
