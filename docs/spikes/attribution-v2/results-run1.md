# Attribution spike v2 — results

Generated 2026-11-16 19:05:00.007 +0100 from the raw CSV files in this folder by `attrib2 analyze`. One Mac (Mac17,3, macOS 27.2.1, 10 cores), synthetic culprits started by the spike. Feasibility evidence, not guaranteed accuracy.

Labels: **measured** = read from `ps`/the kernel; **inferred** = computed from measured values by the stated rule.

## When it ran (exclude these windows from other measurements)

| phase | start | end |
|---|---|---|
| safety-check | 2026-11-16 18:03:50.584 +0100 | 2026-11-16 18:03:55.550 +0100 |
| record-idle | 2026-11-16 18:03:55.550 +0100 | 2026-11-16 18:06:55.572 +0100 |
| start-load-steady | 2026-11-16 18:06:55.572 +0100 | 2026-11-16 18:08:05.252 +0100 |
| record-loaded-steady | 2026-11-16 18:08:05.252 +0100 | 2026-11-16 18:20:05.261 +0100 |
| tests-steady | 2026-11-16 18:20:05.261 +0100 | 2026-11-16 18:34:01.837 +0100 |
| occlusion | 2026-11-16 18:34:01.837 +0100 | 2026-11-16 18:37:29.226 +0100 |
| restart-load-pulsed | 2026-11-16 18:37:29.226 +0100 | 2026-11-16 18:37:50.527 +0100 |
| record-loaded-pulsed | 2026-11-16 18:37:50.527 +0100 | 2026-11-16 18:45:50.545 +0100 |
| tests-pulsed | 2026-11-16 18:45:50.545 +0100 | 2026-11-16 18:54:12.498 +0100 |
| stop-load | 2026-11-16 18:54:12.499 +0100 | 2026-11-16 18:54:12.643 +0100 |

## 1. Calibration of the cause-test thresholds (sham tests, nothing paused)

Method: the exact ADR 0033 window (six 3 s observation windows, then 3 × 3 s "pause" / 3 s "run", all from cumulative `ps` time at window endpoints) is slid over each no-pause recording, one start per sample. Nothing was paused, so every "proven" is false. Definitions: fluctuation = sample standard deviation (n−1) of the six observation windows, floored at one `ps` tick per window (0.33% of a core); effect = mean over the 3 cycles of (mean of the run windows before and after − the pause window); ratio = effect / fluctuation; *strict pattern* = lower in every pause than the run before it and higher in every run after it; *same direction* = each cycle's effect is positive. "Eligible" = observation mean ≥ 10% of a core (ADR 0022 §3: only then is a test offered).

**How much evidence this is.** Overlapping sham tests share most of their data, so the honest sample size is closer to the *non-overlapping* count. With N independent tests and zero false proofs, the true rate is only shown to be below about 3/N (95%).

