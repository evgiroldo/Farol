// Throwaway validation prototype (attribution spike v2). NOT Farol code.
// The ADR 0033 protocol arithmetic, used identically for sham tests (recordings with no pause)
// and for real tests.
//
// Definitions used here (the ADRs leave some of them open; RESULTS must state them):
//   window share  = (cumulative CPU at window end - at window start) / window length
//   fluctuation   = sample standard deviation (n-1) of the six observation windows, floored at
//                   one `ps` tick per window (0.01 s / 3 s) so a quantised zero cannot divide
//   cycle i       : pause window p_i, then run window r_i; "before" b_i is the run window just
//                   before the pause (the last observation window for i = 1, else r_(i-1))
//   effect_i      = mean(b_i, r_i) - p_i          share_i = effect_i / mean(b_i, r_i)
//   effect        = mean of the three effect_i    ratio = effect / fluctuation
//   strict pattern = every p_i < b_i and every r_i > p_i   (ADR 0022 "drops every pause and
//                   rises every resume"; happens by chance 272/5040 = 5.4% for random order)
//   same direction = every effect_i > 0
import Foundation

let windowSeconds = 3.0
let observationWindows = 6
let cycleCount = 3
let protocolSeconds = windowSeconds * Double(observationWindows + 2 * cycleCount)  // 36 s
let minimumLoad = 0.10  // ADR 0022 §3: a test is offered at >= 10% of one core
let fluctuationFloor = 0.01 / windowSeconds

struct ProtoResult {
    var windows: [Double]
    var obsMean: Double
    var fluct: Double
    var effects: [Double]
    var shares: [Double]
    var effect: Double
    var ratio: Double
    var strict: Bool
    var sameDirection: Bool
}

func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
func sampleSD(_ xs: [Double]) -> Double {
    guard xs.count > 1 else { return 0 }
    let m = mean(xs)
    return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
}
func median(_ xs: [Double]) -> Double { quantile(xs.sorted(), 0.5) }
/// Quantile of an already sorted array (nearest rank, no interpolation).
func quantile(_ sorted: [Double], _ q: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let i = min(sorted.count - 1, max(0, Int((q * Double(sorted.count)).rounded(.up)) - 1))
    return sorted[i]
}

/// `w` = 12 window shares: 6 observation, then pause/run alternating three times.
func evaluateWindows(_ w: [Double]) -> ProtoResult {
    precondition(w.count == observationWindows + 2 * cycleCount)
    let obs = Array(w[0..<observationWindows])
    var effects: [Double] = []
    var shares: [Double] = []
    var strict = true
    for i in 0..<cycleCount {
        let p = w[observationWindows + 2 * i]
        let r = w[observationWindows + 2 * i + 1]
        let b = w[observationWindows + 2 * i - 1]
        if !(p < b && r > p) { strict = false }
        let base = (b + r) / 2
        effects.append(base - p)
        shares.append(base > 0 ? (base - p) / base : 0)
    }
    let fluct = max(sampleSD(obs), fluctuationFloor)
    let effect = mean(effects)
    return ProtoResult(
        windows: w, obsMean: mean(obs), fluct: fluct, effects: effects, shares: shares, effect: effect,
        ratio: effect / fluct, strict: strict, sameDirection: effects.allSatisfy { $0 > 0 })
}

/// Cumulative CPU over time, with linear interpolation between samples.
struct Series {
    var t: [Double] = []
    var c: [Double] = []

    func at(_ time: Double) -> Double? {
        // 50 ms of tolerance at both ends: a sample's timestamp is the middle of its `ps` call,
        // so the first one sits a few milliseconds after the nominal start.
        guard let first = t.first, let last = t.last, time >= first - 0.05, time <= last + 0.05 else { return nil }
        if time <= first { return c[0] }
        if time >= last { return c[c.count - 1] }
        var lo = 0
        var hi = t.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if t[mid] <= time { lo = mid } else { hi = mid }
        }
        if hi == lo || t[hi] == t[lo] { return c[lo] }
        let f = min(1, max(0, (time - t[lo]) / (t[hi] - t[lo])))
        return c[lo] + f * (c[hi] - c[lo])
    }

    /// Window shares of the protocol starting at `start`; the three cycles are shifted by `shift`
    /// seconds (ADR 0033 §5 per-daemon lag). nil when the series does not cover the windows.
    func protocolWindows(start: Double, shift: Double = 0) -> [Double]? {
        var out: [Double] = []
        for k in 0..<observationWindows {
            guard let a = at(start + windowSeconds * Double(k)), let b = at(start + windowSeconds * Double(k + 1))
            else { return nil }
            out.append((b - a) / windowSeconds)
        }
        let base = start + windowSeconds * Double(observationWindows) + shift
        for k in 0..<(2 * cycleCount) {
            guard let a = at(base + windowSeconds * Double(k)), let b = at(base + windowSeconds * Double(k + 1))
            else { return nil }
            out.append((b - a) / windowSeconds)
        }
        return out
    }
}

