# 0045. Work Farol cannot see directly

- Status: Accepted
- Date: 2026-11-18
- Amends: 0044 (preview version 0.1)

## Context
Run 6 of the sentinel spike (`docs/spikes/sentinel-24h/results-run6.md`) recorded a 5-minute slowdown with about 2.1 busy cores, while the processes the sampler could read accounted for less than 3% of that work. `proc_pid_rusage` fails for processes of other users: root, the `_`-prefixed system users and any other account logged in on the Mac (fast user switching). In that case the 0.1 card says only "Your Mac is busy… none of them stands out".

`proc_pidpath` works for those processes, and Apple's setuid `/bin/ps` reads their cumulative CPU time. Listing every process with `ps -axo pid=,uid=,time=` takes about 10–20 ms and produces about 30 KB (measured on the maintainer's Mac, about 1,250 processes).

Options considered: **A** state the share of the work Farol cannot attribute; **B** during a slowdown, read every process through `ps` to name the work; **A + B** (chosen).

## Decision
1. **Full list during a slowdown only (B).** While an incident is open, the monitor runs `/bin/ps -axo pid=,uid=,time=` every 10 s, with the same rules as the daemon heartbeat (ADR 0021): `posix_spawn`, absolute path, fixed arguments, no shell, empty environment. Output is capped at 256 KB and parsed as untrusted text. The first reading of an incident only sets the starting point. Nothing is read this way while the Mac is calm.
2. **Only the processes Farol cannot read.** Processes of the user running Farol come from the sampler as before. For the others, the CPU time between two readings is attributed with the executable path (`proc_pidpath`):
   - a knowledge base match becomes system work, as today;
   - a process in another regular account (UID 501 or above, not the current user) is grouped by its outermost `.app` bundle (ADR 0027) and marked **another account**;
   - any other process (root and system users) is grouped the same way and marked **macOS**.
   Their memory is not known and is shown as unavailable.
3. **Privacy.** Farol never shows another account's name or UID. It shows only the app or process name and the words "another account on this Mac". Any local user can already see those names with `ps`.
4. **The unseen share (A).** At each snapshot the monitor compares the Mac's busy cores over the window with the sum of everything it attributed. When the difference reaches `Verdict.suspectCores` (0.5 core) and is larger than any named cause, the cause is **unseen work**: "Something Farol can't see is using about *N* cores. It is probably macOS or another account on this Mac." The value is labelled *estimated*.
5. **Verdict order.** After heat and memory, the cause is the largest of: a system process (at least 0.25 core), an app of any account (at least 0.5 core) and unseen work (at least 0.5 core).
6. **Farol never acts on these processes.** They are read only. The pausing features of 1.0 are not affected by this ADR.

## Consequences
- A slowdown caused by another account or by an unlisted macOS process gets a name about 10 s after it starts, instead of "nothing stands out".
- An incident costs one more `ps` call every 10 s (about 10–20 ms each, estimated from the listing above). Calm periods cost nothing more.
- The sum of attributed work and the busy cores come from different counters read at slightly different times, so small differences are noise. That is why the unseen share must reach 0.5 core.
- Run 6 suggests the unattributed share can be large on a Mac with two accounts logged in. Whether it is common elsewhere is unknown.
