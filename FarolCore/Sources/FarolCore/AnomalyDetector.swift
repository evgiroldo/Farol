/// Why the sentinel considers the system abnormal.
public struct AnomalyReason: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Busy cores well above this Mac's own baseline.
    public static let cpu = AnomalyReason(rawValue: 1 << 0)
    /// Sustained swapping (a rate, not a single page).
    public static let swapping = AnomalyReason(rawValue: 1 << 1)
    /// Memory pressure at warning or critical.
    public static let memoryPressure = AnomalyReason(rawValue: 1 << 2)
    /// Thermal state serious or critical.
    public static let thermal = AnomalyReason(rawValue: 1 << 3)
}

/// Decides when an incident starts and ends, from a stream of `SystemLoad` values.
///
/// Fixes found in the sentinel spike and the first review (ADRs 0011, 0019):
/// - **Hysteresis**: entering needs a higher threshold than staying, and ending needs
///   several consecutive calm samples plus a minimum duration, so an on/off load does
///   not split into many incidents.
/// - **Calm-only baseline**: the baseline learns only from calm samples outside
///   incidents, so neither a spike nor a long incident becomes "normal".
/// - **Swap as a rate**: occasional swapouts are normal on small-memory Macs; only a
///   sustained rate counts.
/// - **Wake suppression**: the burst of work after waking from sleep is not an incident.
///
/// Known limitation, pending architecture decisions (review items C1 and C3): a single
/// daemon using less than one extra core (e.g. `mds_stores` at 50%) does not trigger an
/// incident, and incidents have no maximum duration.
public struct AnomalyDetector: Sendable {
    public struct Configuration: Sendable {
        /// Busy cores above baseline needed to count a sample as abnormal (enter).
        public var enterMargin = 1.0
        /// Busy cores above baseline still considered abnormal while in an incident.
        public var stayMargin = 0.5
        /// Swapout rate (pages per second) that counts as swapping. 64 pages of 16 KB is 1 MB/s.
        public var swapoutsPerSecond = 64.0
        /// Consecutive abnormal samples needed to start an incident.
        public var enterSamples = 2
        /// Consecutive calm samples needed to end an incident.
        public var exitSamples = 5
        /// Minimum incident duration in seconds.
        public var minimumDuration: Double = 30
        /// Weight of each new sample in the baseline moving average.
        public var baselineWeight = 0.05

        public init() {}
    }

    public enum Event: Sendable, Equatable {
        case started(reasons: AnomalyReason)
        case ended(duration: Double)
    }

    public private(set) var baseline: Double?
    public private(set) var incidentStart: Double?
    public var isInIncident: Bool { incidentStart != nil }

    private let config: Configuration
    private var abnormalStreak = 0
    private var calmStreak = 0
    private var pendingReasons: AnomalyReason = []
    private var suppressedUntil: Double = -.infinity

    public init(configuration: Configuration = Configuration()) {
        config = configuration
    }

    /// Ignores samples until `time` — call on wake from sleep. Detection restarts from
    /// scratch afterwards; an incident already in progress is not affected.
    public mutating func suppress(until time: Double) {
        suppressedUntil = max(suppressedUntil, time)
        abnormalStreak = 0
        pendingReasons = []
    }

    /// Feeds one load sample taken at `time` (seconds, monotonic).
    public mutating func observe(_ load: SystemLoad, at time: Double) -> Event? {
        if time < suppressedUntil && !isInIncident { return nil }
        guard let base = baseline else {
            baseline = load.busyCores
            return nil
        }
        let reasons = reasons(for: load, baseline: base)

        if let start = incidentStart {
            calmStreak = reasons.isEmpty ? calmStreak + 1 : 0
            if calmStreak >= config.exitSamples && time - start >= config.minimumDuration {
                incidentStart = nil
                calmStreak = 0
                return .ended(duration: time - start)
            }
            return nil
        }

        if reasons.isEmpty {
            // Learn only from calm samples, so a spike never becomes "normal".
            baseline = base * (1 - config.baselineWeight) + load.busyCores * config.baselineWeight
            abnormalStreak = 0
            pendingReasons = []
            return nil
        }
        abnormalStreak += 1
        pendingReasons.formUnion(reasons)
        guard abnormalStreak >= config.enterSamples else { return nil }
        incidentStart = time
        abnormalStreak = 0
        defer { pendingReasons = [] }
        return .started(reasons: pendingReasons)
    }

    private func reasons(for load: SystemLoad, baseline: Double) -> AnomalyReason {
        var r: AnomalyReason = []
        let margin = isInIncident ? config.stayMargin : config.enterMargin
        if load.busyCores > baseline + margin { r.insert(.cpu) }
        if load.swapoutsPerSecond >= config.swapoutsPerSecond { r.insert(.swapping) }
        if let pressure = load.memoryPressure, pressure >= .warning { r.insert(.memoryPressure) }
        if load.thermal >= .serious { r.insert(.thermal) }
        return r
    }
}
