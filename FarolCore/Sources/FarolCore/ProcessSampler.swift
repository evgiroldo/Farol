import Darwin
import Foundation

/// Identifies a process across PID reuse and reboots: a PID plus its wall-clock start
/// time in microseconds since 1970.
///
/// It does not change across `execve`, so it cannot tell that a process became another
/// program. Code that acts on a process (pausing, M2) must re-verify the executable path
/// and owner right before acting, and never act on an identity read back from disk
/// (ADR 0019).
public struct ProcessIdentity: Sendable, Hashable {
    public let pid: pid_t
    public let startTime: UInt64

    public init(pid: pid_t, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

/// Cumulative counters of one process at one moment.
public struct ProcessSample: Sendable, Equatable {
    public let identity: ProcessIdentity
    /// Name chosen by the process itself: display only, never a security decision.
    public let name: String
    public let uid: uid_t
    /// User + system CPU time since the process started, in seconds.
    public let cpuSeconds: Double
    public let diskBytesWritten: UInt64
    /// Physical memory footprint in bytes.
    public let footprint: UInt64

    public init(
        identity: ProcessIdentity, name: String, uid: uid_t, cpuSeconds: Double, diskBytesWritten: UInt64,
        footprint: UInt64
    ) {
        self.identity = identity
        self.name = name
        self.uid = uid
        self.cpuSeconds = cpuSeconds
        self.diskBytesWritten = diskBytesWritten
        self.footprint = footprint
    }
}

/// All readable processes at one moment.
public struct ProcessSnapshot: Sendable, Equatable {
    /// When the snapshot was taken, microseconds since 1970 (same clock as `startTime`).
    public let time: UInt64
    public let processes: [ProcessSample]

    public init(time: UInt64, processes: [ProcessSample]) {
        self.time = time
        self.processes = processes
    }
}

/// What one process did between two snapshots.
public struct ProcessDelta: Sendable, Equatable {
    public let identity: ProcessIdentity
    public let name: String
    public let uid: uid_t
    public let cpuSeconds: Double
    public let diskBytesWritten: UInt64
    /// Footprint at the end of the interval, in bytes.
    public let footprint: UInt64

    public init(
        identity: ProcessIdentity, name: String, uid: uid_t, cpuSeconds: Double, diskBytesWritten: UInt64,
        footprint: UInt64
    ) {
        self.identity = identity
        self.name = name
        self.uid = uid
        self.cpuSeconds = cpuSeconds
        self.diskBytesWritten = diskBytesWritten
        self.footprint = footprint
    }
}

/// Reads per-process counters with `proc_pid_rusage` and `proc_pidinfo`. Only processes
/// owned by the current user are readable without privileges (ADR 0007); others are skipped.
///
/// `snapshot()` caches what does not change during a process's life (identity, name, owner)
/// and the PIDs it cannot read, so a repeated snapshot costs about one system call per
/// readable process (ADR 0037). Every cached entry is checked against the kernel's start time
/// on each read, so a reused PID is never mistaken for the old process; the caches are
/// rebuilt every `refreshInterval` seconds.
public struct ProcessSampler: Sendable {
    struct Known: Sendable, Equatable {
        let startAbstime: UInt64
        let identity: ProcessIdentity
        let name: String
        let uid: uid_t
    }

    private let timebase: Double
    /// Seconds between full cache rebuilds (names can change after `execve`; a reused PID
    /// may become readable).
    public var refreshInterval: Double = 60
    var known: [pid_t: Known] = [:]
    var unreadable: Set<pid_t> = []
    private var lastRefresh: UInt64 = 0

    public init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebase = Double(tb.numer) / Double(tb.denom) / 1e9
    }

    /// Samples every readable process except the caller, using the caches.
    public mutating func snapshot() -> ProcessSnapshot {
        let time = Self.nowMicroseconds()
        if Double(time &- lastRefresh) / 1e6 >= refreshInterval {
            known.removeAll(keepingCapacity: true)
            unreadable.removeAll(keepingCapacity: true)
            lastRefresh = time
        }
        let me = getpid()
        let pids = Self.allPIDs()
        var samples: [ProcessSample] = []
        samples.reserveCapacity(known.isEmpty ? pids.count / 2 : known.count + 16)
        for pid in pids where pid > 0 && pid != me && !unreadable.contains(pid) {
            guard let usage = Self.usage(of: pid) else {
                if errno == EPERM { unreadable.insert(pid) }
                continue
            }
            let entry: Known
            if let cached = known[pid], cached.startAbstime == usage.ri_proc_start_abstime {
                entry = cached
            } else {
                guard let fresh = Self.identity(of: pid, startAbstime: usage.ri_proc_start_abstime) else { continue }
                entry = fresh
                known[pid] = fresh
            }
            samples.append(makeSample(entry, usage))
        }
        return ProcessSnapshot(time: time, processes: samples)
    }

    /// Samples one process without any cache, or `nil` if it exited or is not readable.
    /// Use this when acting on a process (it always reflects the kernel's current state).
    public func sample(pid: pid_t) -> ProcessSample? {
        guard let usage = Self.usage(of: pid),
            let entry = Self.identity(of: pid, startAbstime: usage.ri_proc_start_abstime)
        else { return nil }
        return makeSample(entry, usage)
    }

    private func makeSample(_ entry: Known, _ usage: rusage_info_v6) -> ProcessSample {
        ProcessSample(
            identity: entry.identity,
            name: entry.name,
            uid: entry.uid,
            cpuSeconds: Double(usage.ri_user_time &+ usage.ri_system_time) * timebase,
            diskBytesWritten: usage.ri_diskio_byteswritten,
            footprint: usage.ri_phys_footprint
        )
    }

    private static func usage(of pid: pid_t) -> rusage_info_v6? {
        var usage = rusage_info_v6()
        let rc = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return rc == 0 ? usage : nil
    }

    /// Name, owner and start time come from one call, so they describe the same process.
    private static func identity(of pid: pid_t, startAbstime: UInt64) -> Known? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let start = UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
        return Known(
            startAbstime: startAbstime, identity: ProcessIdentity(pid: pid, startTime: start),
            name: name(from: info), uid: info.pbi_uid)
    }

