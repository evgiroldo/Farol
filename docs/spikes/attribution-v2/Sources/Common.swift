// Throwaway validation prototype (attribution spike v2, ADR 0033). NOT Farol code.
// Shared plumbing: clocks, process identity, posix_spawn, `/bin/ps` queries, self-cost.
import Darwin
import Foundation

// MARK: - Clocks and small helpers

/// Monotonic seconds. CLOCK_MONOTONIC_RAW keeps counting while the Mac sleeps, so a sleep
/// shows up as a visible gap in a recording instead of being silently swallowed.
func monoNow() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9 }

let wallFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZ"
    return f
}()
func wallNow() -> String { wallFormatter.string(from: Date()) }

func sleepUntil(_ t: Double) {
    while true {
        let d = t - monoNow()
        if d <= 0 { return }
        usleep(UInt32(min(d, 0.25) * 1e6))
    }
}
func sleepFor(_ s: Double) { sleepUntil(monoNow() + s) }

func f2(_ x: Double) -> String { String(format: "%.2f", x) }
func f3(_ x: Double) -> String { String(format: "%.3f", x) }
func pct(_ x: Double) -> String { String(format: "%.1f%%", 100 * x) }

func appendLine(_ path: String, _ line: String) {
    let data = Data((line + "\n").utf8)
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile()
        h.write(data)
        try? h.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: data)
    }
}

func readLines(_ path: String) -> [String] {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

/// Minimal `--key value` / `--flag` parser.
struct Args {
    var positional: [String] = []
    var options: [String: String] = [:]
    init(_ raw: [String]) {
        var i = 0
        while i < raw.count {
            let a = raw[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < raw.count, !raw[i + 1].hasPrefix("--") {
                    options[key] = raw[i + 1]
                    i += 1
                } else {
                    options[key] = "1"
                }
            } else {
                positional.append(a)
            }
            i += 1
        }
    }
    func str(_ k: String, _ d: String) -> String { options[k] ?? d }
    func num(_ k: String, _ d: Double) -> Double { options[k].flatMap(Double.init) ?? d }
    func int(_ k: String, _ d: Int) -> Int { options[k].flatMap(Int.init) ?? d }
    func flag(_ k: String) -> Bool { options[k] != nil }
}

// MARK: - Process identity (ADR 0023: PID + start time + executable path + owner)

struct Identity: Equatable {
    let pid: pid_t
    let startSec: UInt64
    let startUsec: UInt64
    let path: String
    let uid: uid_t
}

struct ProcInfo {
    let id: Identity
    let ppid: pid_t
    let status: UInt32  // SIDL 1, SRUN 2, SSLEEP 3, SSTOP 4, SZOMB 5
    let flags: UInt32
    let tdev: UInt32  // controlling terminal device, 0xFFFFFFFF when none
}

let P_STATUS_STOPPED: UInt32 = 4
let P_FLAG_TRACED: UInt32 = 2  // PROC_FLAG_TRACED

func procPath(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    return n > 0 ? String(cString: buf) : nil
}

/// Live state of a process, or nil when it does not exist (or is a zombie, or unreadable).
func procInfo(_ pid: pid_t) -> ProcInfo? {
    guard pid > 1 else { return nil }
    var bi = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, size) == size, pid_t(bi.pbi_pid) == pid,
        let path = procPath(pid)
    else { return nil }
    let id = Identity(pid: pid, startSec: bi.pbi_start_tvsec, startUsec: bi.pbi_start_tvusec, path: path, uid: bi.pbi_uid)
    return ProcInfo(id: id, ppid: pid_t(bi.pbi_ppid), status: bi.pbi_status, flags: bi.pbi_flags, tdev: bi.e_tdev)
}

/// Returns the live info only when the PID still is the very process recorded in `id`.
func verify(_ id: Identity) -> ProcInfo? {
    guard let info = procInfo(id.pid), info.id == id, id.uid == getuid() else { return nil }
    return info
}

func allPids() -> [pid_t] {
    let n = proc_listallpids(nil, 0)
    guard n > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(n) + 256)
    let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    return pids.prefix(Int(max(got, 0))).filter { $0 > 1 }
}

private let timebase: (Double) = {
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    return Double(tb.numer) / Double(tb.denom) / 1e9
}()

/// Cumulative CPU seconds of one of the user's own processes (no `ps` needed). nil if unreadable.
func ownProcessCPU(_ pid: pid_t) -> Double? {
    var ru = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &ru) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard r == 0 else { return nil }
    return Double(ru.ri_user_time + ru.ri_system_time) * timebase
}

// MARK: - Responsibility (undocumented, read through dlsym; ADR 0030 §11)

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
private typealias DisclaimFn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

