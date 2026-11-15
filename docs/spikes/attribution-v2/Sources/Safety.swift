// Throwaway validation prototype (attribution spike v2). NOT Farol code.
// Everything that sends a signal lives in this file (plus the time-out kill of a stuck tool
// child in Common.swift). Search for "SIGNAL SITE" to review every one of them.
//
// Rules (task brief, ADR 0023, ADR 0034):
//  - Signals go only to processes the spike started itself, or to Apple-signed WebKit helpers
//    that macOS holds the spike's own web app responsible for (ADR 0034 §3).
//  - Before every SIGSTOP the target's PID + start time + executable path + owner are compared
//    with what was recorded when the spike launched/discovered it.
//  - A separate watchdog process resumes everything when its pipe closes (ADR 0034 §1).
import Darwin
import Foundation

// MARK: - Watchdog process (role `_watchdog`)

/// Runs in its own session. stdin = command pipe from the spike, stdout = acknowledgements.
/// Protocol (text lines):
///   ARM <seq> <deadline seconds> <n>   followed by n lines:  P <pid> <startSec> <startUsec> <path>
///   CLEAR <seq>                         cancels the deadline (everything was resumed)
///   QUIT                                final sweep, then exit
/// Replies `ACK <seq>`. End-of-file on stdin (the spike died or quit) = resume everything at once.
func runWatchdog() -> Never {
    signal(SIGHUP, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    signal(SIGPIPE, SIG_IGN)
    let owner = getuid()
    var listed: [Identity] = []  // union of everything ever listed; resuming is identity-checked
    var deadline: Double? = nil  // monotonic clock
    var pending: [UInt8] = []

    func log(_ s: String) { fputs("[watchdog \(getpid())] \(wallNow()) \(s)\n", stderr) }

    func sweep(_ why: String) {
        var resumed = 0
        for id in listed {
            // Same identity check as the spike: never signal a PID that was reused.
            guard id.uid == owner, let info = procInfo(id.pid), info.id == id else { continue }
            // SIGNAL SITE (watchdog): SIGCONT to a listed process whose identity still matches.
            // Sent whether or not the process reports "stopped": SIGCONT to a running process
            // is harmless, and this does not depend on the stopped flag being reliable.
            if kill(id.pid, SIGCONT) == 0 { resumed += info.status == P_STATUS_STOPPED ? 1 : 0 }
        }
        log("sweep (\(why)): \(listed.count) listed, \(resumed) were stopped and got resumed")
    }

    enum Input { case line(String), timeout, eof }
    func nextLine() -> Input {
        while true {
            if let nl = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[..<nl], as: UTF8.self)
                pending.removeSubrange(...nl)
                return .line(line)
            }
            var waitMs: Int32 = 60_000
            if let d = deadline {
                let left = d - monoNow()
                if left <= 0 { return .timeout }
                waitMs = Int32(min(60_000, max(1, left * 1000)))
            }
            var p = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, waitMs)
            if r < 0 { if errno == EINTR { continue } else { return .eof } }
            if r == 0 { continue }  // loop re-checks the deadline
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(0, &buf, buf.count)
            if n == 0 { return .eof }
            if n < 0 { if errno == EINTR { continue } else { return .eof } }
            pending.append(contentsOf: buf[0..<n])
            if pending.count > 1_000_000 { return .eof }
        }
    }

    log("started")
    _ = writeAll(fd: 1, "READY\n")
    while true {
        switch nextLine() {
        case .eof:
            // The spike is gone. Resume now, and a few more times in case a stop was in flight.
            for i in 0..<5 {
                sweep("pipe closed, pass \(i + 1)")
                usleep(200_000)
            }
            exit(0)
        case .timeout:
            sweep("deadline reached")
            deadline = nil
        case .line(let line):
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
            guard let cmd = parts.first else { continue }
            if cmd == "ARM", parts.count >= 4, let secs = Double(parts[2]), let n = Int(parts[3]), n >= 0, n <= 256 {
                var ok = true
                for _ in 0..<n {
                    guard case .line(let pl) = nextLine() else {
                        ok = false
                        break
                    }
                    let f = pl.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
                    guard f.count == 5, f[0] == "P", let pid = pid_t(f[1]), pid > 1, let s = UInt64(f[2]),
                        let u = UInt64(f[3])
                    else {
                        ok = false
                        break
                    }
                    let id = Identity(pid: pid, startSec: s, startUsec: u, path: f[4], uid: owner)
                    if !listed.contains(id) { listed.append(id) }
                }
                if ok {
                    deadline = monoNow() + min(max(secs, 0.5), 30)
                    _ = writeAll(fd: 1, "ACK \(parts[1])\n")
                } else {
                    log("malformed ARM; resuming everything")
                    sweep("malformed command")
                    _ = writeAll(fd: 1, "ERR\n")
                }
            } else if cmd == "CLEAR", parts.count >= 2 {
                deadline = nil
                _ = writeAll(fd: 1, "ACK \(parts[1])\n")
            } else if cmd == "QUIT" {
                sweep("quit")
                exit(0)
            } else {
                log("unknown command; resuming everything")
                sweep("unknown command")
            }
        }
    }
}

