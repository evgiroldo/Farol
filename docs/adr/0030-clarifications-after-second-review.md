# 0030. Clarifications after the second review

- Status: Accepted
- Date: 2026-11-14
- Amends: 0011, 0014, 0017, 0021, 0024, 0026, 0029

## Context
A second independent review (Claude Fable 5.2, 2026-11-14) of ADRs 0021–0029 checked several claims on a real Mac and found contradictions and gaps. This ADR records the corrections that need no new product decision. Open decisions from that review (suspicion state machine, cause-test statistics, what counts as "normal" macOS work, watchdog design, microphone and group refusal rules, the pause set, restart semantics, development-build signing, alert filters, test-result storage, incident caps, settings) are decided in later ADRs.

## Corrections

1. **`kernel_task` is not watchable** (amends 0021). PID 0 does not appear in `ps` output (verified); it is removed from the watch list. Thermal throttling is explained from the thermal state instead.
2. **Watch-list identity** (amends 0021). Daemons are matched by name *and* executable path under `/System` or `/usr` (`proc_pidpath`), with owner and start time from `PROC_PIDTBSDINFO` — both readable for root processes without privilege (verified). A user process named like a daemon is ignored. PIDs are rediscovered every 5 minutes and whenever a queried PID disappears. Per-user daemons owned by the current user are read with `proc_pid_rusage` instead of `ps`.
3. **How `ps` is used** (amends 0021). Only the cumulative `time` column with `pid=` (`-o pid=,time=`), never `%cpu` (a decayed average). CPU shares are deltas of cumulative time between timestamps taken around each call. `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT`, empty environment, stdin and stderr on `/dev/null`, output capped at 64 KB, a time-out, and the child always reaped. Output is untrusted text.
4. **Idle mode includes the 60-second ring** (amends 0011, which said idle reads global counters only). A full per-process snapshot costs about 1.4 ms of CPU (measured), so the top-20 sample every 10 s adds about 0.014% of a core and is part of the idle budget.
5. **Self-measurement counts child processes.** Farol's own CPU cost always includes `ps` children.
6. **One set of budget numbers** (amends 0014). The values in ADR 0014 (0.3% / 30 MB) are retired; the README table is the single source and stays provisional until the real sentinel is measured (ADR 0028).
7. **"Launch agent" everywhere** (amends 0011, 0017, 0026). The sentinel is registered with `SMAppService.agent` (ADR 0025); "login item" in earlier ADRs means this launch agent and its states.
8. **Alert examples must be possible** (amends 0024). A named-app alert states only the duration measured so far — after the 2-minute threshold it reads "for 2 minutes", not "for 10 minutes".
9. **Durations are typical, never predicted.** Explanations may quote typical durations from the knowledge base, labeled as typical ("often takes from minutes to a few hours"); Farol never states when a specific task will end. The README example is corrected.
10. **App names from bundles are untrusted.** Display names are sanitized like process names and capped at 64 characters; when a name matches an Apple app but the code is not Apple-signed, Farol also shows the developer or path.
11. **The responsible-process function** (clarifies 0027 and 0029) is `responsibility_get_pid_responsible_for_pid`; it works without root for the user's own processes (verified) and returns an error for other users' processes. The isolated private-sensor module ships in 1.0 with this one function; energy and temperature sensors stay after 1.0.
12. **Other user accounts.** When load is unexplained and another user session is active, Farol says it cannot see that account's apps and offers no cause test.
13. **No runtime bypass of the XPC peer check** (amends 0025). However development builds are signed, the check is never disabled by a runtime switch; the exact mechanism is decided with the Xcode project.
