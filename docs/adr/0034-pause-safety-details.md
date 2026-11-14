# 0034. Pause safety details

- Status: Accepted
- Date: 2026-11-15
- Amends: 0023 (watchdog, protections), 0027 (what "whole app" pauses)

## Decision
1. **Watchdog.**
   - The app keeps a pipe open to the watchdog; if the pipe closes (app crashed or quit), the watchdog **resumes everything at once**. The deadline is only a second guard.
   - The first `SIGSTOP` is sent only after the watchdog **acknowledges** it is running; the list of paused processes is sent to it **before** each new `SIGSTOP`.
   - The watchdog ignores `SIGHUP`, `SIGTERM` and `SIGINT` and uses a monotonic clock.
   - If both the app and the watchdog die, the next time Farol opens it looks for the user's stopped processes (not in a terminal, not traced) and offers "X appears frozen — resume it?". This uses live process state only, never the history file. SECURITY.md documents the residual risk.
2. **Calls and protected processes (conservative).**
   - **No cause test runs while any process on the Mac has microphone input running.**
   - If the app is playing audio, the confirmation adds: "If you're in a call, it may be interrupted."
   - If **any** process of the app's group is protected (ADR 0023), the whole test is refused and Farol says why; it never pauses part of an app.
3. **What "the whole app" means.** Only executables **inside the app's own bundle**, plus Apple-signed browser helpers (WebKit) that belong to it. Builds, servers and scripts the app started are not paused; if the group contains executables from outside the bundle, the test is refused. The confirmation shows how many processes will be paused.