| recording | daemon | sham tests | overlapping N | non-overlapping N | median load | strict pattern by chance | ratio p50 | p95 | p99 | max | threshold proven (<1%) | threshold likely (<5%) | false proven at 3× / false likely at 2× |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| idle | WindowServer | all | 145 | 5 | 0.4% | 5.5% | -0.00 | 0.67 | 1.00 | 1.17 | 0.83 | 0.67 | 0.0% / 0.0% |
| idle | WindowServer | eligible | 0 | 0 | – | – | – | – | – | – | – | – | – |
| idle | mds_stores | all | 145 | 5 | 0.1% | 0.0% | 0.00 | 0.33 | 0.50 | 0.50 | 0.00 | 0.00 | 0.0% / 0.0% |
| idle | mds_stores | eligible | 0 | 0 | – | – | – | – | – | – | – | – | – |
| loaded-pulsed | WindowServer | all | 445 | 13 | 42.1% | 9.7% | 0.02 | 1.90 | 2.90 | 3.30 | 2.48 | 1.87 | 0.0% / 4.0% |
| loaded-pulsed | WindowServer | eligible | 445 | 13 | 42.1% | 9.7% | 0.02 | 1.90 | 2.90 | 3.30 | 2.48 | 1.87 | 0.0% / 4.0% |
| loaded-pulsed | mds_stores | all | 445 | 13 | 0.6% | 0.4% | 0.02 | 12.81 | 24.95 | 33.58 | 0.00 | 0.80 | 0.0% / 2.0% |
| loaded-pulsed | mds_stores | eligible | 0 | 0 | – | – | – | – | – | – | – | – | – |
| loaded-steady | WindowServer | all | 685 | 20 | 42.1% | 8.0% | -0.00 | 1.53 | 2.36 | 3.51 | 2.09 | 1.47 | 0.1% / 2.6% |
| loaded-steady | WindowServer | eligible | 685 | 20 | 42.1% | 8.0% | -0.00 | 1.53 | 2.36 | 3.51 | 2.09 | 1.47 | 0.1% / 2.6% |
| loaded-steady | mds_stores | all | 685 | 20 | 0.6% | 1.6% | 0.00 | 12.67 | 28.64 | 35.67 | 0.62 | 1.55 | 0.3% / 4.4% |
| loaded-steady | mds_stores | eligible | 0 | 0 | – | – | – | – | – | – | – | – | – |
| POOLED (recordings under load) | WindowServer | eligible | 1130 | 33 | 42.1% | 8.7% | 0.00 | 1.70 | 2.69 | 3.51 | 2.13 | 1.60 | 0.1% / 3.2% |

Thresholds are the smallest ratio T such that fewer than 1% of sham tests satisfy *strict pattern and ratio > T* (proven), and fewer than 5% satisfy *same direction and ratio > T* (likely). A threshold of 0.00 means the pattern rule alone already kept the rate below the limit in that recording. Pattern-free thresholds and all quantiles are in `calibration.csv`; every sham test is in `sham-*.csv`.

**Thresholds used for the verdicts below** (*inferred*):

- WindowServer: proven > **3.00×**, likely > **2.00×** — 1130 overlapping eligible sham tests (33 non-overlapping) from recordings under load; calibrated values 2.13 (proven, <1%) and 1.60 (likely, <5%), floored at the ADR 0022 values 3 and 2.
- mds_stores: proven > **3.00×**, likely > **2.00×** — uncalibrated: ADR 0022 initial values (no eligible sham tests in this run).

## 2. Real cause tests with known ground truth

All four stimuli run at the same time (web app, writer, and two CPU-only decoys); each test pauses one of them with the full protocol and a watchdog. Ground truth: pausing `web` should lower WindowServer, pausing `writer` should lower mds_stores; every other pairing is a real pause with **no** known cause. "Offered" = observation mean ≥ 10% of a core. Shares are *inferred*: "in three tries, between X% and Y%".

### Per condition