// MARK: - Watchdog client

final class Watchdog {
    let pid: pid_t
    private let cmdFD: Int32
    private let ackFD: Int32
    private var seq = 0

    private init(pid: pid_t, cmdFD: Int32, ackFD: Int32) {
        self.pid = pid
        self.cmdFD = cmdFD
        self.ackFD = ackFD
    }

    /// Starts the watchdog in its own session and waits for its READY line.
    static func start(exe: String, logPath: String) -> Watchdog? {
        var cmd: [Int32] = [0, 0]
        var ack: [Int32] = [0, 0]
        guard pipe(&cmd) == 0, pipe(&ack) == 0 else { return nil }
        let spec = SpawnSpec(exe: exe, args: ["_watchdog"], setsid: true, fdMap: [(cmd[0], 0), (ack[1], 1)], logPath: logPath)
        let child = spawn(spec)
        close(cmd[0])
        close(ack[1])
        guard let child else {
            close(cmd[1])
            close(ack[0])
            return nil
        }
        let w = Watchdog(pid: child.pid, cmdFD: cmd[1], ackFD: ack[0])
        guard readLine(fd: ack[0], timeout: 3) == "READY" else {
            w.quit()
            return nil
        }
        return w
    }

    /// Sends the full list of processes about to be stopped plus a deadline; true only when the
    /// watchdog acknowledged. No SIGSTOP may be sent before this returns true.
    func arm(_ ids: [Identity], deadline: Double) -> Bool {
        seq += 1
        var msg = "ARM \(seq) \(deadline) \(ids.count)\n"
        for id in ids {
            guard !id.path.contains("\n") else { return false }
            msg += "P \(id.pid) \(id.startSec) \(id.startUsec) \(id.path)\n"
        }
        guard writeAll(fd: cmdFD, msg) else { return false }
        return readLine(fd: ackFD, timeout: 2) == "ACK \(seq)"
    }

    func clear() -> Bool {
        seq += 1
        guard writeAll(fd: cmdFD, "CLEAR \(seq)\n") else { return false }
        return readLine(fd: ackFD, timeout: 2) == "ACK \(seq)"
    }

    /// Asks the watchdog to do a final sweep and exit, then reaps it. No signal is sent to it.
    func quit() {
        _ = writeAll(fd: cmdFD, "QUIT\n")
        close(cmdFD)  // end-of-file also makes it sweep and exit
        close(ackFD)
        var status: Int32 = 0
        let until = monoNow() + 5
        while monoNow() < until {
            let r = waitpid(pid, &status, WNOHANG)
            if r == pid || (r < 0 && errno != EINTR) { return }
            usleep(50_000)
        }
    }
}

// MARK: - Children the spike starts

/// A process the spike started itself. `lifeline` is the write end of a pipe whose read end is
/// the child's fd 3: when the spike dies or closes it, the child exits on its own (no signal).
final class Child {
    let label: String
    let id: Identity
    let disclaimed: Bool
    var lifeline: Int32
    var reaped = false
    init(label: String, id: Identity, disclaimed: Bool, lifeline: Int32) {
        self.label = label
        self.id = id
        self.disclaimed = disclaimed
        self.lifeline = lifeline
    }
}

