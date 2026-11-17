import Testing

@testable import FarolCore

@Suite("AnomalyDetector")
struct AnomalyDetectorTests {
    func load(
        _ cores: Double, swapRate: Double = 0, pressure: MemoryPressure? = .normal, thermal: ThermalLevel = .nominal
    ) -> SystemLoad {
        SystemLoad(busyCores: cores, swapoutsPerSecond: swapRate, memoryPressure: pressure, thermal: thermal)
    }

    /// Feeds `values` every 2 s starting at `start`; returns the events with their times.
    func feed(
        _ d: inout AnomalyDetector, _ values: [SystemLoad], start: Double = 0
    ) -> [(Double, AnomalyDetector.Event)] {
        var events: [(Double, AnomalyDetector.Event)] = []
        for (i, l) in values.enumerated() {
            let t = start + Double(i) * 2
            if let e = d.observe(l, at: t) { events.append((t, e)) }
        }
        return events
    }

    func calm(_ n: Int) -> [SystemLoad] { Array(repeating: load(0.9), count: n) }

    @Test func steadyLoadNeverStartsAnIncident() {
        var d = AnomalyDetector()
        #expect(feed(&d, calm(200)).isEmpty)
    }

    @Test func sustainedSpikeStartsAfterTenSeconds() {
        var d = AnomalyDetector()
        let events = feed(&d, calm(10) + Array(repeating: load(3.1), count: 6))
        #expect(events.count == 1)
        #expect(events.first?.0 == 28)  // fifth abnormal sample, 10 s after the first
        #expect(events.first?.1 == .started(reasons: .cpu))
    }

    /// Regression for the 24-hour measurement (ADR 0039): half of 122 incidents lasted under a
    /// minute on a Mac that never felt slow. A burst shorter than 10 s must not start one.
    @Test func burstShorterThanTenSecondsIsIgnored() {
        var d = AnomalyDetector()
        #expect(feed(&d, calm(10) + Array(repeating: load(3.1), count: 4) + calm(10)).isEmpty)
    }

    @Test func singleBlipIsIgnored() {
        var d = AnomalyDetector()
        #expect(feed(&d, calm(10) + [load(4)] + calm(10)).isEmpty)
    }

    /// Regression for the sentinel spike: a load switching on/off every 4 s split into
    /// two incidents. Once started, with hysteresis it must stay one incident.
    @Test func onOffLoadStaysOneIncident() {
        var d = AnomalyDetector()
        var values = calm(20) + Array(repeating: load(3.1), count: 6)
        for i in 0..<30 { values.append(load((i / 2) % 2 == 0 ? 3.1 : 0.9)) }  // 60 s of 4 s on/off
        values += calm(10)
        let events = feed(&d, values)
        #expect(events.count == 2)
        guard case .started = events.first?.1, case .ended = events.last?.1 else {
            Issue.record("expected one start and one end, got \(events)")
            return
        }
    }

    /// Regression for the sentinel spike: the baseline rose from 0.9 to 1.2 during an
    /// incident. It must stay frozen, including the samples that precede the start.
    @Test func baselineIsFrozenDuringIncident() throws {
        var d = AnomalyDetector()
        _ = feed(&d, calm(20))
        let before = try #require(d.baseline)
        _ = feed(&d, Array(repeating: load(3.5), count: 40), start: 40)
        #expect(d.isInIncident)
        #expect(d.baseline == before)
    }

    @Test func incidentLastsAtLeastMinimumDuration() {
        var d = AnomalyDetector()
        let events = feed(&d, calm(5) + Array(repeating: load(3), count: 5) + calm(30))
        guard events.count == 2, case .ended(let duration) = events[1].1 else {
            Issue.record("expected start and end, got \(events)")
            return
        }
        #expect(duration >= 30)
    }

    @Test(arguments: [
        (SystemLoad(busyCores: 0.9, swapoutsPerSecond: 200), AnomalyReason.swapping),
        (SystemLoad(busyCores: 0.9, memoryPressure: .warning), .memoryPressure),
        (SystemLoad(busyCores: 0.9, thermal: .serious), .thermal),
    ])
    func nonCPUReasonsStartIncidents(_ abnormal: SystemLoad, _ reason: AnomalyReason) {
        var d = AnomalyDetector()
        let events = feed(&d, calm(5) + Array(repeating: abnormal, count: 5))
        #expect(events.map(\.1) == [.started(reasons: reason)])
    }

    /// Review finding: on small-memory Macs occasional swapouts are the steady state and
    /// must not keep the sentinel in incident mode.
    @Test func occasionalSwapoutsAreNormal() {
        var d = AnomalyDetector()
        #expect(feed(&d, Array(repeating: load(0.9, swapRate: 5), count: 100)).isEmpty)
    }

    /// Review finding: an unavailable reading must never count as "normal" or "abnormal".
    @Test func unavailablePressureIsNotAReason() {
        var d = AnomalyDetector()
        #expect(feed(&d, Array(repeating: load(0.9, pressure: nil), count: 50)).isEmpty)
    }

    @Test func wakeBurstIsSuppressed() {
        var d = AnomalyDetector()
        _ = feed(&d, calm(10))
        d.suppress(until: 50)
        // Burst right after wake (t = 20…48) is ignored; a burst after it is detected.
        let during = feed(&d, Array(repeating: load(4), count: 15), start: 20)
        #expect(during.isEmpty)
        let after = feed(&d, Array(repeating: load(4), count: 6), start: 60)
        #expect(after.map(\.1) == [.started(reasons: .cpu)])
    }
}
