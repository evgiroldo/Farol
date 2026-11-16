# Attribution spike v2 — results

Generated 2026-11-16 19:23:12.902 +0100 from the raw CSV files in this folder by `attrib2 analyze`. One Mac (Mac17,3, macOS 27.2.1, 10 cores), synthetic culprits started by the spike. Feasibility evidence, not guaranteed accuracy.

Labels: **measured** = read from `ps`/the kernel; **inferred** = computed from measured values by the stated rule.

## When it ran (exclude these windows from other measurements)

| phase | start | end |
|---|---|---|
| safety-check | 2026-11-16 19:06:03.420 +0100 | 2026-11-16 19:06:08.382 +0100 |
| record-idle | 2026-11-16 19:06:08.382 +0100 | 2026-11-16 19:07:08.400 +0100 |
| start-load-steady | 2026-11-16 19:07:08.400 +0100 | 2026-11-16 19:08:18.092 +0100 |
| record-loaded-steady | 2026-11-16 19:08:18.092 +0100 | 2026-11-16 19:11:18.103 +0100 |
| tests-steady | 2026-11-16 19:11:18.103 +0100 | 2026-11-16 19:19:40.044 +0100 |
| occlusion | 2026-11-16 19:19:40.044 +0100 | 2026-11-16 19:20:04.177 +0100 |
| restart-load-pulsed | 2026-11-16 19:20:04.177 +0100 | 2026-11-16 19:20:25.486 +0100 |
| record-loaded-pulsed | 2026-11-16 19:20:25.487 +0100 | 2026-11-16 19:20:25.492 +0100 |
| tests-pulsed | 2026-11-16 19:20:25.492 +0100 | 2026-11-16 19:23:12.871 +0100 |
| stop-load | 2026-11-16 19:23:12.871 +0100 | 2026-11-16 19:23:12.901 +0100 |

## 1. Calibration of the cause-test thresholds (sham tests, nothing paused)

Method: the exact ADR 0033 window (six 3 s observation windows, then 3 × 3 s "pause" / 3 s "run", all from cumulative `ps` time at window endpoints) is slid over each no-pause recording, one start per sample. Nothing was paused, so every "proven" is false. Definitions: fluctuation = sample standard deviation (n−1) of the six observation windows, floored at one `ps` tick per window (0.33% of a core); effect = mean over the 3 cycles of (mean of the run windows before and after − the pause window); ratio = effect / fluctuation; *strict pattern* = lower in every pause than the run before it and higher in every run after it; *same direction* = each cycle's effect is positive. "Eligible" = observation mean ≥ 10% of a core (ADR 0022 §3: only then is a test offered).

**How much evidence this is.** Overlapping sham tests share most of their data, so the honest sample size is closer to the *non-overlapping* count. With N independent tests and zero false proofs, the true rate is only shown to be below about 3/N (95%).