    /// Activity between two snapshots. Idle processes are omitted. A process missing from
    /// `earlier` counts from zero only if it started after `earlier` was taken; otherwise
    /// its baseline is unknown and it is skipped, so lifetime totals never pose as a burst.
    public static func deltas(from earlier: ProcessSnapshot, to later: ProcessSnapshot) -> [ProcessDelta] {
        var previous: [ProcessIdentity: ProcessSample] = [:]
        previous.reserveCapacity(earlier.processes.count)
        for s in earlier.processes { previous[s.identity] = s }
        return later.processes.compactMap { s in
            let p = previous[s.identity]
            guard p != nil || s.identity.startTime >= earlier.time else { return nil }
            let cpu = max(0, s.cpuSeconds - (p?.cpuSeconds ?? 0))
            let before = p?.diskBytesWritten ?? 0
            let written = s.diskBytesWritten >= before ? s.diskBytesWritten - before : 0
            guard cpu > 0 || written > 0 else { return nil }
            return ProcessDelta(
                identity: s.identity, name: s.name, uid: s.uid, cpuSeconds: cpu, diskBytesWritten: written,
                footprint: s.footprint)
        }
    }

    /// Removes control and invisible formatting characters (including bidirectional
    /// overrides) so a process cannot spoof Farol's UI or reports with its name.
    public static func sanitized(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // MARK: Private

    /// Lists PIDs, growing the buffer if processes appeared since the size query.
    private static func allPIDs() -> [pid_t] {
        var capacity = Int(max(proc_listallpids(nil, 0), 0)) + 64
        for _ in 0..<4 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
            guard count > 0 else { return [] }
            if count < capacity { return Array(pids.prefix(count)) }
            capacity *= 2
        }
        return []
    }

    private static func name(from info: proc_bsdinfo) -> String {
        var info = info
        let longName = withUnsafeBytes(of: &info.pbi_name) { Self.string(fromNullTerminated: $0) }
        let raw =
            longName.isEmpty ? withUnsafeBytes(of: &info.pbi_comm) { Self.string(fromNullTerminated: $0) } : longName
        return sanitized(raw)
    }

    private static func string(fromNullTerminated bytes: UnsafeRawBufferPointer) -> String {
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[..<end]), as: UTF8.self)
    }

    static func nowMicroseconds() -> UInt64 {
        var tv = timeval()
        gettimeofday(&tv, nil)
        return UInt64(tv.tv_sec) * 1_000_000 + UInt64(tv.tv_usec)
    }
}
