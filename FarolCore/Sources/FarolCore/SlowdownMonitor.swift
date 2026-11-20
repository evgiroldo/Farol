import Darwin
import Dispatch
import Foundation

/// A slowdown that has ended, kept so the person can still see what happened.
public struct PastSlowdown: Sendable, Equatable {
    public let started: Date
    public let ended: Date
    public let cause: Cause
}

/// Everything the UI shows. All usage values are measured.
public struct MonitorState: Sendable, Equatable {
    public var verdict: Verdict = .calm
    /// Busiest apps over `windowSeconds`, most processor use first.
    public var apps: [AppUsage] = []
    /// Length of the window the usage was measured over; 0 until the first measurement.
    public var windowSeconds: Double = 0
    /// When the current slowdown started, if the Mac is slow now.
    public var slowSince: Date?
    public var lastSlowdown: PastSlowdown?
    public var updated = Date()

    public init() {}
}

/// Watches the Mac and decides when it is slow and why (ADRs 0021, 0032, 0039, 0042, 0043).
///
/// Every 2 s it reads the global counters and feeds the `AnomalyDetector`. Per-process
/// snapshots are taken every 60 s while the Mac looks quiet, every 10 s under suspicion
/// and every 5 s during a slowdown. Watched system processes are queried through `ps`
/// every 60 s, or every 10 s under suspicion. Nothing is written to disk (ADR 0044).
public actor SlowdownMonitor {
    static let tick = 2.0
    static let quietSnapshot = 60.0
    static let suspiciousSnapshot = 10.0
    static let incidentSnapshot = 5.0
    static let heartbeat = 60.0
    static let suspiciousQuery = 10.0
    static let discovery = 900.0
    static let quietWindow = 60.0
    static let incidentWindow = 120.0
    static let suspicionMargin = 0.3
    static let wakeSuppression = 60.0

    private let queue = DispatchQueue(label: "io.github.evgiroldo.farol.monitor", qos: .utility)
    private let pressure: MemoryPressureMonitor
    private var detector = AnomalyDetector()
    private var sampler = ProcessSampler()
    private var grouper: UsageGrouper
    private var watcher: DaemonWatcher

    private var lastCounters: SystemSnapshot?
    private var ring: [(time: Double, snapshot: ProcessSnapshot)] = []
    private var lastDiscovery = -Double.infinity
    private var lastQuery = -Double.infinity
    private var lastRelief = 0.0
    private var daemons: [DaemonActivity] = []
    private var reasons: AnomalyReason?
    private var state = MonitorState()

    public init(knowledgeBase: KnowledgeBase) {
        pressure = MemoryPressureMonitor(queue: queue)
        grouper = UsageGrouper(knowledgeBase: knowledgeBase)
        watcher = DaemonWatcher(knowledgeBase: knowledgeBase)
    }

    /// Runs until the calling task is cancelled, calling `onUpdate` whenever the state changes.
    public func run(_ onUpdate: @escaping @Sendable (MonitorState) -> Void) async {
        while !Task.isCancelled {
            if step() { onUpdate(state) }
            try? await Task.sleep(for: .seconds(Self.tick), tolerance: .milliseconds(500))
        }
    }

    /// Takes a fresh measurement now (for example when the person opens the card).
    public func refreshNow() -> MonitorState {
        snapshot(at: uptime)
        return state
    }

    /// Call after the Mac wakes: the burst of work after waking is not a slowdown (ADR 0019).
    public func systemDidWake() {
        detector.suppress(until: uptime + Self.wakeSuppression)
        lastCounters = nil
        ring.removeAll()
    }

    private var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// One tick. Returns `true` when the state changed.
    private func step() -> Bool {
        guard let now = SystemCounters.read(memoryPressure: pressure.current) else { return false }
        defer { lastCounters = now }
        guard let previous = lastCounters else { return false }
        let load = SystemLoad(from: previous, to: now, cores: SystemCounters.coreCount)
        let t = uptime
        var changed = false

        if let event = detector.observe(load, at: t) {
            switch event {
            case .started(let r):
                reasons = r
                state.slowSince = Date()
            case .ended:
                if let started = state.slowSince, case .slow(let cause) = state.verdict {
                    state.lastSlowdown = PastSlowdown(started: started, ended: Date(), cause: cause)
                }
                reasons = nil
                state.slowSince = nil
                relieveMemory(at: t)
            }
            changed = true
        }

        if t - lastDiscovery >= Self.discovery {
            watcher.discover()
            lastDiscovery = t
        }
        let suspicious = load.busyCores > (detector.baseline ?? load.busyCores) + Self.suspicionMargin
        if t - lastQuery >= Self.heartbeat || (suspicious && t - lastQuery >= Self.suspiciousQuery) {
            daemons = watcher.query(at: t)
            lastQuery = t
            changed = true
        }

        let cadence =
            reasons != nil ? Self.incidentSnapshot : suspicious ? Self.suspiciousSnapshot : Self.quietSnapshot
        if changed || t - (ring.last?.time ?? -.infinity) >= cadence {
            snapshot(at: t)
            changed = true
        }
        if t - lastRelief >= 3_600 { relieveMemory(at: t) }
        return changed
    }

    private func snapshot(at t: Double) {
        let snap = sampler.snapshot()
        ring.append((t, snap))
        let window = reasons != nil ? Self.incidentWindow : Self.quietWindow
        // Keep the window, plus at least one earlier snapshot to measure against.
        while ring.count > 2, t - ring[1].time >= window { ring.removeFirst() }
        guard ring.count >= 2, let first = ring.first else { return }

        let usage = grouper.group(from: first.snapshot, to: snap)
        let system = merged(usage.system, daemons)
        state.apps = usage.apps.sorted { $0.cores > $1.cores }.prefix(8).map { $0 }
        state.windowSeconds = t - first.time
        state.verdict = Verdict.decide(reasons: reasons, apps: usage.apps, system: system)
        state.updated = Date()
    }

    /// System processes seen directly (owned by this user) and through `ps`, by entry.
    private func merged(_ direct: [SystemWork], _ queried: [DaemonActivity]) -> [SystemWork] {
        var result: [String: SystemWork] = [:]
        for w in direct { result[w.entryID] = w }
        for d in queried {
            let w = SystemWork(
                entryID: d.entryID, cores: d.coreShare, sustained: d.busySeconds >= DaemonWatcher.sustainedSeconds)
            if let existing = result[d.entryID], existing.cores >= w.cores && !w.sustained { continue }
            result[d.entryID] = w
        }
        return Array(result.values)
    }

    /// Returns freed allocator memory to the system (ADR 0042).
    private func relieveMemory(at t: Double) {
        malloc_zone_pressure_relief(nil, 0)
        lastRelief = t
    }
}
