// Throwaway prototype for the 24-hour budget measurement (ADR 0028). Not Farol code.
//
// It contains every part the real sentinel will have, so its cost is realistic:
// FarolCore counters + detector + SQLite history, the memory-pressure monitor,
// daemon queries through /bin/ps via posix_spawn (ADR 0021), a 60 s in-memory ring with
// the top 20 apps every 10 s, the notifications framework (loaded, no prompt), an XPC
// listener, and a menu bar item with a menu.
//
// Every 5 minutes it appends its own cost to
// ~/Library/Application Support/FarolSpike/measure.csv (CPU includes `ps` children).
import AppKit
import Darwin
import FarolCore
import Foundation
import UserNotifications

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/FarolSpike", directoryHint: .isDirectory)
let csvURL = supportDir.appending(path: "measure.csv")

// MARK: - Daemon watching through /bin/ps

let watchList: Set<String> = [
    "WindowServer", "mds_stores", "mds", "mdworker_shared", "photoanalysisd", "mediaanalysisd",
    "backupd", "softwareupdated", "cloudd", "bird", "coreaudiod", "fileproviderd",
]

/// Finds watched daemons by name *and* system path, using libproc (works without root).
func discoverDaemons() -> [pid_t: String] {
    var result: [pid_t: String] = [:]
    let count = proc_listallpids(nil, 0)
    var pids = [pid_t](repeating: 0, count: Int(count) + 64)
    let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    var pathBuffer = [CChar](repeating: 0, count: 4096)
    for pid in pids.prefix(Int(max(n, 0))) where pid > 1 {
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
        let path = String(cString: pathBuffer)
        guard path.hasPrefix("/System/") || path.hasPrefix("/usr/") else { continue }
        let name = (path as NSString).lastPathComponent
        if watchList.contains(name) { result[pid] = name }
    }
    return result
}

/// Runs `/bin/ps -o pid=,time= -p …` with posix_spawn: no shell, empty environment,
/// no inherited descriptors, capped output. Returns cumulative CPU seconds per PID.
func queryDaemonCPU(_ pids: [pid_t]) -> [pid_t: Double] {
    guard !pids.isEmpty else { return [:] }
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return [:] }
    var actions: posix_spawn_file_actions_t? = nil
    var attr: posix_spawnattr_t? = nil
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
    let args = ["/bin/ps", "-o", "pid=,time=", "-p", pids.map(String.init).joined(separator: ",")]
    let argv = args.map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = [nil]
    var child: pid_t = 0
    let rc = posix_spawn(&child, "/bin/ps", &actions, &attr, argv, envp)
    close(fds[1])
    var output = [UInt8]()
    var buffer = [UInt8](repeating: 0, count: 4096)
    if rc == 0 {
        while output.count < 65_536 {
            let r = read(fds[0], &buffer, buffer.count)
            if r <= 0 { break }
            output += buffer[0..<r]
        }
        var status: Int32 = 0
        waitpid(child, &status, 0)
    }
    close(fds[0])
    posix_spawn_file_actions_destroy(&actions)
    posix_spawnattr_destroy(&attr)
    argv.forEach { free($0) }

    var result: [pid_t: Double] = [:]
    for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let pid = pid_t(parts[0]) else { continue }
        let seconds = parts[1].split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
        result[pid] = seconds
    }
    return result
}

// MARK: - Engine (confined to one utility queue)

