import Darwin
import Foundation

/// CPU use of one watched system process between two queries.
public struct DaemonActivity: Sendable, Equatable {
    /// Knowledge base entry that matched the process.
    public let entryID: String
    public let pid: pid_t
    /// Share of one core over the last interval (1.0 = one full core). Measured.
    public let coreShare: Double
    /// Seconds the process has stayed at or above the busy threshold, across queries.
    public let busySeconds: Double

    public init(entryID: String, pid: pid_t, coreShare: Double, busySeconds: Double) {
        self.entryID = entryID
        self.pid = pid
        self.coreShare = coreShare
        self.busySeconds = busySeconds
    }
}

/// Watches the system processes listed in the knowledge base (ADR 0021).
///
/// Most of them run as other users, so their counters cannot be read directly (ADR 0007).
/// Their cumulative CPU time comes from Apple's setuid `/bin/ps`, started with
/// `posix_spawn`: absolute path, fixed arguments, no shell, empty environment, bounded
/// output parsed as untrusted text. Farol never acts on these processes; it only reads.
public struct DaemonWatcher: Sendable {
    /// A process is "busy" at or above this share of one core (ADR 0021).
    public static let busyShare = 0.25
    /// Busy for at least this long counts as sustained (ADR 0021).
    public static let sustainedSeconds = 20.0

    let knowledgeBase: KnowledgeBase
    /// Watched PIDs and their knowledge base entry IDs.
    private(set) var watched: [pid_t: String] = [:]
    private var last: [pid_t: (time: Double, cpu: Double)] = [:]
    private var busy: [pid_t: Double] = [:]

    public init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    /// Number of processes currently watched.
    public var count: Int { watched.count }

    /// Finds the running processes that match a watched knowledge base entry by exact
    /// path (or by name under `/System/` and `/usr/`, see `KnowledgeBase.entry`).
    public mutating func discover() {
        var found: [pid_t: String] = [:]
        for pid in Self.allPIDs() where pid > 1 {
            guard let path = ProcessPath.executable(of: pid),
                let entry = knowledgeBase.entry(executableName: (path as NSString).lastPathComponent, path: path),
                entry.watched
            else { continue }
            found[pid] = entry.id
        }
        watched = found
        last = last.filter { found[$0.key] != nil }
        busy = busy.filter { found[$0.key] != nil }
    }

    /// Adds one process to the watch list (tests).
    mutating func watch(pid: pid_t, entryID: String) { watched[pid] = entryID }

    /// Queries the watched processes once and returns their activity since the previous
    /// query. The first query of a process only sets its starting point.
    public mutating func query(at time: Double) -> [DaemonActivity] {
        guard !watched.isEmpty, let output = Self.runPS(pids: Array(watched.keys)) else { return [] }
        let cpu = Self.parse(output, allowed: Set(watched.keys))
        return update(cpu, at: time)
    }

    /// Applies one set of cumulative CPU readings (seconds per PID). Split out for tests.
    mutating func update(_ cpu: [pid_t: Double], at time: Double) -> [DaemonActivity] {
        var result: [DaemonActivity] = []
        for (pid, seconds) in cpu {
            guard let entryID = watched[pid] else { continue }
            defer { last[pid] = (time, seconds) }
            // A drop in cumulative time means a different process now has this PID.
            guard let previous = last[pid], time > previous.time, seconds >= previous.cpu else {
                busy[pid] = nil
                continue
            }
            let interval = time - previous.time
            let share = (seconds - previous.cpu) / interval
            let busySeconds = share >= Self.busyShare ? (busy[pid] ?? 0) + interval : 0
            busy[pid] = busySeconds
            result.append(DaemonActivity(entryID: entryID, pid: pid, coreShare: share, busySeconds: busySeconds))
        }
        return result.sorted { $0.coreShare > $1.coreShare }
    }

    // MARK: Parsing (untrusted text)

    /// Parses `ps -o pid=,time=` output. Lines that do not parse, PIDs that were not asked
    /// for and absurd values are skipped.
    static func parse(_ text: String, allowed: Set<pid_t>) -> [pid_t: Double] {
        var result: [pid_t: Double] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(4_096) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2, let pid = pid_t(fields[0]), allowed.contains(pid),
                let seconds = cpuSeconds(fields[1])
            else { continue }
            result[pid] = seconds
        }
        return result
    }

    /// Parses a `ps` CPU time: `[days-][hours:]minutes:seconds[.fraction]`.
    static func cpuSeconds(_ text: Substring) -> Double? {
        guard text.count <= 32 else { return nil }
        var days = 0.0
        var rest = text
        if let dash = text.firstIndex(of: "-") {
            guard let d = Double(text[..<dash]), d >= 0 else { return nil }
            days = d
            rest = text[text.index(after: dash)...]
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0, value.isFinite else { return nil }
            total = total * 60 + value
        }
        total += days * 86_400
        return total < 1e9 ? total : nil
    }

    // MARK: System access

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(n, 0))))
    }

    /// Runs `/bin/ps -o pid=,time= -p <pids>` and returns at most 64 KB of its output.
    static func runPS(pids: [pid_t]) -> String? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let arguments = ["/bin/ps", "-o", "pid=,time=", "-p", pids.map(String.init).joined(separator: ",")]
        let argv = arguments.map { strdup($0) } + [nil]
        defer { for pointer in argv { free(pointer) } }
        let environment: [UnsafeMutablePointer<CChar>?] = [nil]

        var child: pid_t = 0
        let rc = posix_spawn(&child, "/bin/ps", &actions, &attributes, argv, environment)
        close(fds[1])
        defer { close(fds[0]) }
        guard rc == 0 else { return nil }

        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while output.count < 65_536 {
            let n = read(fds[0], &buffer, buffer.count)
            if n <= 0 { break }
            output += buffer[0..<n]
        }
        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
        return String(decoding: output, as: UTF8.self)
    }
}

/// Executable path of a process, from public `libproc` calls.
public enum ProcessPath {
    /// Absolute path of the process's executable, or `nil` if it exited or is not readable.
    public static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The outermost `.app` bundle in an executable path (ADR 0027), e.g.
    /// `/Applications/Slack.app` for `/Applications/Slack.app/Contents/Frameworks/…/Slack Helper`.
    public static func outermostAppBundle(in path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var prefix = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            prefix += "/" + component
            if component.count > 4, component.hasSuffix(".app") { return prefix }
        }
        return nil
    }
}