// MARK: - Recordings and sham tests

struct Recording {
    var label: String
    var t: [Double] = []
    var epoch: [Int] = []
    var cpu: [String: [Double?]] = [:]
    var interval: Double { t.count > 1 ? (t[t.count - 1] - t[0]) / Double(t.count - 1) : 1 }
    var duration: Double { t.count > 1 ? t[t.count - 1] - t[0] : 0 }
}

/// CSV columns: wall,mono_before,mono_after,epoch,<daemon>… (cumulative CPU seconds, may be empty)
func loadRecording(_ path: String, label: String) -> Recording? {
    let lines = readLines(path)
    guard let header = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init),
        header.count >= 5
    else { return nil }
    let names = Array(header[4...])
    var rec = Recording(label: label)
    for n in names { rec.cpu[n] = [] }
    for line in lines.dropFirst().prefix(2_000_000) {
        let f = line.split(separator: ",", omittingEmptySubsequences: false)
        guard f.count == header.count, let a = Double(f[1]), let b = Double(f[2]), let e = Int(f[3]) else { continue }
        rec.t.append((a + b) / 2)
        rec.epoch.append(e)
        for (i, n) in names.enumerated() { rec.cpu[n]?.append(Double(f[4 + i])) }
    }
    return rec.t.count > 1 ? rec : nil
}

struct Sham {
    var index: Int
    var result: ProtoResult
}

/// Slides the protocol over a no-pause recording, one start per sample. Windows use the samples
/// at multiples of 3 s from the start; a sham is skipped when a sample is missing, the daemon's
/// PID changed, or the spacing is off (the Mac slept, the recorder was late).
func shamTests(_ rec: Recording, daemon: String) -> [Sham] {
    guard let cpu = rec.cpu[daemon] else { return [] }
    let step = max(1, Int((windowSeconds / rec.interval).rounded()))
    let nWin = observationWindows + 2 * cycleCount
    var out: [Sham] = []
    var i = 0
    while i + step * nWin < rec.t.count {
        defer { i += 1 }
        var w: [Double] = []
        var ok = rec.epoch[i] == rec.epoch[i + step * nWin]
        for k in 0..<nWin where ok {
            let a = i + step * k
            let b = a + step
            let dt = rec.t[b] - rec.t[a]
            guard let ca = cpu[a], let cb = cpu[b], abs(dt - windowSeconds) < 0.35, cb >= ca else {
                ok = false
                break
            }
            w.append((cb - ca) / dt)
        }
        if ok { out.append(Sham(index: i, result: evaluateWindows(w))) }
    }
    return out
}

// MARK: - Calibration

struct Calibration {
    var n = 0  // overlapping sham tests (one start per sample)
    var nIndependent = 0  // sham tests that do not overlap in time (start every 36 s)
    var medianLoad = Double.nan
    var medianFluct = Double.nan
    var strictFraction = Double.nan
    var sameDirectionFraction = Double.nan
    var ratioQuantiles: [Double] = []  // 50, 90, 95, 99, 99.9, max
    var thresholdProven = Double.nan  // smallest T with  P(strict and ratio > T) < 1%
    var thresholdLikely = Double.nan  // smallest T with  P(same direction and ratio > T) < 5%
    var thresholdRatioOnly1 = Double.nan  // smallest T with  P(ratio > T) < 1%  (ignoring the pattern)
    var thresholdRatioOnly5 = Double.nan
    var falseProofAt3 = Double.nan  // rate with the uncalibrated ADR 0022 value
    var falseLikelyAt2 = Double.nan
    var falseProofIndependent = Double.nan  // same rule at thresholdProven, non-overlapping subset only
}