| recording | daemon | sham tests | overlapping N | non-overlapping N | median load | strict pattern by chance | ratio p50 | p95 | p99 | max | threshold proven (<1%) | threshold likely (<5%) | false proven at 3× / false likely at 2× |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| idle | WindowServer | all | 25 | 1 | 0.5% | 0.0% | 0.17 | 0.83 | 1.17 | 1.17 | 0.00 | 0.83 | 0.0% / 0.0% |
| idle | WindowServer | eligible | 0 | 0 | – | – | – | – | – | – | – | – | – |
| idle | mds_stores | all | 25 | 1 | 0.5% | 0.0% | -0.13 | 0.58 | 0.65 | 0.65 | 0.00 | 0.58 | 0.0% / 0.0% |
| idle | mds_stores | eligible | 0 | 0 | – | – | – | – | – | – | – | – | – |
| loaded-steady | WindowServer | all | 145 | 5 | 42.7% | 3.4% | -0.00 | 1.15 | 1.63 | 1.96 | 1.63 | 1.15 | 0.0% / 0.0% |
| loaded-steady | WindowServer | eligible | 145 | 5 | 42.7% | 3.4% | -0.00 | 1.15 | 1.63 | 1.96 | 1.63 | 1.15 | 0.0% / 0.0% |
| loaded-steady | mds_stores | all | 145 | 5 | 23.2% | 0.0% | 0.00 | 0.79 | 1.39 | 1.50 | 0.00 | 0.79 | 0.0% / 0.0% |
| loaded-steady | mds_stores | eligible | 145 | 5 | 23.2% | 0.0% | 0.00 | 0.79 | 1.39 | 1.50 | 0.00 | 0.79 | 0.0% / 0.0% |
| POOLED (recordings under load) | WindowServer | eligible | 145 | 5 | 42.7% | 3.4% | -0.00 | 1.15 | 1.63 | 1.96 | 1.63 | 1.15 | 0.0% / 0.0% |
| POOLED (recordings under load) | mds_stores | eligible | 145 | 5 | 23.2% | 0.0% | 0.00 | 0.79 | 1.39 | 1.50 | 0.00 | 0.79 | 0.0% / 0.0% |

Thresholds are the smallest ratio T such that fewer than 1% of sham tests satisfy *strict pattern and ratio > T* (proven), and fewer than 5% satisfy *same direction and ratio > T* (likely). A threshold of 0.00 means the pattern rule alone already kept the rate below the limit in that recording. Pattern-free thresholds and all quantiles are in `calibration.csv`; every sham test is in `sham-*.csv`.

**Thresholds used for the verdicts below** (*inferred*):

- WindowServer: proven > **3.00×**, likely > **2.00×** — 145 overlapping eligible sham tests (5 non-overlapping) from recordings under load; calibrated values 1.63 (proven, <1%) and 1.15 (likely, <5%), floored at the ADR 0022 values 3 and 2.
- mds_stores: proven > **3.00×**, likely > **2.00×** — 145 overlapping eligible sham tests (5 non-overlapping) from recordings under load; calibrated values 0.00 (proven, <1%) and 0.79 (likely, <5%), floored at the ADR 0022 values 3 and 2.

## 2. Real cause tests with known ground truth

All four stimuli run at the same time (web app, writer, and two CPU-only decoys); each test pauses one of them with the full protocol and a watchdog. Ground truth: pausing `web` should lower WindowServer, pausing `writer` should lower mds_stores; every other pairing is a real pause with **no** known cause. "Offered" = observation mean ≥ 10% of a core. Shares are *inferred*: "in three tries, between X% and Y%".

### Per condition