| rhythm | paused | daemon | truth | tests | offered (≥10%) | median load | median fluctuation | median effect | median ratio | proven / likely / inconclusive | same, windows shifted by lag | share range over all tries |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pulsed:4/3 | burn-random | WindowServer | no cause | 3 | 3 | 42.0% | 0.5% | -0.7% | -0.51 | 0 / 0 / 3 | – | – |
| pulsed:4/3 | burn-random | mds_stores | no cause | 3 | 0 | 0.6% | 1.2% | -0.9% | -0.47 | 0 / 0 / 3 | – | – |
| pulsed:4/3 | burn-sync | WindowServer | no cause | 3 | 3 | 42.1% | 0.6% | -0.8% | -1.39 | 0 / 0 / 3 | – | – |
| pulsed:4/3 | burn-sync | mds_stores | no cause | 3 | 0 | 0.8% | 0.6% | 0.4% | 0.28 | 0 / 0 / 3 | – | – |
| pulsed:4/3 | web | WindowServer | **cause** | 3 | 3 | 41.9% | 0.9% | -0.4% | -0.32 | 0 / 0 / 3 | – | -5.1%–3.5% |
| pulsed:4/3 | web | mds_stores | no cause | 3 | 0 | 0.6% | 1.0% | -1.1% | -0.83 | 0 / 0 / 3 | – | – |
| pulsed:4/3 | writer | WindowServer | no cause | 3 | 3 | 41.4% | 0.5% | 0.4% | 0.54 | 0 / 0 / 3 | – | – |
| pulsed:4/3 | writer | mds_stores | **cause** | 3 | 0 | 0.4% | 1.1% | -0.1% | -0.33 | 0 / 0 / 3 | – | -1700.0%–100.0% |
| steady | burn-random | WindowServer | no cause | 5 | 5 | 41.4% | 0.3% | 0.0% | 0.07 | 0 / 0 / 5 | – | – |
| steady | burn-random | mds_stores | no cause | 5 | 0 | 0.7% | 0.8% | -0.1% | -0.04 | 0 / 0 / 5 | – | – |
| steady | burn-sync | WindowServer | no cause | 5 | 5 | 40.3% | 0.3% | -0.9% | -2.53 | 0 / 0 / 5 | – | – |
| steady | burn-sync | mds_stores | no cause | 5 | 0 | 0.7% | 0.9% | 0.0% | 0.00 | 0 / 0 / 5 | – | – |
| steady | web | WindowServer | **cause** | 5 | 5 | 41.9% | 0.3% | -1.8% | -4.84 | 0 / 0 / 5 | – | -9.0%–-1.7% |
| steady | web | mds_stores | no cause | 5 | 0 | 0.7% | 1.3% | 0.0% | 0.00 | 0 / 0 / 5 | – | – |
| steady | writer | WindowServer | no cause | 5 | 5 | 40.3% | 0.3% | 0.1% | 0.16 | 0 / 0 / 5 | – | – |
| steady | writer | mds_stores | **cause** | 5 | 0 | 0.6% | 0.8% | -0.5% | -0.39 | 0 / 0 / 5 | – | -183.3%–100.0% |

### Headline counts (*inferred* verdicts on *measured* data)

- Real cause, test offered (load ≥ 10%): **0 proven, 0 likely, 8 inconclusive** out of 8 (all 16 real-cause tests regardless of load: 0 / 0 / 16).
- No cause (decoys, and culprits measured against the other daemon), test offered: **0 wrongly proven, 0 wrongly likely** out of 24 (all 48 regardless of load: 0 / 0 / 48).
- With these few tests, a count of zero only bounds the true rate below about 3/N.

### Every test

