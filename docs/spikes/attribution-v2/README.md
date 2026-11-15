# Attribution spike v2

Throwaway validation prototype for the cause test (ADR 0022, 0033, 0034). **Not Farol code** — never copy it into the app.
It re-runs the first attribution spike (`../attribution/`) with the statistics and safety rules the second review asked for.

**Before running anything, read [`RUN.md`](RUN.md).**

## Questions it answers

1. **Calibration** — how large must effect ÷ fluctuation be so that a test with no real cause is called "proven" less than 1% of the time (and "likely" less than 5%)? Answered with *sham tests*: the exact protocol window slid over recordings in which nothing was paused.
2. **Real tests with known ground truth** — does the full protocol, with the watchdog, find the real culprit (a WebKit window for WindowServer, a file writer for Spotlight) and clear the decoys? How long does each daemon take to react (lag)?
3. **Occlusion** — does putting Farol's small test panel (or a whole window) over the culprit hide the WindowServer load?
4. **Cost** — how much CPU does the measuring itself use, `ps` children included?

## Build

```bash
./build.sh        # swiftc only, no dependencies; output in ./build (ignored by git)
```

Requires the Swift toolchain, Apple silicon, macOS 26 or later.

## Subcommands (`build/attrib2 <subcommand>`)

| Subcommand | What it does | Opens windows | Pauses anything | Default duration |
|---|---|---|---|---|
| `all` | Everything below in order: safety check → idle recording (3 min) → start load → recording under steady load (12 min) → 20 real tests → occlusion → recording under pulsed load (8 min) → 12 real tests → analysis. Writes `data/<time>/results.md` | yes | only its own processes | about 52 min |
| `record` | Records cumulative CPU time of WindowServer and mds_stores once per second through `/bin/ps` (`posix_spawn`, ADR 0030 §3). Passive by default. `--seconds N`, `--interval S`, `--label NAME`; `--load steady` or `--load pulsed:4,3` adds the spike's own load | only with `--load` | no | 15 min |
| `analyze [folder]` | Offline. Sham-test calibration of every `record-*.csv`, verdicts for every real test with the calibrated thresholds, lag, occlusion and cost tables → `results.md` plus `calibration.csv`, `sham-*.csv`, `test-results.csv`. Default folder: the latest in `data/` | no | no | seconds |
| `test` | Real cause tests only: safety check, start load, then the ADR 0033 protocol `--n` times per target (`--targets web,writer,burn-sync,burn-random`, `--rhythm steady` or `pulsed:4,3`), then analysis | yes | only its own processes | about 10 min for `--n 3` |
| `occlusion` | WindowServer load with the culprit window visible / under a small static panel / fully covered, interleaved `--reps` times for `--seconds` each | yes | no | about 5 min |
| `safety-check` | Starts a CPU burner, pauses it from a stand-in main process that then dies (and, second pass, hangs), and checks the watchdog resumed it. Runs automatically before any pause test; if it fails, no pause test runs | no | one burner it starts | 15 s |
| `probe` | Read-only look: daemon PIDs, whether the responsibility function is available, current WebKit helpers and who is responsible for them | no | no | 1 s |
| `selftest` | Analyses synthetic data with a known answer, to check the arithmetic | no | no | under 1 s |

Every run prints its exact start and end time and writes `phases.csv`, so the window can be excluded from other measurements.

## What is in a data folder

| File | Content |
|---|---|
| `results.md` | The summary (generated; re-create with `analyze`) |
| `record-<label>.csv` | Raw recording: wall time, monotonic time before/after each `ps` call, cumulative CPU seconds per daemon |
| `sham-<label>-<daemon>.csv`, `calibration.csv` | Every sham test and the calibration table |
| `tests.csv`, `trace-<test>.csv` | One line per real test (targets, exact stop/resume times, status) and its 0.25 s trace |
| `test-results.csv` | Effect, ratio, share range and verdict per test and daemon |
| `helpers.csv` | Processes found in the web app's group at each web test: path, parent, responsible PID, kind |
| `occlusion.csv`, `cost.csv`, `phases.csv`, `notes.txt` | Occlusion runs, the spike's own CPU, phase times, notes written during the run |
| `web-status-N.csv` | Written by the test window itself once per second: animation callbacks per second, whether macOS reports the window visible |
| `watchdog.log`, `children.log` | Logs of the watchdog and of the spike's child processes |

## How it is built

One binary. `attrib2` starts copies of itself in internal roles: `_watchdog`, `_webapp` (inside `build/FarolSpikeWeb.app`, an AppKit window with a `WKWebView` showing `stimulus.html`), `_writer`, `_burn`, `_cover`, `_idle`, `_crashmain`.

| Source | Role |
|---|---|
| `Sources/Safety.swift` | **Every signal the spike sends** (search for `SIGNAL SITE`), the watchdog process and its client, identity checks, cleanup on abort |
| `Sources/Common.swift` | Clocks, process identity, `posix_spawn`, `/bin/ps` query and parsing, self-cost |
| `Sources/Stats.swift` | The protocol arithmetic used for both sham and real tests; calibration; lag |
| `Sources/Runner.swift` | Recording, starting the load, group discovery, real tests, occlusion, safety check, probe |
| `Sources/Analyze.swift` | Offline analysis and `results.md` |
| `Sources/Stimuli.swift`, `Sources/WebApp.swift`, `stimulus.html` | Load generators and windows |

## Safety design (ADR 0023, 0034)

- `SIGSTOP` is sent in exactly one place (`pauseGroup`). Targets are processes the spike started itself, plus Apple-signed WebKit helpers that macOS holds the spike's own test app responsible for.
- Before and after every `SIGSTOP`: PID, start time, executable path and owner are compared with what was recorded at launch or discovery; on a mismatch everything is resumed at once and the test is aborted. Processes that are already stopped, traced or attached to a terminal are refused.
- The watchdog is a separate process in its own session. It ignores `SIGHUP`, `SIGTERM` and `SIGINT`, uses a monotonic clock, receives the list and acknowledges **before** each stop, resumes everything when its pipe closes (the spike died) or a 5-second deadline passes (the spike hung).
- Every load generator holds a "lifeline" pipe and exits by itself when the spike disappears; the writer deletes its files on the way out.

## Definitions the ADRs leave open (stated again in every `results.md`)

- Fluctuation: sample standard deviation (n−1) of the six observation windows, floored at one `ps` tick per window (0.33% of a core).
- Effect of a cycle: mean of the run windows before and after the pause, minus the pause window. Effect of a test: mean of the three cycles. Ratio: effect ÷ fluctuation.
- "Proven": lower in every pause than in the run before it, higher in every run after it, and ratio above the calibrated threshold. "Likely": every cycle's effect positive and ratio above the second threshold. Calibrated thresholds are never applied below the ADR 0022 starting values (3× and 2×).
- The protocol as specified lasts 36 s (18 s + 3 × 6 s); ADR 0033 says "about 42 seconds".
