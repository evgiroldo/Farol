// Throwaway validation prototype (attribution spike v2). NOT Farol code.
// Offline analysis of a run folder: sham-test calibration, real-test verdicts, lag, occlusion,
// cost. Reads only CSV files written by the spike; writes CSV summaries and results.md.
import Foundation

private func table(_ headers: [String], _ rows: [[String]]) -> String {
    var s = "| " + headers.joined(separator: " | ") + " |\n|" + headers.map { _ in "---" }.joined(separator: "|") + "|\n"
    for r in rows { s += "| " + r.joined(separator: " | ") + " |\n" }
    return s
}
private func num(_ x: Double, _ digits: Int = 2) -> String { x.isNaN ? "n/a" : String(format: "%.\(digits)f", x) }
private func csvRows(_ path: String) -> [[String: String]] {
    let lines = readLines(path)
    guard let header = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) else { return [] }
    return lines.dropFirst().map { line in
        let f = line.split(separator: ",", maxSplits: header.count - 1, omittingEmptySubsequences: false).map(String.init)
        var d: [String: String] = [:]
        for (i, h) in header.enumerated() where i < f.count { d[h] = f[i] }
        return d
    }
}

/// Pools sham tests from several recordings; the independent (non-overlapping) count is taken
/// per recording.
private func calibratePooled(_ groups: [(shams: [Sham], step: Int)]) -> Calibration {
    var c = calibrate(groups.flatMap { $0.shams }, step: 1)
    // Non-overlapping subset and its false-proof rate, taken recording by recording.
    var indep = 0
    var falseCount = 0
    for g in groups {
        let stride = g.step * (observationWindows + 2 * cycleCount)
        var next = Int.min
        for s in g.shams where s.index >= next {
            indep += 1
            if s.result.strict && s.result.ratio > c.thresholdProven { falseCount += 1 }
            next = s.index + stride
        }
    }
    c.nIndependent = indep
    c.falseProofIndependent = indep > 0 ? Double(falseCount) / Double(indep) : .nan
    return c
}

struct Thresholds {
    var proven = 3.0
    var likely = 2.0
    var calibrated = false
    var basis = "uncalibrated: ADR 0022 initial values (no eligible sham tests in this run)"
}

struct TestTrace {
    var series: [String: Series] = [:]
    var target = Series()
}

private func loadTrace(_ path: String) -> TestTrace? {
    let rows = csvRows(path)
    guard rows.count > 10 else { return nil }
    var tr = TestTrace()
    for n in daemonNames { tr.series[n] = Series() }
    for r in rows {
        guard let a = r["rel_before"].flatMap(Double.init), let b = r["rel_after"].flatMap(Double.init) else { continue }
        let t = (a + b) / 2
        for n in daemonNames {
            if let v = r[n].flatMap(Double.init) {
                tr.series[n]?.t.append(t)
                tr.series[n]?.c.append(v)
            }
        }
        if let v = r["target_cpu"].flatMap(Double.init) {
            tr.target.t.append(t)
            tr.target.c.append(v)
        }
    }
    return tr
}