| test | daemon | truth | load | fluctuation | effect | ratio | strict | share range (3 tries) | verdict | ratio / verdict with lag shift |
|---|---|---|---|---|---|---|---|---|---|---|
| steady-web-1 | WindowServer | cause | 41.9% | 0.5% | -2.4% | -4.84 | no | -9.0%–-1.9% | inconclusive | – |
| steady-web-1 | mds_stores | no cause | 0.7% (below 10%) | 1.0% | 0.0% | 0.00 | no | 0.0%–100.0% | inconclusive | – |
| steady-writer-1 | WindowServer | no cause | 40.8% | 0.3% | 0.1% | 0.21 | no | -0.4%–0.6% | inconclusive | – |
| steady-writer-1 | mds_stores | cause | 0.1% (below 10%) | 0.3% | -8.8% | -26.33 | no | 0.0%–0.0% | inconclusive | – |
| steady-burn-sync-1 | WindowServer | no cause | 40.4% | 0.3% | -0.8% | -2.53 | no | -3.2%–-0.9% | inconclusive | – |
| steady-burn-sync-1 | mds_stores | no cause | 0.7% (below 10%) | 0.9% | 1.0% | 1.11 | no | 0.0%–100.0% | inconclusive | – |
| steady-burn-random-1 | WindowServer | no cause | 41.0% | 0.3% | -0.0% | -0.08 | no | -0.3%–0.1% | inconclusive | – |
| steady-burn-random-1 | mds_stores | no cause | 0.3% (below 10%) | 0.5% | 0.0% | 0.00 | no | 0.0%–0.0% | inconclusive | – |
| steady-web-2 | WindowServer | cause | 41.3% | 0.3% | -1.8% | -5.53 | no | -5.8%–-3.5% | inconclusive | – |
| steady-web-2 | mds_stores | no cause | 4.2% (below 10%) | 10.3% | 1.1% | 0.11 | no | 0.0%–100.0% | inconclusive | – |
| steady-writer-2 | WindowServer | no cause | 40.3% | 0.4% | -0.1% | -0.27 | no | -0.6%–0.0% | inconclusive | – |
| steady-writer-2 | mds_stores | cause | 1.1% (below 10%) | 1.2% | 0.1% | 0.08 | no | -81.2%–100.0% | inconclusive | – |
| steady-burn-sync-2 | WindowServer | no cause | 40.5% | 0.3% | -0.0% | -0.10 | no | -0.4%–0.4% | inconclusive | – |
| steady-burn-sync-2 | mds_stores | no cause | 0.1% (below 10%) | 0.3% | 0.0% | 0.00 | no | 0.0%–0.0% | inconclusive | – |
| steady-burn-random-2 | WindowServer | no cause | 42.4% | 0.3% | 0.2% | 0.75 | yes | 0.4%–0.9% | inconclusive | – |
| steady-burn-random-2 | mds_stores | no cause | 4.7% (below 10%) | 10.8% | -0.4% | -0.04 | no | -1300.0%–100.0% | inconclusive | – |
| steady-web-3 | WindowServer | cause | 41.5% | 0.4% | -1.3% | -3.49 | no | -4.8%–-1.7% | inconclusive | – |
| steady-web-3 | mds_stores | no cause | 1.0% (below 10%) | 1.3% | -0.1% | -0.08 | no | -220.0%–94.9% | inconclusive | – |
| steady-writer-3 | WindowServer | no cause | 39.4% | 0.3% | -0.4% | -1.29 | no | -2.3%–0.5% | inconclusive | – |
| steady-writer-3 | mds_stores | cause | 0.0% (below 10%) | 0.3% | 0.1% | 0.33 | no | 0.0%–100.0% | inconclusive | – |
| steady-burn-sync-3 | WindowServer | no cause | 40.3% | 0.5% | -0.9% | -1.63 | no | -2.8%–-1.3% | inconclusive | – |
| steady-burn-sync-3 | mds_stores | no cause | 4.9% (below 10%) | 10.2% | -0.4% | -0.04 | no | -700.0%–0.0% | inconclusive | – |
| steady-burn-random-3 | WindowServer | no cause | 42.6% | 0.3% | 0.0% | 0.07 | no | -1.1%–0.8% | inconclusive | – |
| steady-burn-random-3 | mds_stores | no cause | 0.7% (below 10%) | 0.8% | -0.1% | -0.14 | no | -140.0%–100.0% | inconclusive | – |
| steady-web-4 | WindowServer | cause | 41.9% | 0.3% | -1.5% | -4.41 | no | -4.8%–-2.8% | inconclusive | – |
| steady-web-4 | mds_stores | no cause | 0.1% (below 10%) | 0.3% | 0.0% | 0.00 | no | 0.0%–0.0% | inconclusive | – |
| steady-writer-4 | WindowServer | no cause | 40.3% | 0.4% | 0.1% | 0.16 | no | -0.4%–0.5% | inconclusive | – |
| steady-writer-4 | mds_stores | cause | 0.6% (below 10%) | 0.8% | -1.0% | -1.25 | no | 0.0%–100.0% | inconclusive | – |
| steady-burn-sync-4 | WindowServer | no cause | 40.0% | 0.3% | -3.0% | -9.11 | no | -10.4%–-4.1% | inconclusive | – |
| steady-burn-sync-4 | mds_stores | no cause | 1.0% (below 10%) | 1.6% | 0.8% | 0.48 | no | 66.7%–100.0% | inconclusive | – |
| steady-burn-random-4 | WindowServer | no cause | 41.4% | 0.4% | 0.0% | 0.12 | no | -1.4%–2.5% | inconclusive | – |
| steady-burn-random-4 | mds_stores | no cause | 0.1% (below 10%) | 0.3% | 4.1% | 12.33 | no | 0.0%–97.4% | inconclusive | – |
| steady-web-5 | WindowServer | cause | 42.4% | 0.3% | -2.3% | -6.80 | no | -7.8%–-3.4% | inconclusive | – |
| steady-web-5 | mds_stores | no cause | 0.6% (below 10%) | 1.5% | 1.3% | 0.85 | no | 0.0%–100.0% | inconclusive | – |
| steady-writer-5 | WindowServer | no cause | 41.1% | 0.3% | 0.5% | 1.36 | yes | 0.6%–2.1% | inconclusive | – |
| steady-writer-5 | mds_stores | cause | 1.4% (below 10%) | 1.4% | -0.5% | -0.39 | no | -183.3%–100.0% | inconclusive | – |
| steady-burn-sync-5 | WindowServer | no cause | 39.5% | 0.3% | -1.9% | -5.78 | no | -5.9%–-3.3% | inconclusive | – |
| steady-burn-sync-5 | mds_stores | no cause | 0.0% (below 10%) | 0.3% | -8.4% | -25.33 | no | 0.0%–0.0% | inconclusive | – |
| steady-burn-random-5 | WindowServer | no cause | 41.4% | 0.3% | -0.1% | -0.43 | no | -0.9%–0.5% | inconclusive | – |
| steady-burn-random-5 | mds_stores | no cause | 0.7% (below 10%) | 0.9% | -0.8% | -0.95 | no | -1700.0%–100.0% | inconclusive | – |
| pulsed-web-1 | WindowServer | cause | 42.3% | 0.4% | -0.8% | -1.94 | no | -4.3%–1.0% | inconclusive | – |
| pulsed-web-1 | mds_stores | no cause | 0.6% (below 10%) | 1.3% | -1.1% | -0.83 | no | -1900.0%–0.0% | inconclusive | – |
| pulsed-writer-1 | WindowServer | no cause | 42.2% | 0.8% | 0.4% | 0.54 | no | -0.0%–1.6% | inconclusive | – |
| pulsed-writer-1 | mds_stores | cause | 0.1% (below 10%) | 0.3% | -0.1% | -0.33 | no | 0.0%–0.0% | inconclusive | – |
| pulsed-burn-sync-1 | WindowServer | no cause | 41.6% | 0.6% | -0.8% | -1.39 | no | -4.4%–1.4% | inconclusive | – |
| pulsed-burn-sync-1 | mds_stores | no cause | 0.8% (below 10%) | 0.6% | -1.1% | -1.70 | no | -2100.0%–100.0% | inconclusive | – |
| pulsed-burn-random-1 | WindowServer | no cause | 41.6% | 0.4% | -2.1% | -5.31 | no | -8.9%–-0.1% | inconclusive | – |
| pulsed-burn-random-1 | mds_stores | no cause | 0.6% (below 10%) | 1.2% | 0.9% | 0.80 | no | 0.0%–100.0% | inconclusive | – |
| pulsed-web-2 | WindowServer | cause | 41.8% | 1.5% | -0.4% | -0.27 | no | -2.5%–0.5% | inconclusive | – |
| pulsed-web-2 | mds_stores | no cause | 0.1% (below 10%) | 0.3% | -8.1% | -24.33 | no | -7500.0%–100.0% | inconclusive | – |
| pulsed-writer-2 | WindowServer | no cause | 41.4% | 0.4% | 0.4% | 1.14 | yes | 1.0%–1.2% | inconclusive | – |
| pulsed-writer-2 | mds_stores | cause | 0.4% (below 10%) | 1.1% | -0.9% | -0.87 | no | -1700.0%–100.0% | inconclusive | – |
| pulsed-burn-sync-2 | WindowServer | no cause | 42.2% | 0.3% | -1.6% | -4.93 | no | -5.4%–-2.3% | inconclusive | – |
| pulsed-burn-sync-2 | mds_stores | no cause | 1.2% (below 10%) | 1.6% | 0.4% | 0.28 | no | 0.0%–100.0% | inconclusive | – |
| pulsed-burn-random-2 | WindowServer | no cause | 42.2% | 0.5% | 0.1% | 0.24 | no | -3.8%–3.4% | inconclusive | – |
| pulsed-burn-random-2 | mds_stores | no cause | 0.2% (below 10%) | 0.4% | -7.8% | -19.19 | no | -14500.0%–100.0% | inconclusive | – |
| pulsed-web-3 | WindowServer | cause | 41.9% | 0.9% | -0.3% | -0.32 | no | -5.1%–3.5% | inconclusive | – |
| pulsed-web-3 | mds_stores | no cause | 0.9% (below 10%) | 1.0% | -0.3% | -0.28 | no | -300.0%–100.0% | inconclusive | – |
| pulsed-writer-3 | WindowServer | no cause | 41.4% | 0.5% | -1.5% | -2.96 | no | -5.5%–-1.1% | inconclusive | – |
| pulsed-writer-3 | mds_stores | cause | 0.9% (below 10%) | 1.3% | -0.1% | -0.09 | no | 0.0%–0.0% | inconclusive | – |
| pulsed-burn-sync-3 | WindowServer | no cause | 42.1% | 1.3% | 0.6% | 0.49 | no | 0.1%–3.6% | inconclusive | – |
| pulsed-burn-sync-3 | mds_stores | no cause | 0.4% (below 10%) | 0.5% | 11.7% | 21.73 | no | -200.0%–100.0% | inconclusive | – |
| pulsed-burn-random-3 | WindowServer | no cause | 42.0% | 1.4% | -0.7% | -0.51 | no | -2.2%–-1.5% | inconclusive | – |
| pulsed-burn-random-3 | mds_stores | no cause | 0.8% (below 10%) | 1.9% | -0.9% | -0.47 | no | -1801.1%–100.0% | inconclusive | – |