| rhythm | paused | daemon | truth | tests | offered (≥10%) | median load | median fluctuation | median effect | median ratio | proven / likely / inconclusive | same, windows shifted by lag | share range over all tries |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pulsed:4/3 | burn-random | WindowServer | no cause | 1 | 1 | 22.6% | 14.4% | -26.2% | -1.82 | 0 / 0 / 1 | 0 / 0 / 1 | – |
| pulsed:4/3 | burn-random | mds_stores | no cause | 1 | 0 | 9.6% | 18.4% | -33.4% | -1.82 | 0 / 0 / 1 | 0 / 0 / 1 | – |
| pulsed:4/3 | burn-sync | WindowServer | no cause | 1 | 1 | 23.3% | 14.6% | -27.2% | -1.86 | 0 / 0 / 1 | 0 / 0 / 1 | – |
| pulsed:4/3 | burn-sync | mds_stores | no cause | 1 | 1 | 10.8% | 23.7% | 2.1% | 0.09 | 0 / 0 / 1 | 0 / 0 / 1 | – |
| pulsed:4/3 | web | WindowServer | **cause** | 1 | 1 | 23.9% | 15.3% | 11.5% | 0.75 | 0 / 0 / 1 | 0 / 0 / 1 | 90.7%–94.3% |
| pulsed:4/3 | web | mds_stores | no cause | 1 | 0 | 9.0% | 13.6% | 20.3% | 1.50 | 0 / 0 / 1 | 0 / 0 / 1 | – |
| pulsed:4/3 | writer | WindowServer | no cause | 1 | 1 | 23.2% | 14.5% | -25.6% | -1.76 | 0 / 0 / 1 | 0 / 0 / 1 | – |
| pulsed:4/3 | writer | mds_stores | **cause** | 1 | 1 | 19.0% | 24.9% | -6.6% | -0.26 | 0 / 0 / 1 | 0 / 0 / 1 | -1190.9%–100.0% |
| steady | burn-random | WindowServer | no cause | 3 | 3 | 44.1% | 0.4% | 0.3% | 0.84 | 0 / 0 / 3 | 0 / 0 / 3 | – |
| steady | burn-random | mds_stores | no cause | 3 | 3 | 22.6% | 30.0% | -2.4% | -0.09 | 0 / 0 / 3 | 0 / 0 / 3 | – |
| steady | burn-sync | WindowServer | no cause | 3 | 3 | 41.5% | 0.4% | -1.3% | -3.33 | 0 / 0 / 3 | 0 / 0 / 3 | – |
| steady | burn-sync | mds_stores | no cause | 3 | 3 | 20.8% | 24.6% | 8.4% | 0.35 | 0 / 0 / 3 | 0 / 0 / 3 | – |
| steady | web | WindowServer | **cause** | 3 | 3 | 43.1% | 0.4% | 41.7% | 115.12 | 3 / 0 / 0 | 3 / 0 / 0 | 97.3%–98.3% |
| steady | web | mds_stores | no cause | 3 | 3 | 22.7% | 25.8% | 23.0% | 0.88 | 0 / 0 / 3 | 0 / 0 / 3 | – |
| steady | writer | WindowServer | no cause | 3 | 3 | 41.0% | 0.3% | -0.1% | -0.36 | 0 / 0 / 3 | 0 / 0 / 3 | – |
| steady | writer | mds_stores | **cause** | 3 | 3 | 22.1% | 24.8% | 12.2% | 0.47 | 0 / 0 / 3 | 0 / 0 / 3 | -1212.7%–100.0% |

### Headline counts (*inferred* verdicts on *measured* data)

- Real cause, test offered (load ≥ 10%): **3 proven, 0 likely, 5 inconclusive** out of 8 (all 8 real-cause tests regardless of load: 3 / 0 / 5).
- No cause (decoys, and culprits measured against the other daemon), test offered: **0 wrongly proven, 0 wrongly likely** out of 22 (all 24 regardless of load: 0 / 0 / 24).
- With these few tests, a count of zero only bounds the true rate below about 3/N.

### Every test

