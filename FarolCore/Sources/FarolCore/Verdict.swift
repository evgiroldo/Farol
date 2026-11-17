import Foundation

/// What one app (or one command-line tool) did over a time window. All values are measured.
public struct AppUsage: Sendable, Equatable, Identifiable {
    /// The `.app` bundle path, or `"tool:"` plus the executable name for processes outside any app.
    public let id: String
    /// Executable or bundle name, sanitized; the UI shows the bundle's display name when it can.
    public let name: String
    public let bundlePath: String?
    /// Average processor use over the window, in cores (1.0 = one full core).
    public let cores: Double
    /// Memory in use at the end of the window, in bytes.
    public let footprint: UInt64
    /// Bytes written to disk over the window.
    public let diskBytesWritten: UInt64
    public let processCount: Int

    public init(
        id: String, name: String, bundlePath: String?, cores: Double, footprint: UInt64,
        diskBytesWritten: UInt64, processCount: Int
    ) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.cores = cores
        self.footprint = footprint
        self.diskBytesWritten = diskBytesWritten
        self.processCount = processCount
    }
}

/// A system process from the knowledge base doing work. Measured.
public struct SystemWork: Sendable, Equatable {
    public let entryID: String
    /// Processor use, in cores.
    public let cores: Double
    /// Busy for at least `DaemonWatcher.sustainedSeconds`.
    public let sustained: Bool

    public init(entryID: String, cores: Double, sustained: Bool) {
        self.entryID = entryID
        self.cores = cores
        self.sustained = sustained
    }
}

/// The most likely cause of a slowdown, chosen without any test (a *suspect*, ADR 0031).
public enum Cause: Sendable, Equatable {
    /// An app uses far more of the processor than anything else.
    case app(AppUsage)
    /// A system process from the knowledge base is doing the work.
    case systemWork(SystemWork)
    /// The Mac is short of memory; the app using the most memory, if known.
    case memory(AppUsage?)
    /// The Mac is hot and slows itself down to cool off.
    case heat
    /// The Mac is slow but nothing stands out.
    case unclear
}

public enum Verdict: Sendable, Equatable {
    /// Nothing abnormal.
    case calm
    /// The Mac is not slow overall, but a system process has been busy for a while.
    case working(SystemWork)
    /// The Mac is slow (an incident is open).
    case slow(Cause)

    /// An app must use at least this many cores to be named as the suspect. An incident
    /// starts at one core above the baseline (ADR 0039), so this is half of that excess.
    /// Initial value, to be tuned with real use.
    public static let suspectCores = 0.5

    /// Picks the most likely cause. `reasons` are the open incident's reasons, or `nil`
    /// when the Mac is not slow.
    public static func decide(reasons: AnomalyReason?, apps: [AppUsage], system: [SystemWork]) -> Verdict {
        guard let reasons else {
            if let busy = system.filter(\.sustained).max(by: { $0.cores < $1.cores }) { return .working(busy) }
            return .calm
        }
        if reasons.contains(.thermal) { return .slow(.heat) }
        let short = !reasons.isDisjoint(with: [.memoryPressure, .swapping])
        let byMemory = apps.max { $0.footprint < $1.footprint }
        if short && !reasons.contains(.cpu) { return .slow(.memory(byMemory)) }

        let topApp = apps.max { $0.cores < $1.cores }
        let topSystem = system.max { $0.cores < $1.cores }
        if let s = topSystem, s.cores >= DaemonWatcher.busyShare, s.cores > (topApp?.cores ?? 0) {
            return .slow(.systemWork(s))
        }
        if let a = topApp, a.cores >= suspectCores { return .slow(.app(a)) }
        if short { return .slow(.memory(byMemory)) }
        return .slow(.unclear)
    }
}

/// Turns per-process activity into per-app usage (ADR 0027) and system work.
public struct UsageGrouper: Sendable {
    /// Where one process belongs. Worked out once per process, since it never changes.
    enum Owner: Sendable, Equatable {
        case system(entryID: String)
        case app(key: String, name: String, bundle: String?)
    }

    let knowledgeBase: KnowledgeBase
    private var owners: [ProcessIdentity: Owner] = [:]

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    /// Groups the activity between `earlier` and `later`. Processes that match a knowledge
    /// base entry by path become system work instead of an app.
    public mutating func group(from earlier: ProcessSnapshot, to later: ProcessSnapshot) -> (
        apps: [AppUsage], system: [SystemWork]
    ) {
        let seconds = Double(later.time &- earlier.time) / 1e6
        guard seconds > 0 else { return ([], []) }
        if owners.count > later.processes.count * 2 {
            let live = Set(later.processes.map(\.identity))
            owners = owners.filter { live.contains($0.key) }
        }

        struct Group {
            var name: String
            var bundle: String?
            var cpu = 0.0
            var footprint: UInt64 = 0
            var written: UInt64 = 0
            var count = 0
        }
        var groups: [String: Group] = [:]
        var system: [String: Double] = [:]

        let deltas = Dictionary(
            ProcessSampler.deltas(from: earlier, to: later).map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
        for process in later.processes {
            let delta = deltas[process.identity]
            switch owner(of: process) {
            case .system(let entryID):
                system[entryID, default: 0] += (delta?.cpuSeconds ?? 0) / seconds
            case .app(let key, let name, let bundle):
                var g = groups[key] ?? Group(name: name, bundle: bundle)
                g.cpu += delta?.cpuSeconds ?? 0
                g.written &+= delta?.diskBytesWritten ?? 0
                g.footprint &+= process.footprint
                g.count += 1
                groups[key] = g
            }
        }
        let apps = groups.map { key, g in
            AppUsage(
                id: key, name: g.name, bundlePath: g.bundle, cores: g.cpu / seconds, footprint: g.footprint,
                diskBytesWritten: g.written, processCount: g.count)
        }
        let work = system.map { SystemWork(entryID: $0.key, cores: $0.value, sustained: false) }
        return (apps, work)
    }

    private mutating func owner(of process: ProcessSample) -> Owner {
        if let cached = owners[process.identity] { return cached }
        let owner = Self.classify(
            name: process.name, path: ProcessPath.executable(of: process.identity.pid), knowledgeBase)
        owners[process.identity] = owner
        return owner
    }

    static func classify(name: String, path: String?, _ knowledgeBase: KnowledgeBase) -> Owner {
        guard let path else { return .app(key: "tool:" + name, name: name, bundle: nil) }
        if let entry = knowledgeBase.entry(executableName: (path as NSString).lastPathComponent, path: path) {
            return .system(entryID: entry.id)
        }
        guard let bundle = ProcessPath.outermostAppBundle(in: path) else {
            return .app(key: "tool:" + name, name: name, bundle: nil)
        }
        let bundleName = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        return .app(key: bundle, name: ProcessSampler.sanitized(bundleName), bundle: bundle)
    }
}