/// Smallest threshold T such that fewer than `alpha` of all `n` shams have a value above T.
/// `values` = ratios of the shams that satisfy the rule's pattern condition.
func thresholdFor(values: [Double], n: Int, alpha: Double) -> Double {
    guard n > 0 else { return .nan }
    let allowed = max(0, Int((alpha * Double(n)).rounded(.up)) - 1)  // count must be < alpha * n
    let sorted = values.sorted(by: >)
    if sorted.count <= allowed { return 0 }
    return max(0, sorted[allowed])  // at most `allowed` values are strictly above this
}

func calibrate(_ shams: [Sham], step: Int) -> Calibration {
    var c = Calibration()
    let r = shams.map { $0.result }
    c.n = r.count
    guard c.n > 0 else { return c }
    // Non-overlapping subset: greedily keep shams at least one protocol length apart.
    let stride = step * (observationWindows + 2 * cycleCount)
    var indep: [ProtoResult] = []
    var next = Int.min
    for s in shams where s.index >= next {
        indep.append(s.result)
        next = s.index + stride
    }
    c.nIndependent = indep.count
    c.medianLoad = median(r.map { $0.obsMean })
    c.medianFluct = median(r.map { $0.fluct })
    let n = Double(c.n)
    c.strictFraction = Double(r.filter { $0.strict }.count) / n
    c.sameDirectionFraction = Double(r.filter { $0.sameDirection }.count) / n
    let ratios = r.map { $0.ratio }.sorted()
    c.ratioQuantiles = [0.5, 0.9, 0.95, 0.99, 0.999].map { quantile(ratios, $0) } + [ratios.last ?? .nan]
    c.thresholdProven = thresholdFor(values: r.filter { $0.strict }.map { $0.ratio }, n: c.n, alpha: 0.01)
    c.thresholdLikely = thresholdFor(values: r.filter { $0.sameDirection }.map { $0.ratio }, n: c.n, alpha: 0.05)
    c.thresholdRatioOnly1 = thresholdFor(values: ratios, n: c.n, alpha: 0.01)
    c.thresholdRatioOnly5 = thresholdFor(values: ratios, n: c.n, alpha: 0.05)
    c.falseProofAt3 = Double(r.filter { $0.strict && $0.ratio > 3 }.count) / n
    c.falseLikelyAt2 = Double(r.filter { $0.sameDirection && $0.ratio > 2 }.count) / n
    let t = c.thresholdProven
    c.falseProofIndependent = Double(indep.filter { $0.strict && $0.ratio > t }.count) / Double(max(1, indep.count))
    return c
}

enum Verdict: String {
    case proven, likely, inconclusive
}

func verdict(_ r: ProtoResult, proven: Double, likely: Double) -> Verdict {
    if r.strict && r.ratio > proven { return .proven }
    if r.sameDirection && r.ratio > likely { return .likely }
    return .inconclusive
}

// MARK: - Lag (ADR 0033 §5)

/// Mean CPU share in consecutive bins after an event, averaged over the given event times.
func responseCurve(_ s: Series, events: [Double], bin: Double, bins: Int) -> [Double]? {
    var acc = [Double](repeating: 0, count: bins)
    for e in events {
        for j in 0..<bins {
            guard let a = s.at(e + bin * Double(j)), let b = s.at(e + bin * Double(j + 1)) else { return nil }
            acc[j] += (b - a) / bin
        }
    }
    return acc.map { $0 / Double(max(1, events.count)) }
}

struct Lag {
    var runLevel: Double
    var pauseLevel: Double
    var drop: Double?  // seconds after SIGSTOP until the share is below the midpoint
    var recover: Double?  // seconds after SIGCONT until the share is above the midpoint
}

/// Lag from the mean response curves (bins of `bin` seconds, 3 s long). Levels are the last
/// second of each phase. Reported only when the step is clear (> 2% of a core).
func lagFrom(dropCurve: [Double], riseCurve: [Double], bin: Double) -> Lag {
    let tail = max(1, Int((1.0 / bin).rounded()))
    let run = mean(Array(riseCurve.suffix(tail)))
    let paused = mean(Array(dropCurve.suffix(tail)))
    var lag = Lag(runLevel: run, pauseLevel: paused, drop: nil, recover: nil)
    guard run - paused > 0.02 else { return lag }
    let mid = (run + paused) / 2
    if let j = dropCurve.firstIndex(where: { $0 <= mid }) { lag.drop = Double(j) * bin }
    if let j = riseCurve.firstIndex(where: { $0 >= mid }) { lag.recover = Double(j) * bin }
    return lag
}