| test | daemon | truth | load | fluctuation | effect | ratio | strict | share range (3 tries) | verdict | ratio / verdict with lag shift |
|---|---|---|---|---|---|---|---|---|---|---|
| steady-web-1 | WindowServer | cause | 42.9% | 0.3% | 41.7% | 125.17 | yes | 97.3%–98.1% | proven | – |
| steady-web-1 | mds_stores | no cause | 24.5% | 25.8% | 23.0% | 0.89 | no | -11.7%–94.2% | inconclusive | – |
| steady-writer-1 | WindowServer | no cause | 41.0% | 0.3% | -0.1% | -0.36 | no | -0.8%–0.3% | inconclusive | – |
| steady-writer-1 | mds_stores | cause | 21.1% | 23.8% | 4.1% | 0.17 | no | -607.6%–99.9% | inconclusive | – |
| steady-burn-sync-1 | WindowServer | no cause | 41.5% | 0.4% | -3.3% | -7.81 | no | -9.9%–-5.9% | inconclusive | – |
| steady-burn-sync-1 | mds_stores | no cause | 20.8% | 25.3% | 22.1% | 0.87 | no | 34.9%–95.1% | inconclusive | – |
| steady-burn-random-1 | WindowServer | no cause | 44.1% | 0.4% | 0.4% | 1.04 | yes | 0.5%–1.2% | inconclusive | – |
| steady-burn-random-1 | mds_stores | no cause | 23.6% | 30.0% | 26.5% | 0.88 | no | 8.3%–97.3% | inconclusive | – |
| steady-web-2 | WindowServer | cause | 43.1% | 0.5% | 41.3% | 89.16 | yes | 98.0%–98.3% | proven | – |
| steady-web-2 | mds_stores | no cause | 21.0% | 19.5% | 11.5% | 0.59 | no | -26.3%–94.7% | inconclusive | – |
| steady-writer-2 | WindowServer | no cause | 40.7% | 0.3% | 0.3% | 0.92 | no | 0.3%–1.3% | inconclusive | – |
| steady-writer-2 | mds_stores | cause | 22.1% | 25.8% | 12.2% | 0.47 | no | -1212.7%–100.0% | inconclusive | – |
| steady-burn-sync-2 | WindowServer | no cause | 41.0% | 0.4% | -1.0% | -2.57 | no | -5.0%–-0.2% | inconclusive | – |
| steady-burn-sync-2 | mds_stores | no cause | 18.3% | 23.9% | 8.4% | 0.35 | no | -136.9%–94.8% | inconclusive | – |
| steady-burn-random-2 | WindowServer | no cause | 43.6% | 0.6% | -0.3% | -0.41 | no | -1.3%–0.8% | inconclusive | – |
| steady-burn-random-2 | mds_stores | no cause | 20.3% | 28.1% | -2.4% | -0.09 | no | -438.3%–95.2% | inconclusive | – |
| steady-web-3 | WindowServer | cause | 44.1% | 0.4% | 42.1% | 115.12 | yes | 98.0%–98.1% | proven | – |
| steady-web-3 | mds_stores | no cause | 22.7% | 32.2% | 28.4% | 0.88 | no | 42.5%–94.5% | inconclusive | – |
| steady-writer-3 | WindowServer | no cause | 41.2% | 0.3% | -0.3% | -1.04 | no | -2.1%–0.2% | inconclusive | – |
| steady-writer-3 | mds_stores | cause | 25.4% | 24.8% | 35.3% | 1.42 | yes | 99.1%–100.0% | inconclusive | – |
| steady-burn-sync-3 | WindowServer | no cause | 41.5% | 0.4% | -1.3% | -3.33 | no | -5.0%–-1.2% | inconclusive | – |
| steady-burn-sync-3 | mds_stores | no cause | 25.6% | 24.6% | -23.5% | -0.96 | no | -2877.8%–93.6% | inconclusive | – |
| steady-burn-random-3 | WindowServer | no cause | 44.1% | 0.3% | 0.3% | 0.84 | no | 0.1%–1.1% | inconclusive | – |
| steady-burn-random-3 | mds_stores | no cause | 22.6% | 31.5% | -5.8% | -0.18 | no | -1132.5%–96.0% | inconclusive | – |
| pulsed-web-1 | WindowServer | cause | 23.9% | 15.3% | 11.5% | 0.75 | yes | 90.7%–94.3% | inconclusive | – |
| pulsed-web-1 | mds_stores | no cause | 9.0% (below 10%) | 13.6% | 20.3% | 1.50 | no | 74.7%–90.4% | inconclusive | – |
| pulsed-writer-1 | WindowServer | no cause | 23.2% | 14.5% | -25.6% | -1.76 | no | -430.6%–-109.3% | inconclusive | – |
| pulsed-writer-1 | mds_stores | cause | 19.0% | 24.9% | -6.6% | -0.26 | no | -1190.9%–100.0% | inconclusive | – |
| pulsed-burn-sync-1 | WindowServer | no cause | 23.3% | 14.6% | -27.2% | -1.86 | no | -495.8%–-121.9% | inconclusive | – |
| pulsed-burn-sync-1 | mds_stores | no cause | 10.8% | 23.7% | 2.1% | 0.09 | no | -24.9%–85.5% | inconclusive | – |
| pulsed-burn-random-1 | WindowServer | no cause | 22.6% | 14.4% | -26.2% | -1.82 | no | -446.0%–-77.6% | inconclusive | – |
| pulsed-burn-random-1 | mds_stores | no cause | 9.6% (below 10%) | 18.4% | -33.4% | -1.82 | no | -7024.0%–-418.1% | inconclusive | – |

