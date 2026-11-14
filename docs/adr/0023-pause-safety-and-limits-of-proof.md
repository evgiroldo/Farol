# 0023. Pause safety and the limits of proof

- Status: Accepted; amended by ADR 0034
- Date: 2026-11-14
- Amends: 0010 (protected list and watchdog), 0003 (which symptoms are provable)

## Context
The first review found that the pause-based test covers fewer diagnoses than the README implied, and that the safety rules of ADR 0010 were partly unimplementable: the watchdog had no owner, and "apps in a call or downloading" cannot be detected reliably. It also found unprotected cases: processes attached to a terminal, processes the user had already stopped, processes under a debugger, and identity races between confirmation and signal.

## Decision

### What can be proven and what is only explained
| Situation | What Farol does |
|---|---|
| An app itself uses a lot of CPU | Measures it directly; no test needed |
| A system process works on behalf of an app (WindowServer, Spotlight…) | Offers the cause test (ADR 0022) |
| Heat / thermal throttling | Explains (thermal time constants are minutes, a 3 s pause shows nothing) |
| Low memory / swapping | Explains (pausing an app frees no memory) |
| Full disk | Explains and shows what uses the space |
| Work done by macOS itself (indexing after an update, backups) | Explains: what it is, whether it is normal, how long it usually takes |

### Watchdog
Before pausing, the app starts a **small, separate watchdog process** (a signed helper inside the app bundle, started with `posix_spawn` in its own session so it survives the app). It receives the list of paused processes (PID, start time, executable path) and a deadline. At the deadline it resumes (`SIGCONT`) every listed process that still matches its identity and is still stopped, then exits. The app resumes processes normally; the watchdog is the guarantee if the app crashes or hangs.

### Never paused (only conditions Farol can verify)
- Processes **using the microphone** (CoreAudio process objects; a sign of a call or recording).
- Processes **attached to a terminal** (controlling TTY): stopping them breaks the shell's job control.
- Processes **already stopped** — Farol would wake something the user paused on purpose.
- Processes **being traced or debugged**.
- **Finder, Dock and macOS components**, identified by executable path and code-signing identity, never by name.
- Farol itself and its helpers; anything not owned by the current user; PIDs ≤ 1.

What cannot be verified (network transfers, camera use) becomes a **warning** in the confirmation text: "If this app is downloading or uploading something, it may be interrupted."

### The app the user was using
Allowed. It is the most likely cause; while the test runs, Farol's own window is in front. The confirmation names the app and says plainly that it will freeze three times for 3 seconds.

### Identity checks
- The pause code accepts only a **live identity** created by the sampler moments before, never one read from the history file.
- Immediately before and after each `SIGSTOP`, Farol re-checks PID, start time, owner, executable path and the protection rules; on any mismatch it resumes at once and aborts the test.
- macOS has no race-free process handle (no pidfd), so a very small window between check and signal remains; this is documented in SECURITY.md.

## Consequences
- An extra signed executable (the watchdog) ships inside the app bundle and must be covered by tests that kill the app mid-test.
- Some suspects cannot be tested (a call app using the microphone, a command running in Terminal); Farol says why instead of silently skipping them.