### Lag per daemon (ADR 0033 §5)

**WindowServer** when its culprit (`web`) is paused — 8 tests × 3 cycles, 0.25 s bins (*measured* shares, *inferred* lag):

- share while running (last second before the next pause): 41.5%; while paused (last second of the pause): 42.6%
- after SIGSTOP, share per 0.25 s bin: 43 43 42 42 42 42 43 43 43 42 43 42 (%)
- after SIGCONT, share per 0.25 s bin: 40 40 41 41 41 41 41 40 42 42 41 41 (%)
- no clear step between running and paused (difference under 2% of a core): **lag not measurable in this run**

**mds_stores** when its culprit (`writer`) is paused — 8 tests × 3 cycles, 0.25 s bins (*measured* shares, *inferred* lag):

- share while running (last second before the next pause): 0.1%; while paused (last second of the pause): 3.1%
- after SIGSTOP, share per 0.25 s bin: 1 0 0 2 0 2 0 1 12 0 0 0 (%)
- after SIGCONT, share per 0.25 s bin: 0 0 0 0 0 0 0 0 0 0 0 0 (%)
- no clear step between running and paused (difference under 2% of a core): **lag not measurable in this run**

### WebKit helper processes and responsibility (*measured*)

| kind | executable | folder | times seen (once per web test) | responsible pid = the app |
|---|---|---|---|---|
| apple-other | `MTLCompilerService` | `/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc/Contents/MacOS` | 5 | 5 of 5 |
| apple-other | `SetStoreUpdateService` | `/System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices/SetStoreUpdateService.xpc/Contents/MacOS` | 8 | 8 of 8 |
| apple-other | `com.apple.audio.SandboxHelper` | `/System/Library/Frameworks/AudioToolbox.framework/XPCServices/com.apple.audio.SandboxHelper.xpc/Contents/MacOS` | 8 | 8 of 8 |
| main | `FarolSpikeWeb` | `/Users/evgiroldo/Claude Code/Farol/docs/spikes/attribution-v2/build/FarolSpikeWeb.app/Contents/MacOS` | 8 | 8 of 8 |
| webkit-helper | `com.apple.WebKit.GPU` | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS` | 8 | 8 of 8 |
| webkit-helper | `com.apple.WebKit.Networking` | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS` | 8 | 8 of 8 |
| webkit-helper | `com.apple.WebKit.WebContent` | `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS` | 8 | 8 of 8 |