### Lag per daemon (ADR 0033 §5)

**WindowServer** when its culprit (`web`) is paused — 4 tests × 3 cycles, 0.25 s bins (*measured* shares, *inferred* lag):

- share while running (last second before the next pause): 34.4%; while paused (last second of the pause): 0.7%
- after SIGSTOP, share per 0.25 s bin: 3 0 0 0 1 0 0 1 1 1 1 1 (%)
- after SIGCONT, share per 0.25 s bin: 42 35 35 35 35 32 32 32 33 35 35 35 (%)
- **lag to drop: the first bin at or below the midpoint starts 0.00 s after the pause; lag to recover: 0.00 s after the resume** (resolution 0.25 s; `ps` time has 10 ms steps)
- per-test spread: drop 0.00–0.00 s (median 0.00), recover 0.00–0.00 s (median 0.00) — 4 of 4 tests had a clear step

**mds_stores** when its culprit (`writer`) is paused — 4 tests × 3 cycles, 0.25 s bins (*measured* shares, *inferred* lag):

- share while running (last second before the next pause): 31.5%; while paused (last second of the pause): 6.6%
- after SIGSTOP, share per 0.25 s bin: 4 32 17 9 0 0 0 0 1 0 0 25 (%)
- after SIGCONT, share per 0.25 s bin: 4 4 4 3 7 28 36 13 47 6 37 36 (%)
- **lag to drop: the first bin at or below the midpoint starts 0.00 s after the pause; lag to recover: 1.25 s after the resume** (resolution 0.25 s; `ps` time has 10 ms steps)
- per-test spread: drop 0.00–0.00 s (median 0.00), recover 1.00–2.00 s (median 1.75) — 3 of 4 tests had a clear step

### WebKit helper processes and responsibility (*measured*)