private let responsibleFn: ResponsibleFn? = {
    guard let p = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
    return unsafeBitCast(p, to: ResponsibleFn.self)
}()
private let disclaimFn: DisclaimFn? = {
    guard let p = dlsym(rtldDefault, "responsibility_spawnattrs_setdisclaim") else { return nil }
    return unsafeBitCast(p, to: DisclaimFn.self)
}()

let responsibilityAvailable = responsibleFn != nil

/// PID that macOS holds responsible for `pid`, or nil when unavailable / error.
func responsiblePid(_ pid: pid_t) -> pid_t? {
    guard let fn = responsibleFn else { return nil }
    let r = fn(pid)
    return r > 0 ? r : nil
}

// MARK: - posix_spawn

struct SpawnSpec {
    var exe: String
    var args: [String] = []
    var emptyEnv = false
    var setsid = false
    /// Ask macOS to make the child responsible for itself (what LaunchServices does for apps).
    var disclaim = false
    /// (fd in this process, fd number in the child). Everything else is closed in the child.
    var fdMap: [(Int32, Int32)] = []
    /// stdout+stderr of the child are appended here when not mapped; otherwise /dev/null.
    var logPath: String? = nil
}

struct Spawned {
    let pid: pid_t
    let disclaimed: Bool
}

/// Starts a process with POSIX_SPAWN_CLOEXEC_DEFAULT (no descriptor leaks), no shell.
func spawn(_ s: SpawnSpec) -> Spawned? {
    var fa: posix_spawn_file_actions_t? = nil
    var attr: posix_spawnattr_t? = nil
    posix_spawn_file_actions_init(&fa)
    posix_spawnattr_init(&attr)
    defer {
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
    }
    var flags = Int32(POSIX_SPAWN_CLOEXEC_DEFAULT)
    if s.setsid { flags |= 0x0400 }  // POSIX_SPAWN_SETSID
    posix_spawnattr_setflags(&attr, Int16(flags))
    var disclaimed = false
    if s.disclaim, let fn = disclaimFn { disclaimed = fn(&attr, 1) == 0 }

    let mapped = Set(s.fdMap.map { $0.1 })
    if !mapped.contains(0) { posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0) }
    for (src, dst) in s.fdMap {
        if src == dst {
            posix_spawn_file_actions_addinherit_np(&fa, src)
        } else {
            posix_spawn_file_actions_adddup2(&fa, src, dst)
        }
    }
    if !mapped.contains(1) {
        if let log = s.logPath {
            posix_spawn_file_actions_addopen(&fa, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        } else {
            posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0)
        }
    }
    if !mapped.contains(2) {
        if let log = s.logPath {
            posix_spawn_file_actions_addopen(&fa, 2, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        } else {
            posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0)
        }
    }

    var argv: [UnsafeMutablePointer<CChar>?] = ([s.exe] + s.args).map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let rc: Int32
    if s.emptyEnv {
        let envp: [UnsafeMutablePointer<CChar>?] = [nil]
        rc = posix_spawn(&pid, s.exe, &fa, &attr, argv, envp)
    } else {
        var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        rc = posix_spawn(&pid, s.exe, &fa, &attr, argv, envp)
        envp.forEach { free($0) }
    }
    guard rc == 0, pid > 1 else { return nil }
    return Spawned(pid: pid, disclaimed: disclaimed)
}

/// Reads one line (without the newline) from `fd`, waiting at most `timeout` seconds.
func readLine(fd: Int32, timeout: Double) -> String? {
    var bytes: [UInt8] = []
    let deadline = monoNow() + timeout
    while bytes.count < 8192 {
        let left = deadline - monoNow()
        if left <= 0 { return nil }
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let r = poll(&p, 1, Int32(max(1, left * 1000)))
        if r < 0 && errno == EINTR { continue }
        if r <= 0 { return nil }
        var c: UInt8 = 0
        let n = read(fd, &c, 1)
        if n == 0 { return nil }  // EOF
        if n < 0 { if errno == EINTR { continue } else { return nil } }
        if c == 10 { return String(decoding: bytes, as: UTF8.self) }
        bytes.append(c)
    }
    return nil
}