`main` is the spike's own app; `webkit-helper` = Apple-signed (`anchor apple`), under `/System/…/WebKit.framework/`, started after the app, and attributed to the app by `responsibility_get_pid_responsible_for_pid` (or its child). `main`, `bundle` and `webkit-helper` were paused together. `apple-other` = another Apple-signed macOS service attributed to the app: the spike left it running and did not refuse — **ADR 0034 §3 as written would refuse the test**, so every row of that kind is a case to decide. A member of kind `outside` makes the spike refuse the test. The app is launched with a responsibility *disclaim* so that it, not the terminal, is the responsible process — see the notes for whether that worked.

## 3. Occlusion: does covering the culprit's window hide the load?

| state | runs | WindowServer mean (*measured*) | each run | relative to visible | web app group CPU | animation callbacks per second | window reports visible (0–1) |
|---|---|---|---|---|---|---|---|
| culprit window visible | 3 | 42.8% | 42.5%, 43.1%, 42.7% | 100.0% | 8.5% | 60 | 1.00 |
| small static panel on top (planned Farol test UI) | 3 | 42.6% | 42.9%, 42.8%, 42.1% | 99.6% | 8.5% | 60 | 1.00 |
| fully covered by another window | 3 | 39.6% | 39.1%, 40.6%, 39.2% | 92.7% | 8.4% | 60 | 1.00 |