enum Safety {
    static let lock = NSRecursiveLock()
    static var aborting = false
    static var paused: [Identity] = []
    static var children: [Child] = []
    static var watchdog: Watchdog?
    /// Folders of generated files to remove on exit: (directory, file-name prefix).
    static var cleanupDirs: [(String, String)] = []
    static var signalSources: [DispatchSourceSignal] = []
}

/// Starts one of the spike's own executables in its own session (no controlling terminal) and
/// records its identity immediately. `exe` must be a fully resolved path.
func startChild(label: String, exe: String, args: [String], disclaim: Bool, logPath: String) -> Child? {
    Safety.lock.lock()
    let aborting = Safety.aborting
    Safety.lock.unlock()
    if aborting { return nil }
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return nil }
    let spec = SpawnSpec(exe: exe, args: args, setsid: true, disclaim: disclaim, fdMap: [(fds[0], 3)], logPath: logPath)
    let spawned = spawn(spec)
    close(fds[0])
    guard let spawned else {
        close(fds[1])
        return nil
    }
    // The child is not reaped yet, so this PID is certainly the process we just created.
    guard let info = procInfo(spawned.pid), info.id.path == exe, info.id.uid == getuid() else {
        close(fds[1])  // lifeline closed: the child exits by itself
        var st: Int32 = 0
        while waitpid(spawned.pid, &st, 0) < 0 && errno == EINTR {}
        return nil
    }
    let c = Child(label: label, id: info.id, disclaimed: spawned.disclaimed, lifeline: fds[1])
    Safety.lock.lock()
    Safety.children.append(c)
    Safety.lock.unlock()
    return c
}

private func waitExit(_ c: Child, seconds: Double) -> Bool {
    let until = monoNow() + seconds
    var status: Int32 = 0
    while true {
        let r = waitpid(c.id.pid, &status, WNOHANG)
        if r == c.id.pid || (r < 0 && errno == ECHILD) {
            c.reaped = true
            return true
        }
        if monoNow() >= until { return false }
        usleep(20_000)
    }
}

/// Ends a spike-owned child: closes its lifeline (it exits by itself); only if that fails,
/// SIGTERM and then SIGKILL, each after re-checking its identity.
func stopChild(_ c: Child) {
    Safety.lock.lock()
    defer { Safety.lock.unlock() }
    guard !c.reaped else { return }
    if let info = verify(c.id), info.status == P_STATUS_STOPPED {
        // SIGNAL SITE (stopChild): our own child is still stopped; wake it so it can exit.
        kill(c.id.pid, SIGCONT)
    }
    if c.lifeline >= 0 {
        close(c.lifeline)
        c.lifeline = -1
    }
    if waitExit(c, seconds: 2) { return }
    if verify(c.id) != nil {
        // SIGNAL SITE (stopChild): our own, un-reaped child ignored the closed lifeline.
        kill(c.id.pid, SIGTERM)
    }
    if waitExit(c, seconds: 1.5) { return }
    if verify(c.id) != nil {
        // SIGNAL SITE (stopChild): last resort for our own, un-reaped child.
        kill(c.id.pid, SIGKILL)
    }
    _ = waitExit(c, seconds: 2)
}

func stopAllChildren() {
    Safety.lock.lock()
    let list = Safety.children
    // Close every lifeline first so they all wind down in parallel.
    for c in list where !c.reaped && c.lifeline >= 0 {
        if let info = verify(c.id), info.status == P_STATUS_STOPPED {
            // SIGNAL SITE (stopAllChildren): wake our own stopped child so it can exit.
            kill(c.id.pid, SIGCONT)
        }
        close(c.lifeline)
        c.lifeline = -1
    }
    Safety.lock.unlock()
    for c in list { stopChild(c) }
    Safety.lock.lock()
    Safety.children.removeAll { $0.reaped }
    Safety.lock.unlock()
}

// MARK: - Pause and resume (the only SIGSTOP in the spike)

/// ADR 0023 protections that can be checked on a live process. nil = may be paused.
func protectionProblem(_ info: ProcInfo) -> String? {
    if info.id.pid <= 1 || info.id.pid == getpid() { return "protected pid" }
    if info.id.uid != getuid() { return "not owned by the current user" }
    if info.status == P_STATUS_STOPPED { return "already stopped" }
    if info.flags & P_FLAG_TRACED != 0 { return "being traced or debugged" }
    if info.tdev != UInt32.max { return "attached to a terminal" }
    return nil
}