func analyze(dir: String) {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir) else {
        print("no such folder: \(dir)")
        return
    }
    var md = "# Attribution spike v2 — results\n\n"
    md += "Generated \(wallNow()) from the raw CSV files in this folder by `attrib2 analyze`. "
    md += "One Mac (\(sysctlString("hw.model")), macOS \(sysctlString("kern.osproductversion")), \(ProcessInfo.processInfo.processorCount) cores), "
    md += "synthetic culprits started by the spike. Feasibility evidence, not guaranteed accuracy.\n\n"
    md += "Labels: **measured** = read from `ps`/the kernel; **inferred** = computed from measured values by the stated rule.\n\n"

    // ---- Phases -------------------------------------------------------------------------
    let phases = csvRows(dir + "/phases.csv")
    if !phases.isEmpty {
        md += "## When it ran (exclude these windows from other measurements)\n\n"
        md += table(["phase", "start", "end"], phases.map { [$0["phase"] ?? "", $0["start"] ?? "", $0["end"] ?? ""] }) + "\n"
    }

    // ---- 1. Calibration -----------------------------------------------------------------
    md += "## 1. Calibration of the cause-test thresholds (sham tests, nothing paused)\n\n"
    md += "Method: the exact ADR 0033 window (six 3 s observation windows, then 3 × 3 s \"pause\" / 3 s \"run\", "
    md += "all from cumulative `ps` time at window endpoints) is slid over each no-pause recording, one start per sample. "
    md += "Nothing was paused, so every \"proven\" is false. Definitions: fluctuation = sample standard deviation (n−1) of the six observation windows, "
    md += "floored at one `ps` tick per window (0.33% of a core); effect = mean over the 3 cycles of (mean of the run windows before and after − the pause window); "
    md += "ratio = effect / fluctuation; *strict pattern* = lower in every pause than the run before it and higher in every run after it; "
    md += "*same direction* = each cycle's effect is positive. \"Eligible\" = observation mean ≥ 10% of a core (ADR 0022 §3: only then is a test offered).\n\n"
    md += "**How much evidence this is.** Overlapping sham tests share most of their data, so the honest sample size is closer to the "
    md += "*non-overlapping* count. With N independent tests and zero false proofs, the true rate is only shown to be below about 3/N (95%).\n\n"

    var calRows: [[String]] = []
    var calCSV = ["recording,daemon,filter,n_overlapping,n_non_overlapping,median_load,median_fluctuation,strict_fraction,same_direction_fraction,ratio_p50,ratio_p90,ratio_p95,ratio_p99,ratio_p999,ratio_max,threshold_proven_1pct,threshold_likely_5pct,threshold_ratio_only_1pct,threshold_ratio_only_5pct,false_proof_rate_at_3,false_likely_rate_at_2,false_proof_rate_non_overlapping"]
    var pooled: [String: [(shams: [Sham], step: Int)]] = [:]  // daemon → eligible shams of loaded recordings
    var pooledAny: [String: [(shams: [Sham], step: Int)]] = [:]  // daemon → eligible shams of all recordings
    let recordings = names.filter { $0.hasPrefix("record-") && $0.hasSuffix(".csv") }.sorted()
    func addCal(_ label: String, _ daemon: String, _ filter: String, _ c: Calibration) {
        guard c.n > 0 else {
            calRows.append([label, daemon, filter, "0", "0", "–", "–", "–", "–", "–", "–", "–", "–", "–"])
            return
        }
        let q = c.ratioQuantiles
        calRows.append([
            label, daemon, filter, String(c.n), String(c.nIndependent), pct(c.medianLoad), pct(c.strictFraction),
            num(q[0]), num(q[2]), num(q[3]), num(q[5]), num(c.thresholdProven), num(c.thresholdLikely),
            pct(c.falseProofAt3) + " / " + pct(c.falseLikelyAt2),
        ])
        calCSV.append(
            ([label, daemon, filter, String(c.n), String(c.nIndependent), num(c.medianLoad, 4), num(c.medianFluct, 4), num(c.strictFraction, 4), num(c.sameDirectionFraction, 4)]
                + q.map { num($0, 3) }
                + [num(c.thresholdProven, 3), num(c.thresholdLikely, 3), num(c.thresholdRatioOnly1, 3), num(c.thresholdRatioOnly5, 3), num(c.falseProofAt3, 4), num(c.falseLikelyAt2, 4), num(c.falseProofIndependent, 4)])
                .joined(separator: ","))
    }
    for file in recordings {
        let label = String(file.dropFirst(7).dropLast(4))
        guard let rec = loadRecording(dir + "/" + file, label: label) else { continue }
        let step = max(1, Int((windowSeconds / rec.interval).rounded()))
        for d in daemonNames {
            let shams = shamTests(rec, daemon: d)
            var raw = ["start_index,start_mono,obs_mean,fluctuation,effect,ratio,strict,same_direction"]
            for s in shams {
                let r = s.result
                raw.append("\(s.index),\(f3(rec.t[s.index])),\(num(r.obsMean, 4)),\(num(r.fluct, 4)),\(num(r.effect, 4)),\(num(r.ratio, 3)),\(r.strict ? 1 : 0),\(r.sameDirection ? 1 : 0)")
            }
            try? (raw.joined(separator: "\n") + "\n").write(toFile: dir + "/sham-\(label)-\(d).csv", atomically: true, encoding: .utf8)
            let eligible = shams.filter { $0.result.obsMean >= minimumLoad }
            addCal(label, d, "all", calibrate(shams, step: step))
            addCal(label, d, "eligible", calibrate(eligible, step: step))
            pooledAny[d, default: []].append((eligible, step))
            if !label.hasPrefix("idle") { pooled[d, default: []].append((eligible, step)) }
        }
    }
    var thresholds: [String: Thresholds] = [:]
    for d in daemonNames {
        var th = Thresholds()
        var groups = pooled[d] ?? []
        var basis = "recordings under load"
        if groups.reduce(0, { $0 + $1.shams.count }) == 0 {
            groups = pooledAny[d] ?? []
            basis = "all recordings"
        }
        let c = calibratePooled(groups)
        if c.n > 0 {
            addCal("POOLED (\(basis))", d, "eligible", c)
            // Calibrated value, but never below the ADR 0022 starting values: a short recording can
            // only show that a threshold is too low, not that a lower one is safe.
            th.proven = max(3.0, c.thresholdProven)
            th.likely = min(th.proven, max(2.0, c.thresholdLikely))
            th.calibrated = true
            th.basis =
                "\(c.n) overlapping eligible sham tests (\(c.nIndependent) non-overlapping) from \(basis); calibrated values "
                + "\(num(c.thresholdProven)) (proven, <1%) and \(num(c.thresholdLikely)) (likely, <5%), floored at the ADR 0022 values 3 and 2"
        }
        thresholds[d] = th
    }
    if recordings.isEmpty {
        md += "_No recording in this folder._\n\n"
    } else {
        md += table(
            ["recording", "daemon", "sham tests", "overlapping N", "non-overlapping N", "median load", "strict pattern by chance", "ratio p50", "p95", "p99", "max", "threshold proven (<1%)", "threshold likely (<5%)", "false proven at 3× / false likely at 2×"],
            calRows) + "\n"
        md += "Thresholds are the smallest ratio T such that fewer than 1% of sham tests satisfy *strict pattern and ratio > T* (proven), "
        md += "and fewer than 5% satisfy *same direction and ratio > T* (likely). A threshold of 0.00 means the pattern rule alone already kept the rate below the limit in that recording. "
        md += "Pattern-free thresholds and all quantiles are in `calibration.csv`; every sham test is in `sham-*.csv`.\n\n"
        md += "**Thresholds used for the verdicts below** (*inferred*):\n\n"
        for d in daemonNames {
            let t = thresholds[d] ?? Thresholds()
            md += "- \(d): proven > **\(num(t.proven))×**, likely > **\(num(t.likely))×** — \(t.basis).\n"
        }
        md += "\n"
        try? (calCSV.joined(separator: "\n") + "\n").write(toFile: dir + "/calibration.csv", atomically: true, encoding: .utf8)
    }

    // ---- 2. Real tests ------------------------------------------------------------------
    md += "## 2. Real cause tests with known ground truth\n\n"
    let tests = csvRows(dir + "/tests.csv")
    struct Row {
        var test: String, rhythm: String, target: String, daemon: String, truth: Bool
        var r: ProtoResult
        var verdict: Verdict
        var shifted: ProtoResult?
        var verdictShifted: Verdict?
        var webVisible: Double?
    }
    var rows: [Row] = []
    var traces: [String: (TestTrace, [Double], [Double])] = [:]
    var notOK: [String] = []
    for t in tests {
        guard let id = t["test"], let target = t["target"] else { continue }
        guard t["status"] == "ok", let tr = loadTrace(dir + "/trace-\(id).csv") else {
            notOK.append("\(id): \(t["status"] ?? "no trace")")
            continue
        }
        let stops = (t["stop_times_s"] ?? "").split(separator: ";").compactMap { Double($0) }
        let conts = (t["resume_times_s"] ?? "").split(separator: ";").compactMap { Double($0) }
        traces[id] = (tr, stops, conts)
        for d in daemonNames {
            guard let s = tr.series[d], let w = s.protocolWindows(start: 0) else {
                notOK.append("\(id)/\(d): incomplete trace")
                continue
            }
            let r = evaluateWindows(w)
            let th = thresholds[d] ?? Thresholds()
            let truth = (target == "web" && d == "WindowServer") || (target == "writer" && d == "mds_stores")
            rows.append(
                Row(test: id, rhythm: t["rhythm"] ?? "", target: target, daemon: d, truth: truth, r: r,
                    verdict: verdict(r, proven: th.proven, likely: th.likely), webVisible: t["web_visible_obs"].flatMap(Double.init)))
        }
    }

    // Lag per daemon, from the true-culprit tests (mean response curves over cycles and tests).
    let bins = Int((windowSeconds / traceBin).rounded())
    var lagText = ""
    var shifts: [String: Double] = [:]
    for (d, culprit) in [("WindowServer", "web"), ("mds_stores", "writer")] {
        var drops: [[Double]] = []
        var rises: [[Double]] = []
        for t in tests where t["target"] == culprit && t["status"] == "ok" {
            guard let id = t["test"], let (tr, stops, conts) = traces[id], let s = tr.series[d], stops.count == cycleCount, conts.count == cycleCount,
                let dc = responseCurve(s, events: stops, bin: traceBin, bins: bins), let rc = responseCurve(s, events: conts, bin: traceBin, bins: bins)
            else { continue }
            drops.append(dc)
            rises.append(rc)
        }
        guard !drops.isEmpty else { continue }
        let dropCurve = (0..<bins).map { j in mean(drops.map { $0[j] }) }
        let riseCurve = (0..<bins).map { j in mean(rises.map { $0[j] }) }
        let lag = lagFrom(dropCurve: dropCurve, riseCurve: riseCurve, bin: traceBin)
        // Per-test lags, to show the spread.
        let perTest = zip(drops, rises).map { lagFrom(dropCurve: $0, riseCurve: $1, bin: traceBin) }
        let dropList = perTest.compactMap { $0.drop }.sorted()
        let recList = perTest.compactMap { $0.recover }.sorted()
        lagText += "**\(d)** when its culprit (`\(culprit)`) is paused — \(drops.count) tests × 3 cycles, 0.25 s bins (*measured* shares, *inferred* lag):\n\n"
        lagText += "- share while running (last second before the next pause): \(pct(lag.runLevel)); while paused (last second of the pause): \(pct(lag.pauseLevel))\n"
        lagText += "- after SIGSTOP, share per 0.25 s bin: " + dropCurve.map { String(format: "%.0f", 100 * $0) }.joined(separator: " ") + " (%)\n"
        lagText += "- after SIGCONT, share per 0.25 s bin: " + riseCurve.map { String(format: "%.0f", 100 * $0) }.joined(separator: " ") + " (%)\n"
        if let dr = lag.drop, let rc = lag.recover {
            lagText += "- **lag to drop: the first bin at or below the midpoint starts \(num(dr)) s after the pause; lag to recover: \(num(rc)) s after the resume** (resolution 0.25 s; `ps` time has 10 ms steps)\n"
            lagText += "- per-test spread: drop \(dropList.isEmpty ? "n/a" : "\(num(dropList.first!))–\(num(dropList.last!)) s (median \(num(median(dropList))))"), recover \(recList.isEmpty ? "n/a" : "\(num(recList.first!))–\(num(recList.last!)) s (median \(num(median(recList))))") — \(dropList.count) of \(perTest.count) tests had a clear step\n\n"
            shifts[d] = min(traceTail, dr)
        } else {
            lagText += "- no clear step between running and paused (difference under 2% of a core): **lag not measurable in this run**\n\n"
        }
    }
    // Re-evaluate with the windows of the three cycles shifted by the daemon's lag.
    for i in rows.indices {
        let row = rows[i]
        guard let shift = shifts[row.daemon], shift > 0, let (tr, _, _) = traces[row.test], let s = tr.series[row.daemon],
            let w = s.protocolWindows(start: 0, shift: shift)
        else { continue }
        let r = evaluateWindows(w)
        let th = thresholds[row.daemon] ?? Thresholds()
        rows[i].shifted = r
        rows[i].verdictShifted = verdict(r, proven: th.proven, likely: th.likely)
    }

    if tests.isEmpty {
        md += "_No real test in this folder._\n\n"
    } else {
        md += "All four stimuli run at the same time (web app, writer, and two CPU-only decoys); each test pauses one of them with the full protocol and a watchdog. "
        md += "Ground truth: pausing `web` should lower WindowServer, pausing `writer` should lower mds_stores; every other pairing is a real pause with **no** known cause. "
        md += "\"Offered\" = observation mean ≥ 10% of a core. Shares are *inferred*: \"in three tries, between X% and Y%\".\n\n"
        var csv = ["test,rhythm,target,daemon,truth_is_cause,obs_mean,fluctuation,effect,ratio,strict,same_direction,share_min,share_max,offered,verdict,lag_shift_s,ratio_shifted,verdict_shifted,web_visible_obs"]
        for r in rows {
            csv.append(
                "\(r.test),\(r.rhythm),\(r.target),\(r.daemon),\(r.truth ? 1 : 0),\(num(r.r.obsMean, 4)),\(num(r.r.fluct, 4)),\(num(r.r.effect, 4)),\(num(r.r.ratio, 3)),\(r.r.strict ? 1 : 0),\(r.r.sameDirection ? 1 : 0),"
                    + "\(num(r.r.shares.min() ?? .nan, 3)),\(num(r.r.shares.max() ?? .nan, 3)),\(r.r.obsMean >= minimumLoad ? 1 : 0),\(r.verdict.rawValue),\(shifts[r.daemon].map { num($0) } ?? ""),"
                    + "\(r.shifted.map { num($0.ratio, 3) } ?? ""),\(r.verdictShifted?.rawValue ?? ""),\(r.webVisible.map { num($0) } ?? "")")
        }
        try? (csv.joined(separator: "\n") + "\n").write(toFile: dir + "/test-results.csv", atomically: true, encoding: .utf8)

        func count(_ list: [Row], _ v: Verdict, shifted: Bool = false) -> Int {
            list.filter { (shifted ? ($0.verdictShifted ?? $0.verdict) : $0.verdict) == v }.count
        }
        // Summary per condition.
        var summary: [[String]] = []
        let keys = Array(Set(rows.map { "\($0.rhythm)|\($0.target)|\($0.daemon)" })).sorted()
        for k in keys {
            let list = rows.filter { "\($0.rhythm)|\($0.target)|\($0.daemon)" == k }
            guard let f = list.first else { continue }
            let offered = list.filter { $0.r.obsMean >= minimumLoad }
            let shareLo = list.map { $0.r.shares.min() ?? 0 }.min() ?? 0
            let shareHi = list.map { $0.r.shares.max() ?? 0 }.max() ?? 0
            summary.append([
                f.rhythm, f.target, f.daemon, f.truth ? "**cause**" : "no cause", String(list.count), String(offered.count),
                pct(median(list.map { $0.r.obsMean })), pct(median(list.map { $0.r.fluct })), pct(median(list.map { $0.r.effect })),
                num(median(list.map { $0.r.ratio })),
                "\(count(list, .proven)) / \(count(list, .likely)) / \(count(list, .inconclusive))",
                shifts[f.daemon] == nil ? "–" : "\(count(list, .proven, shifted: true)) / \(count(list, .likely, shifted: true)) / \(count(list, .inconclusive, shifted: true))",
                f.truth ? "\(pct(shareLo))–\(pct(shareHi))" : "–",
            ])
        }
        md += "### Per condition\n\n"
        md += table(
            ["rhythm", "paused", "daemon", "truth", "tests", "offered (≥10%)", "median load", "median fluctuation", "median effect", "median ratio", "proven / likely / inconclusive", "same, windows shifted by lag", "share range over all tries"],
            summary) + "\n"

        let truthRows = rows.filter { $0.truth }
        let nullRows = rows.filter { !$0.truth }
        let truthOffered = truthRows.filter { $0.r.obsMean >= minimumLoad }
        let nullOffered = nullRows.filter { $0.r.obsMean >= minimumLoad }
        md += "### Headline counts (*inferred* verdicts on *measured* data)\n\n"
        md += "- Real cause, test offered (load ≥ 10%): **\(count(truthOffered, .proven)) proven, \(count(truthOffered, .likely)) likely, \(count(truthOffered, .inconclusive)) inconclusive** out of \(truthOffered.count)"
        md += " (all \(truthRows.count) real-cause tests regardless of load: \(count(truthRows, .proven)) / \(count(truthRows, .likely)) / \(count(truthRows, .inconclusive))).\n"
        md += "- No cause (decoys, and culprits measured against the other daemon), test offered: **\(count(nullOffered, .proven)) wrongly proven, \(count(nullOffered, .likely)) wrongly likely** out of \(nullOffered.count)"
        md += " (all \(nullRows.count) regardless of load: \(count(nullRows, .proven)) / \(count(nullRows, .likely)) / \(count(nullRows, .inconclusive))).\n"
        if !truthOffered.isEmpty || !nullOffered.isEmpty {
            md += "- With these few tests, a count of zero only bounds the true rate below about 3/N.\n"
        }
        let hidden = rows.filter { $0.target == "web" && $0.daemon == "WindowServer" && ($0.webVisible ?? 1) < 0.99 }
        if !hidden.isEmpty {
            md += "- **Warning:** in \(hidden.count) web test(s) the web window reported itself not fully visible during observation (`web_visible_obs` in `test-results.csv`); those tests under-state the load.\n"
        }
        if !notOK.isEmpty { md += "- Tests refused, aborted or incomplete (not counted above): " + notOK.joined(separator: "; ") + ".\n" }
        md += "\n### Every test\n\n"
        md += table(
            ["test", "daemon", "truth", "load", "fluctuation", "effect", "ratio", "strict", "share range (3 tries)", "verdict", "ratio / verdict with lag shift"],
            rows.map { row in
                [
                    row.test, row.daemon, row.truth ? "cause" : "no cause", pct(row.r.obsMean) + (row.r.obsMean >= minimumLoad ? "" : " (below 10%)"), pct(row.r.fluct), pct(row.r.effect), num(row.r.ratio),
                    row.r.strict ? "yes" : "no", "\(pct(row.r.shares.min() ?? 0))–\(pct(row.r.shares.max() ?? 0))", row.verdict.rawValue,
                    row.shifted.map { s in "\(num(s.ratio)) / \(row.verdictShifted?.rawValue ?? "")" } ?? "–",
                ]
            }) + "\n"
        md += "### Lag per daemon (ADR 0033 §5)\n\n" + (lagText.isEmpty ? "_No true-culprit test completed._\n\n" : lagText)
    }

    // ---- WebKit helpers -----------------------------------------------------------------
    let helpers = csvRows(dir + "/helpers.csv")
    if !helpers.isEmpty {
        md += "### WebKit helper processes and responsibility (*measured*)\n\n"
        var seen: [String: (count: Int, mapped: Int)] = [:]
        for h in helpers {
            let key = "\(h["kind"] ?? "")|\(((h["path"] ?? "") as NSString).lastPathComponent)|\(((h["path"] ?? "") as NSString).deletingLastPathComponent)"
            var e = seen[key] ?? (0, 0)
            e.count += 1
            if h["responsible_pid"] == h["app_pid"], h["responsible_pid"] != "" { e.mapped += 1 }
            seen[key] = e
        }
        md += table(
            ["kind", "executable", "folder", "times seen (once per web test)", "responsible pid = the app"],
            seen.keys.sorted().map { k in
                let p = k.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                return [p[0], "`\(p[1])`", "`\(p[2])`", String(seen[k]!.count), "\(seen[k]!.mapped) of \(seen[k]!.count)"]
            }) + "\n"
        md += "`main` is the spike's own app; `webkit-helper` = Apple-signed (`anchor apple`), under `/System/…/WebKit.framework/`, started after the app, and attributed to the app by `responsibility_get_pid_responsible_for_pid` (or its child). "
        md += "`main`, `bundle` and `webkit-helper` were paused together. `apple-other` = another Apple-signed macOS service attributed to the app: the spike left it running and did not refuse — **ADR 0034 §3 as written would refuse the test**, so every row of that kind is a case to decide. A member of kind `outside` makes the spike refuse the test. The app is launched with a responsibility *disclaim* so that it, not the terminal, is the responsible process — see the notes for whether that worked.\n\n"
    }

    // ---- 3. Occlusion -------------------------------------------------------------------
    md += "## 3. Occlusion: does covering the culprit's window hide the load?\n\n"
    let occ = csvRows(dir + "/occlusion.csv")
    if occ.isEmpty {
        md += "_Not run in this folder._\n\n"
    } else {
        func col(_ state: String, _ key: String) -> [Double] { occ.filter { $0["state"] == state }.compactMap { $0[key].flatMap(Double.init) } }
        let base = mean(col("visible", "WindowServer_share"))
        var orows: [[String]] = []
        for (state, label) in [("visible", "culprit window visible"), ("panel", "small static panel on top (planned Farol test UI)"), ("full", "fully covered by another window")] {
            let ws = col(state, "WindowServer_share")
            guard !ws.isEmpty else { continue }
            orows.append([
                label, String(ws.count), pct(mean(ws)), ws.map { pct($0) }.joined(separator: ", "), base > 0 ? pct(mean(ws) / base) : "n/a",
                pct(mean(col(state, "web_group_cpu_share"))), num(mean(col(state, "web_fps")), 0), num(mean(col(state, "web_window_visible"))),
            ])
        }
        md += table(["state", "runs", "WindowServer mean (*measured*)", "each run", "relative to visible", "web app group CPU", "animation callbacks per second", "window reports visible (0–1)"], orows) + "\n"
        md += "States were interleaved (visible → panel → full, repeated), 3 s settling before each measurement. \"Animation callbacks per second\" is counted inside the page, so WebKit throttling an occluded view shows directly.\n\n"
    }

    // ---- 4. Cost ------------------------------------------------------------------------
    md += "## 4. Cost of the spike itself (*measured*, includes `ps` children)\n\n"
    let cost = csvRows(dir + "/cost.csv")
    if cost.isEmpty {
        md += "_No cost data._\n\n"
    } else {
        var crow: [[String]] = []
        for c in cost where (c["phase"] ?? "").hasPrefix("record-") {
            crow.append([c["phase"] ?? "", "every \(c["cadence_s"] ?? "?") s", c["wall_s"] ?? "", c["ps_calls"] ?? "", (c["pct_of_one_core"] ?? "") + "%"])
        }
        let testCosts = cost.filter { ($0["phase"] ?? "").hasPrefix("test-") }.compactMap { $0["pct_of_one_core"].flatMap(Double.init) }
        if !testCosts.isEmpty {
            crow.append(["real tests (\(testCosts.count))", "every \(traceBin) s", "37.5 each", "151 each", String(format: "%.2f%% mean (%.2f–%.2f%%)", mean(testCosts), testCosts.min()!, testCosts.max()!)])
        }
        md += table(["phase", "`ps` cadence", "seconds", "`ps` calls", "CPU, % of one core"], crow) + "\n"
        md += "During a test the trace is sampled every 0.25 s only to measure lag; the protocol itself needs 13 `ps` calls (window endpoints).\n\n"
    }

    // ---- Notes --------------------------------------------------------------------------
    let notes = readLines(dir + "/notes.txt")
    if !notes.isEmpty { md += "## Notes written during the run\n\n" + notes.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
    md += "## Limits of this evidence\n\n"
    md += "- One Mac, one session, synthetic culprits; daemon behaviour differs across hardware, displays and macOS versions.\n"
    md += "- The protocol as specified (18 s + 3 × 6 s) lasts 36 s; ADR 0033 says \"about 42 seconds\". The spike runs 36 s plus a 1.5 s tail used only for the lag shift.\n"
    md += "- Sham tests come from the same minutes of load as the real tests; other kinds of natural load (video, scrolling, a first Spotlight index) may fluctuate differently. Longer `record` runs during normal use extend the calibration.\n"
    md += "- Thresholds are floored at the ADR 0022 starting values (3× and 2×); the raw calibrated values are in the table and in `calibration.csv`.\n"
    md += "- The microphone rule (ADR 0034 §2) is not implemented here: the spike only ever pauses its own processes.\n"
    try? md.write(toFile: dir + "/results.md", atomically: true, encoding: .utf8)
    print("wrote \(dir)/results.md")
}