States were interleaved (visible → panel → full, repeated), 3 s settling before each measurement. "Animation callbacks per second" is counted inside the page, so WebKit throttling an occluded view shows directly.

## 4. Cost of the spike itself (*measured*, includes `ps` children)

| phase | `ps` cadence | seconds | `ps` calls | CPU, % of one core |
|---|---|---|---|---|
| record-idle | every 1.0 s | 180.02 | 181 | 1.488% |
| record-loaded-steady | every 1.0 s | 720.01 | 721 | 0.518% |
| record-loaded-pulsed | every 1.0 s | 480.02 | 481 | 0.715% |
| real tests (32) | every 0.25 s | 37.5 each | 151 each | 2.36% mean (1.97–3.30%) |

During a test the trace is sampled every 0.25 s only to measure lag; the protocol itself needs 13 `ps` calls (window endpoints).

## Notes written during the run

- 2026-11-16 18:03:51.320 +0100  safety check (crash): stop reported "STOPPED status=4 cpuDelta=0.000" 0.6 s after start; victim running again within 0.1 s of that report → PASS
- 2026-11-16 18:03:55.525 +0100  safety check (hang): stop reported "STOPPED status=4 cpuDelta=0.000" 0.6 s after start; victim running again within 0.4 s of that report → PASS
- 2026-11-16 18:06:55.984 +0100  web app pid 51187, level 1, rhythm steady, window frame 40,236,1536,878; disclaim requested: true; responsible pid: 51187 (itself)
- 2026-11-16 18:07:14.002 +0100  load check: WindowServer 42.2% at web level 1, mds_stores 16.2% at writer level 1
- 2026-11-16 18:07:32.071 +0100  load check: WindowServer 42.9% at web level 1, mds_stores 0.2% at writer level 2
- 2026-11-16 18:07:50.142 +0100  load check: WindowServer 41.5% at web level 1, mds_stores 24.1% at writer level 3
- 2026-11-16 18:08:05.252 +0100  Spotlight did NOT return the writer's files (mdfind -onlyin found 0): the Spotlight culprit is not valid in this run
- 2026-11-16 18:37:29.357 +0100  web app pid 55619, level 1, rhythm pulsed:4,3, window frame 40,236,1536,878; disclaim requested: true; responsible pid: 55619 (itself)
- 2026-11-16 18:37:50.527 +0100  Spotlight did NOT return the writer's files (mdfind -onlyin found 0): the Spotlight culprit is not valid in this run

## Limits of this evidence

- One Mac, one session, synthetic culprits; daemon behaviour differs across hardware, displays and macOS versions.
- The protocol as specified (18 s + 3 × 6 s) lasts 36 s; ADR 0033 says "about 42 seconds". The spike runs 36 s plus a 1.5 s tail used only for the lag shift.
- Sham tests come from the same minutes of load as the real tests; other kinds of natural load (video, scrolling, a first Spotlight index) may fluctuate differently. Longer `record` runs during normal use extend the calibration.
- Thresholds are floored at the ADR 0022 starting values (3× and 2×); the raw calibrated values are in the table and in `calibration.csv`.
- The microphone rule (ADR 0034 §2) is not implemented here: the spike only ever pauses its own processes.