/// Resumes every process in `ids` that still matches its recorded identity.
func resumeGroup(_ ids: [Identity]) {
    Safety.lock.lock()
    defer { Safety.lock.unlock() }
    for id in ids {
        if verify(id) != nil {
            // SIGNAL SITE (resumeGroup): SIGCONT to a process we stopped, identity re-checked.
            kill(id.pid, SIGCONT)
        }
        Safety.paused.removeAll { $0 == id }
    }
}

/// Stops the whole group or nothing. Returns nil on success, or the reason it refused/aborted
/// (in which case everything already stopped has been resumed).
func pauseGroup(_ ids: [Identity], watchdog: Watchdog, deadline: Double) -> String? {
    Safety.lock.lock()
    defer { Safety.lock.unlock() }
    if Safety.aborting { return "aborting" }
    // 1. Refuse the whole group if any member fails identity or protection checks (ADR 0034 §2).
    for id in ids {
        guard let info = verify(id) else { return "identity mismatch before pause (pid \(id.pid))" }
        if let p = protectionProblem(info) { return "pid \(id.pid) is \(p)" }
    }
    // 2. The watchdog gets the list first and must acknowledge (ADR 0034 §1).
    guard watchdog.arm(ids, deadline: deadline) else { return "watchdog did not acknowledge" }
    // 3. Stop, re-checking identity immediately before and after each signal (ADR 0023).
    var stopped: [Identity] = []
    for id in ids {
        guard let info = verify(id), protectionProblem(info) == nil else {
            resumeGroup(stopped)
            _ = watchdog.clear()
            return "identity or protection check failed right before SIGSTOP (pid \(id.pid))"
        }
        Safety.paused.append(id)  // recorded first, so an abort handler can resume it
        // SIGNAL SITE (pauseGroup): the only SIGSTOP in the spike.
        kill(id.pid, SIGSTOP)
        stopped.append(id)
        if verify(id) == nil {
            // The PID no longer is the process we meant (it exited, or the PID was reused in the
            // tiny window between check and signal). Undo our own stop at once and abort.
            // SIGNAL SITE (pauseGroup): SIGCONT to the PID we just stopped, after a mismatch.
            kill(id.pid, SIGCONT)
            resumeGroup(stopped)
            _ = watchdog.clear()
            return "identity mismatch right after SIGSTOP (pid \(id.pid)); resumed"
        }
    }
    return nil
}

// MARK: - Cleanup and abort

/// Removes generated files `<prefix>*` from a folder the spike created, then the empty folder.
func removeGeneratedFiles(dir: String, prefix: String) {
    let fm = FileManager.default
    guard !prefix.isEmpty, let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
    for n in names where n.hasPrefix(prefix) || n == ".DS_Store" { try? fm.removeItem(atPath: dir + "/" + n) }
    rmdir(dir)
}

/// Resumes everything, ends every child, removes generated files. Safe to call more than once.
func shutdownEverything() {
    Safety.lock.lock()
    Safety.aborting = true
    let paused = Safety.paused
    Safety.lock.unlock()
    resumeGroup(paused)
    stopAllChildren()
    for (dir, prefix) in Safety.cleanupDirs { removeGeneratedFiles(dir: dir, prefix: prefix) }
    Safety.cleanupDirs.removeAll()
    Safety.watchdog?.quit()
    Safety.watchdog = nil
}

/// Ctrl-C, SIGTERM and SIGHUP: resume and clean up, then exit. If the spike is killed in a way
/// it cannot catch, the watchdog (pipe closed) and the lifelines do the same job.
func installAbortHandlers() {
    signal(SIGPIPE, SIG_IGN)
    let queue = DispatchQueue(label: "abort")
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
        src.setEventHandler {
            fputs("\nInterrupted (signal \(sig)) at \(wallNow()): resuming and cleaning up…\n", stderr)
            shutdownEverything()
            fputs("Everything resumed and stopped. End time: \(wallNow())\n", stderr)
            _exit(130)
        }
        src.resume()
        Safety.signalSources.append(src)
    }
}