| kind | executable | folder | times seen (once per web test) | responsible pid = the app |
|---|---|---|---|---|
| apple-other | `SetStoreUpdateService` | `/System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices/SetStoreUpdateService.xpc/Contents/MacOS` | 4 | 4 of 4 |
| apple-other | `com.apple.audio.SandboxHelper` | `/System/Library/Frameworks/AudioToolbox.framework/XPCServices/com.apple.audio.SandboxHelper.xpc/Contents/MacOS` | 4 | 4 of 4 |
| main | `FarolSpikeWeb` | `/Users/evgiroldo/Claude Code/Farol/docs/spikes/attribution-v2/build/FarolSpikeWeb.app/Contents/MacOS` | 4 | 4 of 4 |
| webkit-helper | `com.apple.WebKit.GPU` | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS` | 4 | 4 of 4 |
| webkit-helper | `com.apple.WebKit.Networking` | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS` | 4 | 4 of 4 |
| webkit-helper | `com.apple.WebKit.WebContent` | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS` | 4 | 4 of 4 |

`main` is the spike's own app; `webkit-helper` = Apple-signed (`anchor apple`), under `/System/…/WebKit.framework/`, started after the app, and attributed to the app by `responsibility_get_pid_responsible_for_pid` (or its child). `main`, `bundle` and `webkit-helper` were paused together. `apple-other` = another Apple-signed macOS service attributed to the app: the spike left it running and did not refuse — **ADR 0034 §3 as written would refuse the test**, so every row of that kind is a case to decide. A member of kind `outside` makes the spike refuse the test. The app is launched with a responsibility *disclaim* so that it, not the terminal, is the responsible process — see the notes for whether that worked.

## 3. Occlusion: does covering the culprit's window hide the load?

| state | runs | WindowServer mean (*measured*) | each run | relative to visible | web app group CPU | animation callbacks per second | window reports visible (0–1) |
|---|---|---|---|---|---|---|---|
| culprit window visible | 1 | 43.1% | 43.1% | 100.0% | 11.2% | 60 | 1.00 |
| small static panel on top (planned Farol test UI) | 1 | 42.7% | 42.7% | 99.1% | 11.5% | 60 | 1.00 |
| fully covered by another window | 1 | 37.3% | 37.3% | 86.5% | 11.3% | 60 | 1.00 |

States were interleaved (visible → panel → full, repeated), 3 s settling before each measurement. "Animation callbacks per second" is counted inside the page, so WebKit throttling an occluded view shows directly.

## 4. Cost of the spike itself (*measured*, includes `ps` children)

| phase | `ps` cadence | seconds | `ps` calls | CPU, % of one core |
|---|---|---|---|---|
| record-idle | every 1.0 s | 60.02 | 61 | 1.490% |
| record-loaded-steady | every 1.0 s | 180.01 | 181 | 0.517% |
| record-loaded-pulsed | every 1.0 s | 0.01 | 1 | 97.744% |
| real tests (16) | every 0.25 s | 37.5 each | 151 each | 2.31% mean (2.00–3.05%) |

During a test the trace is sampled every 0.25 s only to measure lag; the protocol itself needs 13 `ps` calls (window endpoints).

## Notes written during the run

- 2026-11-16 19:06:04.151 +0100  safety check (crash): stop reported "STOPPED status=4 cpuDelta=0.000" 0.6 s after start; victim running again within 0.1 s of that report → PASS
- 2026-11-16 19:06:08.357 +0100  safety check (hang): stop reported "STOPPED status=4 cpuDelta=0.000" 0.6 s after start; victim running again within 0.5 s of that report → PASS
- 2026-11-16 19:07:08.819 +0100  web app pid 59096, level 1, rhythm steady, window frame 40,236,1536,878; disclaim requested: true; responsible pid: 59096 (itself)
- 2026-11-16 19:07:26.838 +0100  load check: WindowServer 41.2% at web level 1, mds_stores 5.6% at writer level 1
- 2026-11-16 19:07:44.885 +0100  load check: WindowServer 43.0% at web level 1, mds_stores 16.8% at writer level 2
- 2026-11-16 19:08:02.978 +0100  load check: WindowServer 42.6% at web level 1, mds_stores 30.6% at writer level 3
- 2026-11-16 19:08:18.092 +0100  Spotlight did NOT return the writer's files (mdfind -onlyin found 0): the Spotlight culprit is not valid in this run
- 2026-11-16 19:20:04.289 +0100  web app pid 61384, level 1, rhythm pulsed:4,3, window frame 40,236,1536,878; disclaim requested: true; responsible pid: 61384 (itself)
- 2026-11-16 19:20:25.486 +0100  Spotlight did NOT return the writer's files (mdfind -onlyin found 0): the Spotlight culprit is not valid in this run

## Limits of this evidence

- One Mac, one session, synthetic culprits; daemon behaviour differs across hardware, displays and macOS versions.
- The protocol as specified (18 s + 3 × 6 s) lasts 36 s; ADR 0033 says "about 42 seconds". The spike runs 36 s plus a 1.5 s tail used only for the lag shift.
- Sham tests come from the same minutes of load as the real tests; other kinds of natural load (video, scrolling, a first Spotlight index) may fluctuate differently. Longer `record` runs during normal use extend the calibration.
- Thresholds are floored at the ADR 0022 starting values (3× and 2×); the raw calibrated values are in the table and in `calibration.csv`.
- The microphone rule (ADR 0034 §2) is not implemented here: the spike only ever pauses its own processes.