final class Engine: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "farol.spike.sentinel", qos: .utility)
    let started = Date()
    let monitor: MemoryPressureMonitor
    let sampler = ProcessSampler()
    let store: HistoryStore
    var detector = AnomalyDetector()
    var lastSnapshot: SystemSnapshot?
    var minuteLoads: [SystemLoad] = []
    var minuteStart = Date().timeIntervalSince1970

    var daemons: [pid_t: String] = [:]
    var lastDaemonCPU: [pid_t: (time: Double, cpu: Double)] = [:]
    var lastDaemonQuery = 0.0
    var lastDiscovery = 0.0
    var psCalls = 0
    var daemonHighEvents = 0

    var ring: [[ProcessDelta]] = []  // top 20 apps, every 10 s, last 60 s
    var lastProcessSnapshot: ProcessSnapshot?
    var lastRingSample = 0.0

    var incidentID: Int64?
    var incidentStarted = 0.0
    var pendingRecords: [IncidentProcessRecord] = []
    var incidents = 0
    var lastReport = Date()
    var lastPurge = Date()
    var timers: [DispatchSourceTimer] = []

    var onStateChange: ((Bool) -> Void)?

    init(storeURL: URL) throws {
        monitor = MemoryPressureMonitor(queue: queue)
        store = try HistoryStore(url: storeURL)
        try store.closeDanglingIncidents()
        super.init()
    }

    func start() {
        let tick = DispatchSource.makeTimerSource(queue: queue)
        tick.schedule(deadline: .now(), repeating: 2.0, leeway: .milliseconds(500))
        tick.setEventHandler { [unowned self] in self.idleTick() }
        tick.resume()
        timers.append(tick)
    }

    private var uptime: Double { ProcessInfo.processInfo.systemUptime }

    func idleTick() {
        guard let now = SystemCounters.read(memoryPressure: monitor.current) else { return }
        defer { lastSnapshot = now }
        guard let previous = lastSnapshot else { return }
        let load = SystemLoad(from: previous, to: now, cores: SystemCounters.coreCount)
        minuteLoads.append(load)

        // Daemons: rescan PIDs every 5 min; query on suspicion (at most every 10 s) or every 30 s.
        let t = uptime
        if t - lastDiscovery > 300 { daemons = discoverDaemons(); lastDiscovery = t }
        let suspicious = load.busyCores > (detector.baseline ?? load.busyCores) + 0.3
        if t - lastDaemonQuery >= 30 || (suspicious && t - lastDaemonQuery >= 10) { queryDaemons(at: t) }

        // Ring: top 20 apps every 10 s.
        if t - lastRingSample >= 10 { sampleRing(at: t) }

        if let event = detector.observe(load, at: t) {
            switch event {
            case .started(let reasons): beginIncident(reasons)
            case .ended: endIncident()
            }
        }
        if incidentID != nil { incidentTick() }

        if Date().timeIntervalSince1970 - minuteStart >= 60 { flushMinute() }
        if Date().timeIntervalSince(lastReport) >= 300 { report() }
        if Date().timeIntervalSince(lastPurge) >= 3600 {
            try? store.purge(olderThan: Date().timeIntervalSince1970 - 7 * 86_400)
            lastPurge = Date()
        }
    }

    func queryDaemons(at t: Double) {
        let cpu = queryDaemonCPU(Array(daemons.keys))
        psCalls += 1
        for (pid, seconds) in cpu {
            if let last = lastDaemonCPU[pid], t > last.time {
                let share = (seconds - last.cpu) / (t - last.time)
                if share >= 0.25 { daemonHighEvents += 1 }
            }
            lastDaemonCPU[pid] = (t, seconds)
        }
        lastDaemonQuery = t
    }

    func sampleRing(at t: Double) {
        let snapshot = sampler.snapshot()
        if let previous = lastProcessSnapshot {
            let top = ProcessSampler.deltas(from: previous, to: snapshot)
                .sorted { $0.cpuSeconds > $1.cpuSeconds }.prefix(20)
            ring.append(Array(top))
            if ring.count > 6 { ring.removeFirst() }
        }
        lastProcessSnapshot = snapshot
        lastRingSample = t
    }

    func beginIncident(_ reasons: AnomalyReason) {
        let now = Date().timeIntervalSince1970
        guard let id = try? store.beginIncident(at: now, reasons: reasons, bootTime: SystemCounters.bootTime() ?? 0)
        else { return }
        incidentID = id
        incidentStarted = now
        incidents += 1
        // The ring becomes the incident's first samples.
        let records = ring.enumerated().flatMap { index, deltas in
            deltas.map { IncidentProcessRecord(time: now - Double(ring.count - index) * 10, delta: $0) }
        }
        try? store.append(records, incident: id)
        onStateChange?(true)
    }

    func incidentTick() {
        // Detailed sampling every 2 s tick (the spike uses the idle cadence), capped at 10 minutes.
        let snapshot = sampler.snapshot()
        if let previous = lastProcessSnapshot, Date().timeIntervalSince1970 - incidentStarted < 600 {
            let now = Date().timeIntervalSince1970
            pendingRecords += ProcessSampler.deltas(from: previous, to: snapshot)
                .map { IncidentProcessRecord(time: now, delta: $0) }
        }
        lastProcessSnapshot = snapshot
        if pendingRecords.count > 500, let id = incidentID {
            try? store.append(pendingRecords, incident: id)
            pendingRecords.removeAll(keepingCapacity: true)
        }
    }

    func endIncident() {
        guard let id = incidentID else { return }
        try? store.append(pendingRecords, incident: id)
        pendingRecords.removeAll()
        try? store.endIncident(id, at: Date().timeIntervalSince1970)
        incidentID = nil
        onStateChange?(false)
    }

    func flushMinute() {
        guard !minuteLoads.isEmpty else { return }
        let avg = minuteLoads.map(\.busyCores).reduce(0, +) / Double(minuteLoads.count)
        let minute = SystemMinute(
            start: minuteStart, averageBusyCores: avg,
            peakBusyCores: minuteLoads.map(\.busyCores).max() ?? 0,
            swapped: minuteLoads.contains { $0.swapoutsPerSecond > 0 },
            peakMemoryPressure: minuteLoads.compactMap(\.memoryPressure).max(),
            peakThermal: minuteLoads.map(\.thermal).max() ?? .nominal)
        try? store.append(minute)
        minuteLoads.removeAll(keepingCapacity: true)
        minuteStart = Date().timeIntervalSince1970
    }

    // MARK: Self-measurement

    var lastCPU = 0.0
    var lastWakeups: UInt64 = 0
    var lastReportUptime = ProcessInfo.processInfo.systemUptime

    func report() {
        var usage = rusage_info_v6()
        _ = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
            }
        }
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let ownCPU = Double(usage.ri_user_time + usage.ri_system_time) * Double(tb.numer) / Double(tb.denom) / 1e9
        var children = rusage()
        getrusage(RUSAGE_CHILDREN, &children)
        let childCPU = Double(children.ru_utime.tv_sec + children.ru_stime.tv_sec)
            + Double(children.ru_utime.tv_usec + children.ru_stime.tv_usec) / 1e6
        let totalCPU = ownCPU + childCPU
        let wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups
        let elapsed = ProcessInfo.processInfo.systemUptime - lastReportUptime
        let line = String(
            format: "%@,%.0f,%@,%.4f,%.4f,%.2f,%.2f,%d,%d,%d\n",
            ISO8601DateFormatter().string(from: Date()), Date().timeIntervalSince(started),
            incidentID == nil ? "idle" : "incident",
            100 * (totalCPU - lastCPU) / elapsed, 100 * childCPU / max(Date().timeIntervalSince(started), 1),
            Double(usage.ri_phys_footprint) / 1e6, Double(wakeups - lastWakeups) / elapsed,
            psCalls, incidents, daemonHighEvents)
        if let handle = try? FileHandle(forWritingTo: csvURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
        lastCPU = totalCPU
        lastWakeups = wakeups
        lastReportUptime = ProcessInfo.processInfo.systemUptime
        lastReport = Date()
    }

    // MARK: XPC (loaded so its cost is counted; accepts no connections)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        false
    }
}

// MARK: - App

try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
if !FileManager.default.fileExists(atPath: csvURL.path) {
    FileManager.default.createFile(
        atPath: csvURL.path,
        contents: Data(
            "time,elapsed_s,mode,cpu_pct_interval,child_cpu_pct_total,footprint_mb,wakeups_per_s,ps_calls,incidents,daemon_high_events\n"
                .utf8))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let engine: Engine
do {
    engine = try Engine(storeURL: supportDir.appending(path: "history.sqlite"))
} catch {
    NSLog("FarolSpike cannot open history: \(error)")
    exit(1)
}

let xpc = NSXPCListener.anonymous()
xpc.delegate = engine
xpc.resume()

UNUserNotificationCenter.current().getNotificationSettings { _ in }

let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
func setIcon(_ incident: Bool) {
    item.button?.image = NSImage(
        systemSymbolName: incident ? "exclamationmark.triangle.fill" : "light.beacon.max",
        accessibilityDescription: "Farol measurement")
}
setIcon(false)
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Farol — measuring for 24 h (ADR 0028)", action: nil, keyEquivalent: ""))
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Quit measurement", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
item.menu = menu

engine.onStateChange = { incident in DispatchQueue.main.async { setIcon(incident) } }
engine.start()
app.run()