func writeAll(fd: Int32, _ text: String) -> Bool {
    let bytes = Array(text.utf8)
    var off = 0
    while off < bytes.count {
        let n = bytes[off...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n < 0 { if errno == EINTR { continue } else { return false } }
        off += n
    }
    return true
}

// MARK: - Running a system tool and capturing its output (ADR 0030 §3)

var toolCalls = 0

/// Runs an absolute-path tool: posix_spawn, no shell, empty environment, stdin and stderr on
/// /dev/null, output capped, time-out, child always reaped. The output is untrusted text.
func runTool(_ path: String, _ args: [String], timeout: Double = 2.0, cap: Int = 65536) -> String? {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return nil }
    let spec = SpawnSpec(exe: path, args: args, emptyEnv: true, fdMap: [(fds[1], 1)])
    guard let child = spawn(spec) else {
        close(fds[0])
        close(fds[1])
        return nil
    }
    toolCalls += 1
    close(fds[1])
    var out = [UInt8]()
    var buf = [UInt8](repeating: 0, count: 4096)
    let deadline = monoNow() + timeout
    var failed = false
    while true {
        let left = deadline - monoNow()
        if left <= 0 || out.count > cap {
            failed = true
            break
        }
        var p = pollfd(fd: fds[0], events: Int16(POLLIN), revents: 0)
        let r = poll(&p, 1, Int32(max(1, left * 1000)))
        if r < 0 && errno == EINTR { continue }
        if r <= 0 {
            failed = true
            break
        }
        let n = read(fds[0], &buf, buf.count)
        if n == 0 { break }
        if n < 0 {
            if errno == EINTR { continue }
            failed = true
            break
        }
        out.append(contentsOf: buf[0..<n])
    }
    close(fds[0])
    if failed {
        // SIGNAL SITE (tool child): the tool we spawned a moment ago is stuck or too chatty.
        // It is our own un-reaped child, so its PID cannot have been reused.
        kill(child.pid, SIGKILL)
    }
    var status: Int32 = 0
    while waitpid(child.pid, &status, 0) < 0 && errno == EINTR {}
    return failed ? nil : String(decoding: out, as: UTF8.self)
}

/// Parses `ps` cumulative time: "MM:SS.cc" or "H:MM:SS.cc". Defensive: digits, ':' and '.' only.
func parseCPUTime(_ s: Substring) -> Double? {
    guard !s.isEmpty, s.count <= 20, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ":" || $0 == ".") }) else {
        return nil
    }
    let parts = s.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts.count <= 3 else { return nil }
    var total = 0.0
    for p in parts {
        guard let v = Double(p), v >= 0 else { return nil }
        total = total * 60 + v
    }
    return total
}

/// `/bin/ps -o pid=,time= -p …`: cumulative CPU seconds per PID (10 ms resolution).
func queryCPU(_ pids: [pid_t]) -> [pid_t: Double] {
    guard !pids.isEmpty, pids.count <= 64 else { return [:] }
    let wanted = Set(pids)
    guard let text = runTool("/bin/ps", ["-o", "pid=,time=", "-p", pids.map(String.init).joined(separator: ",")])
    else { return [:] }
    var out: [pid_t: Double] = [:]
    for line in text.split(separator: "\n").prefix(128) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let pid = pid_t(parts[0]), wanted.contains(pid), let t = parseCPUTime(parts[1])
        else { continue }
        out[pid] = t
    }
    return out
}

// MARK: - Watched daemons (ADR 0030 §2: name and path under /System or /usr)

let daemonNames = ["WindowServer", "mds_stores"]

func discoverDaemons() -> [String: [pid_t]] {
    var out: [String: [pid_t]] = [:]
    for pid in allPids() {
        guard let path = procPath(pid), path.hasPrefix("/System/") || path.hasPrefix("/usr/") else { continue }
        let name = (path as NSString).lastPathComponent
        if daemonNames.contains(name) { out[name, default: []].append(pid) }
    }
    for k in out.keys { out[k]?.sort() }
    return out
}

/// One `ps` call for every watched daemon; instances of the same daemon are summed.
/// A daemon is missing from the result when any of its PIDs was not reported.
func sampleDaemons(_ pids: [String: [pid_t]]) -> [String: Double] {
    let cpu = queryCPU(pids.values.flatMap { $0 })
    var out: [String: Double] = [:]
    for (name, list) in pids {
        let vals = list.compactMap { cpu[$0] }
        if vals.count == list.count, !list.isEmpty { out[name] = vals.reduce(0, +) }
    }
    return out
}

// MARK: - Self cost (ADR 0030 §5: always includes reaped `ps` children)

func selfCPU() -> Double {
    func tv(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    var a = rusage()
    var b = rusage()
    getrusage(RUSAGE_SELF, &a)
    getrusage(RUSAGE_CHILDREN, &b)
    return tv(a.ru_utime) + tv(a.ru_stime) + tv(b.ru_utime) + tv(b.ru_stime)
}

func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return "?" }
    var buf = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buf, &size, nil, 0)
    return String(cString: buf)
}

func executablePath() -> String {
    var size: UInt32 = 4096
    var buf = [CChar](repeating: 0, count: Int(size))
    _NSGetExecutablePath(&buf, &size)
    var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
    if realpath(buf, &resolved) != nil { return String(cString: resolved) }
    return String(cString: buf)
}
