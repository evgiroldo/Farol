// Throwaway validation prototype (attribution spike v2). NOT Farol code.
// Data collection: passive recording, stimuli management, real cause tests, occlusion,
// the watchdog safety check and the read-only probe. All signals go through Safety.swift.
import CoreGraphics
import Darwin
import Foundation
import IOKit.pwr_mgt
import Security

// MARK: - Run context

final class Run {
    let dir: String
    let exe: String
    let webBundle: String
    let webExe: String
    var daemons: [String: [pid_t]] = [:]
    var displayAssertion: IOPMAssertionID = 0

    init(dir: String) {
        self.dir = dir
        exe = executablePath()
        let buildDir = (exe as NSString).deletingLastPathComponent
        webBundle = buildDir + "/FarolSpikeWeb.app"
        webExe = webBundle + "/Contents/MacOS/FarolSpikeWeb"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        daemons = discoverDaemons()
    }

    var logPath: String { dir + "/children.log" }

    func note(_ s: String) {
        print("  note: \(s)")
        appendLine(dir + "/notes.txt", "\(wallNow())  \(s)")
    }

    /// Records the exact wall-clock window of a phase (to exclude it from other measurements).
    func phase(_ name: String, _ body: () -> Void) {
        let start = wallNow()
        print("\n== \(name) — start \(start)")
        fflush(stdout)
        body()
        let end = wallNow()
        print("== \(name) — end \(end)")
        fflush(stdout)
        if !FileManager.default.fileExists(atPath: dir + "/phases.csv") { appendLine(dir + "/phases.csv", "phase,start,end") }
        appendLine(dir + "/phases.csv", "\(name),\(start),\(end)")
    }

    func keepDisplayAwake() {
        guard displayAssertion == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Farol attribution spike (test load on screen)" as CFString, &displayAssertion)
    }

    func describeDaemons() -> String {
        daemonNames.map { "\($0)=\(daemons[$0]?.map(String.init).joined(separator: "+") ?? "not found")" }.joined(separator: " ")
    }
}

/// nil when a window can actually be shown and seen; otherwise why not.
func screenProblem() -> String? {
    if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return "the display is asleep" }
    if let d = CGSessionCopyCurrentDictionary() as? [String: Any] {
        if (d["CGSSessionScreenIsLocked"] as? Bool) == true { return "the screen is locked" }
        if (d["kCGSSessionOnConsoleKey"] as? Bool) == false { return "this login session is not on the screen" }
    } else {
        return "no window session (not logged in at the screen?)"
    }
    return nil
}

// MARK: - Passive recording

/// Records cumulative daemon CPU at a steady cadence. Pauses nothing, opens nothing.
func record(run: Run, label: String, seconds: Double, interval: Double) {
    let path = run.dir + "/record-\(label).csv"
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let out = FileHandle(forWritingAtPath: path) else {
        print("cannot write \(path)")
        return
    }
    out.write(Data(("wall,mono_before,mono_after,epoch," + daemonNames.joined(separator: ",") + "\n").utf8))
    let cost0 = selfCPU()
    let calls0 = toolCalls
    let t0 = monoNow()
    var epoch = 0
    var k = 0
    var rows = 0
    var lastProgress = t0
    while true {
        let target = t0 + Double(k) * interval
        if target - t0 > seconds { break }
        sleepUntil(target)
        let before = monoNow()
        let s = sampleDaemons(run.daemons)
        let after = monoNow()
        if s.count < daemonNames.count {
            // A daemon restarted or was not reported: rediscover, and start a new epoch so the
            // analysis never computes a delta across two different processes.
            run.daemons = discoverDaemons()
            epoch += 1
        }
        let cols = daemonNames.map { s[$0].map(f2) ?? "" }.joined(separator: ",")
        out.write(Data("\(wallNow()),\(f3(before)),\(f3(after)),\(epoch),\(cols)\n".utf8))
        rows += 1
        if after - lastProgress >= 60 {
            lastProgress = after
            print(String(format: "  recording %@: %.0f of %.0f s", label, after - t0, seconds))
            fflush(stdout)
        }
        k += 1
        // If we fell behind (the Mac slept, heavy load), skip the missed slots instead of bursting.
        let now = monoNow()
        if now > t0 + Double(k) * interval + interval { k = Int((now - t0) / interval) + 1 }
    }
    try? out.close()
    let wall = monoNow() - t0
    let cpu = selfCPU() - cost0
    writeCost(run, phase: "record-\(label)", wall: wall, cpu: cpu, calls: toolCalls - calls0, cadence: interval)
    print(String(format: "  recorded %d samples; spike cost %.3f%% of one core (incl. ps children)", rows, 100 * cpu / wall))
}

func writeCost(_ run: Run, phase: String, wall: Double, cpu: Double, calls: Int, cadence: Double) {
    let path = run.dir + "/cost.csv"
    if !FileManager.default.fileExists(atPath: path) {
        appendLine(path, "phase,wall_s,self_cpu_s_incl_ps_children,pct_of_one_core,ps_calls,cadence_s")
    }
    appendLine(path, "\(phase),\(f2(wall)),\(f3(cpu)),\(String(format: "%.3f", 100 * cpu / max(wall, 0.001))),\(calls),\(cadence)")
}

/// Mean CPU share of each daemon over `seconds`, from two cumulative endpoints.
func measureShares(_ run: Run, seconds: Double) -> [String: Double] {
    let a = sampleDaemons(run.daemons)
    let ta = monoNow()
    sleepFor(seconds)
    let b = sampleDaemons(run.daemons)
    let tb = monoNow()
    var out: [String: Double] = [:]
    for n in daemonNames { if let x = a[n], let y = b[n] { out[n] = (y - x) / (tb - ta) } }
    return out
}

// MARK: - Stimuli

final class Stimuli {
    var web: Child?
    var writer: Child?
    var burnSync: Child?
    var burnRandom: Child?
    var webLevel = 1
    var writerLevel = 1
    var rhythm = "steady"
    var webStatusPath = ""
    var webFrame = ""
    var spotlightDir = ""
    var webLaunches = 0
}

/// Rows (mono, frames per second, visible, on) the web app wrote between two instants.
func webStatus(_ stim: Stimuli, from: Double, to: Double) -> (fps: Double, visible: Double)? {
    var fps: [Double] = []
    var vis: [Double] = []
    for line in readLines(stim.webStatusPath) where !line.hasPrefix("#") {
        let f = line.split(separator: ",")
        guard f.count >= 3, let t = Double(f[0]), t >= from, t <= to, let a = Double(f[1]), let v = Double(f[2]) else { continue }
        fps.append(a)
        vis.append(v)
    }
    return fps.isEmpty ? nil : (mean(fps), mean(vis))
}

func launchWeb(_ run: Run, _ stim: Stimuli) -> Bool {
    stim.webLaunches += 1
    stim.webStatusPath = run.dir + "/web-status-\(stim.webLaunches).csv"
    let args = ["_webapp", "--rhythm", stim.rhythm, "--level", String(stim.webLevel), "--status", stim.webStatusPath]
    guard let c = startChild(label: "web", exe: run.webExe, args: args, disclaim: true, logPath: run.logPath) else {
        run.note("could not start the web app at \(run.webExe)")
        return false
    }
    stim.web = c
    let until = monoNow() + 15
    while monoNow() < until {
        if let line = readLines(stim.webStatusPath).first(where: { $0.hasPrefix("#frame ") }) {
            stim.webFrame = line.dropFirst(7).split(separator: " ").joined(separator: ",")
            break
        }
        if readLines(stim.webStatusPath).contains(where: { $0.hasPrefix("#error") }) { break }
        usleep(100_000)
    }
    if stim.webFrame.isEmpty {
        run.note("the web app did not report a window (see children.log)")
        return false
    }
    let resp = responsiblePid(c.id.pid)
    run.note(
        "web app pid \(c.id.pid), level \(stim.webLevel), rhythm \(stim.rhythm), window frame \(stim.webFrame); "
            + "disclaim requested: \(c.disclaimed); responsible pid: \(resp.map(String.init) ?? "unavailable") "
            + "(\(resp == c.id.pid ? "itself" : "NOT itself"))")
    return true
}

func launchWriter(_ run: Run, _ stim: Stimuli) -> Bool {
    let args = ["_writer", "--dir", stim.spotlightDir, "--rhythm", stim.rhythm, "--level", String(stim.writerLevel)]
    guard let c = startChild(label: "writer", exe: run.exe, args: args, disclaim: false, logPath: run.logPath) else {
        run.note("could not start the writer")
        return false
    }
    stim.writer = c
    return true
}

/// Starts the culprits and decoys. With `tune`, raises the load level (up to 3) until each
/// daemon is comfortably above the 10% minimum, so the tests are not all "below minimum".
func startStimuli(_ run: Run, rhythm: String, tune: Bool, reuse: Stimuli? = nil) -> Stimuli? {
    if let p = screenProblem() {
        run.note("cannot show the test load: \(p)")
        return nil
    }
    guard FileManager.default.isExecutableFile(atPath: run.webExe) else {
        run.note("web app bundle missing; run ./build.sh first")
        return nil
    }
    run.keepDisplayAwake()
    let stim = Stimuli()
    stim.rhythm = rhythm
    stim.webLevel = reuse?.webLevel ?? 1
    stim.writerLevel = reuse?.writerLevel ?? 1
    stim.spotlightDir = run.dir + "/spotlight-test-files"
    Safety.cleanupDirs.append((stim.spotlightDir, writerFilePrefix))
    guard launchWeb(run, stim), launchWriter(run, stim) else { return nil }
    stim.burnSync = startChild(label: "burn-sync", exe: run.exe, args: ["_burn", "--rhythm", rhythm], disclaim: false, logPath: run.logPath)
    stim.burnRandom = startChild(label: "burn-random", exe: run.exe, args: ["_burn", "--rhythm", "random"], disclaim: false, logPath: run.logPath)
    guard stim.burnSync != nil, stim.burnRandom != nil else {
        run.note("could not start the decoys")
        return nil
    }
    sleepFor(6)
    if tune {
        for _ in 0..<3 {
            let s = measureShares(run, seconds: 12)
            let ws = s["WindowServer"] ?? 0
            let mds = s["mds_stores"] ?? 0
            run.note("load check: WindowServer \(pct(ws)) at web level \(stim.webLevel), mds_stores \(pct(mds)) at writer level \(stim.writerLevel)")
            var changed = false
            if ws < 0.20, stim.webLevel < 3, let old = stim.web {
                stopChild(old)
                stim.webLevel += 1
                guard launchWeb(run, stim) else { return nil }
                changed = true
            }
            if mds < 0.20, stim.writerLevel < 3, let old = stim.writer {
                stopChild(old)
                stim.writerLevel += 1
                guard launchWriter(run, stim) else { return nil }
                changed = true
            }
            if !changed { break }
            sleepFor(6)
        }
    }
    // Is the writer's folder really indexed by Spotlight?
    var indexed = 0
    for _ in 0..<5 {
        let out = runTool("/usr/bin/mdfind", ["-onlyin", stim.spotlightDir, "-name", writerFilePrefix], timeout: 5, cap: 1_000_000)
        indexed = out?.split(separator: "\n").count ?? 0
        if indexed > 0 { break }
        sleepFor(3)
    }
    run.note(
        indexed > 0
            ? "Spotlight indexing verified: mdfind -onlyin found \(indexed) of the writer's files"
            : "Spotlight did NOT return the writer's files (mdfind -onlyin found 0): the Spotlight culprit is not valid in this run")
    return stim
}

func stopStimuli(_ run: Run, _ stim: Stimuli?) {
    stopAllChildren()
    for (dir, prefix) in Safety.cleanupDirs { removeGeneratedFiles(dir: dir, prefix: prefix) }
    Safety.cleanupDirs.removeAll()
    if let d = stim?.spotlightDir, FileManager.default.fileExists(atPath: d) {
        run.note("could not remove \(d) completely; please delete it by hand")
    }
}

// MARK: - The web app's process group (ADR 0027 / 0034 §3)

struct GroupMember {
    let id: Identity
    let ppid: pid_t
    let responsible: pid_t?
    /// main | bundle | webkit-helper (these three are paused) | apple-other (macOS service,
    /// recorded but never paused) | outside (anything else: the whole test is refused)
    let kind: String
}

func isAppleSigned(_ pid: pid_t) -> Bool {
    var code: SecCode?
    let attrs = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attrs, SecCSFlags(), &code) == errSecSuccess, let code else { return false }
    var req: SecRequirement?
    guard SecRequirementCreateWithString("anchor apple" as CFString, SecCSFlags(), &req) == errSecSuccess, let req else {
        return false
    }
    return SecCodeCheckValidity(code, SecCSFlags(), req) == errSecSuccess
}

/// The app plus every process of the current user that macOS holds it responsible for, or that
/// is its child. Helpers count as WebKit helpers only when Apple-signed, under
/// /System/…/WebKit.framework/, and started after the app.
func discoverGroup(app: Child, bundle: String) -> [GroupMember] {
    var out = [GroupMember(id: app.id, ppid: getpid(), responsible: responsiblePid(app.id.pid), kind: "main")]
    for pid in allPids() where pid != app.id.pid && pid != getpid() {
        guard let info = procInfo(pid), info.id.uid == getuid() else { continue }
        let resp = responsiblePid(pid)
        guard resp == app.id.pid || info.ppid == app.id.pid else { continue }
        let p = info.id.path
        let startedAfter = (info.id.startSec, info.id.startUsec) >= (app.id.startSec, app.id.startUsec)
        var kind = "outside"
        if p.hasPrefix(bundle + "/") {
            kind = "bundle"
        } else if p.hasPrefix("/System/") || p.hasPrefix("/usr/"), isAppleSigned(pid) {
            // Apple-signed system code attributed to the app. Only WebKit's own helpers started
            // after the app are paused; any other macOS service is recorded and left running.
            kind = p.hasPrefix("/System/") && p.contains("/WebKit.framework/") && startedAfter ? "webkit-helper" : "apple-other"
        }
        out.append(GroupMember(id: info.id, ppid: info.ppid, responsible: resp, kind: kind))
    }
    return out
}

// MARK: - One real cause test

let traceBin = 0.25
let traceTail = 1.5  // extra seconds after the protocol, so windows can be shifted by a lag

/// Runs the ADR 0033 protocol once against `target` and writes a 0.25 s trace.
func runTest(run: Run, stim: Stimuli, target: String, id testId: String, watchdog: Watchdog) {
    let testsPath = run.dir + "/tests.csv"
    if !FileManager.default.fileExists(atPath: testsPath) {
        appendLine(
            testsPath,
            "test,rhythm,target,wall_start,wall_end,group_size,group_pids,stop_times_s,resume_times_s,status,self_cpu_pct,web_fps_obs,web_visible_obs"
        )
    }
    // 1. Who gets paused.
    var ids: [Identity] = []
    var refusal: String? = nil
    switch target {
    case "web":
        guard let app = stim.web else { return }
        let group = discoverGroup(app: app, bundle: run.webBundle)
        let helpersPath = run.dir + "/helpers.csv"
        if !FileManager.default.fileExists(atPath: helpersPath) {
            appendLine(helpersPath, "test,pid,ppid,responsible_pid,app_pid,kind,start_sec,path")
        }
        for m in group {
            appendLine(
                helpersPath,
                "\(testId),\(m.id.pid),\(m.ppid),\(m.responsible.map(String.init) ?? ""),\(app.id.pid),\(m.kind),\(m.id.startSec),\(m.id.path)")
        }
        if group.contains(where: { $0.kind == "outside" }) {
            refusal = "refused: the app's group contains executables outside its bundle (ADR 0034 §3)"
        }
        // DEVIATION from ADR 0034 §3 as written: an Apple-signed macOS service that is not a
        // WebKit helper ("apple-other") does not make the spike refuse; it is left running and
        // reported, so the maintainer can see how often the strict rule would refuse an app.
        ids = group.filter { ["main", "bundle", "webkit-helper"].contains($0.kind) }.map { $0.id }
    case "writer": ids = stim.writer.map { [$0.id] } ?? []
    case "burn-sync": ids = stim.burnSync.map { [$0.id] } ?? []
    case "burn-random": ids = stim.burnRandom.map { [$0.id] } ?? []
    default: return
    }
    guard !ids.isEmpty else { return }
    let wallStart = wallNow()
    if let refusal {
        appendLine(testsPath, "\(testId),\(csvSafe(stim.rhythm)),\(target),\(wallStart),\(wallStart),\(ids.count),\(ids.map { String($0.pid) }.joined(separator: ";")),,,\(refusal),,,")
        run.note("test \(testId): \(refusal)")
        return
    }

    // 2. Trace: one sample every 0.25 s; phase boundaries fall exactly on samples, and each
    //    boundary sample is taken just before the signals of that boundary are sent.
    let tracePath = run.dir + "/trace-\(testId).csv"
    var rows = ["k,rel_before,rel_after," + daemonNames.joined(separator: ",") + ",target_cpu"]
    let perWindow = Int((windowSeconds / traceBin).rounded())
    let firstPause = observationWindows * perWindow
    let pauseKs = Set((0..<cycleCount).map { firstPause + 2 * perWindow * $0 })
    let resumeKs = Set(pauseKs.map { $0 + perWindow })
    let lastK = Int(((protocolSeconds + traceTail) / traceBin).rounded())
    var stops: [Double] = []
    var conts: [Double] = []
    var status = "ok"
    var pausedNow = false
    let cost0 = selfCPU()
    let t0 = monoNow() + 0.3
    for k in 0...lastK {
        sleepUntil(t0 + Double(k) * traceBin)
        let before = monoNow()
        let s = sampleDaemons(run.daemons)
        let targetCPU = ids.compactMap { ownProcessCPU($0.pid) }.reduce(0, +)
        let after = monoNow()
        rows.append(
            "\(k),\(f3(before - t0)),\(f3(after - t0))," + daemonNames.map { s[$0].map(f2) ?? "" }.joined(separator: ",")
                + ",\(f3(targetCPU))")
        if pauseKs.contains(k) {
            if let problem = pauseGroup(ids, watchdog: watchdog, deadline: windowSeconds + 2) {
                status = "aborted: \(problem)"
                break
            }
            pausedNow = true
            stops.append(monoNow() - t0)
        } else if resumeKs.contains(k) {
            resumeGroup(ids)
            pausedNow = false
            conts.append(monoNow() - t0)
            if !watchdog.clear() { status = "aborted: watchdog stopped answering" }
            if status != "ok" { break }
        }
    }
    if pausedNow || status != "ok" {
        resumeGroup(ids)
        _ = watchdog.clear()
    }
    let wall = monoNow() - t0
    let cpu = selfCPU() - cost0
    try? (rows.joined(separator: "\n") + "\n").write(toFile: tracePath, atomically: true, encoding: .utf8)
    let web = webStatus(stim, from: t0, to: t0 + windowSeconds * Double(observationWindows))
    appendLine(
        testsPath,
        "\(testId),\(csvSafe(stim.rhythm)),\(target),\(wallStart),\(wallNow()),\(ids.count),\(ids.map { String($0.pid) }.joined(separator: ";")),"
            + "\(stops.map(f3).joined(separator: ";")),\(conts.map(f3).joined(separator: ";")),\(status),"
            + "\(String(format: "%.2f", 100 * cpu / max(wall, 0.001))),\(web.map { f2($0.fps) } ?? ""),\(web.map { f2($0.visible) } ?? "")")
    writeCost(run, phase: "test-\(testId)", wall: wall, cpu: cpu, calls: lastK + 1, cadence: traceBin)
    print("  test \(testId) [\(target), \(stim.rhythm)]: \(status), paused \(ids.count) process(es) \(stops.count)×")
    fflush(stdout)
    if status != "ok" { run.note("test \(testId): \(status)") }
}

/// A block of tests: targets in round-robin order, `n` rounds.
func runTests(run: Run, stim: Stimuli, targets: [String], n: Int, block: String) {
    guard let wd = Watchdog.start(exe: run.exe, logPath: run.dir + "/watchdog.log") else {
        run.note("the watchdog did not start; no pause test was run")
        return
    }
    Safety.watchdog = wd
    var count = 0
    outer: for round in 1...max(1, n) {
        for target in targets {
            if Safety.aborting { break outer }
            if let p = screenProblem() {
                run.note("tests stopped: \(p)")
                break outer
            }
            runTest(run: run, stim: stim, target: target, id: "\(block)-\(target)-\(round)", watchdog: wd)
            count += 1
            sleepFor(4)  // let the daemons settle between tests
        }
    }
    Safety.watchdog = nil
    wd.quit()
    print("  \(count) tests done in block \(block)")
}

// MARK: - Occlusion (ADR 0033 §7)

func runOcclusion(run: Run, stim: Stimuli, reps: Int, seconds: Double) {
    guard let app = stim.web else { return }
    let path = run.dir + "/occlusion.csv"
    appendLine(path, "rep,state,wall_start,seconds,WindowServer_share,mds_stores_share,web_group_cpu_share,web_fps,web_window_visible")
    let group = discoverGroup(app: app, bundle: run.webBundle).filter { $0.kind != "apple-other" && $0.kind != "outside" }.map { $0.id }
    for rep in 1...max(1, reps) {
        for state in ["visible", "panel", "full"] {
            if Safety.aborting { return }
            var cover: Child? = nil
            if state != "visible" {
                cover = startChild(
                    label: "cover", exe: run.exe, args: ["_cover", "--mode", state, "--frame", stim.webFrame], disclaim: false,
                    logPath: run.logPath)
                if cover == nil { run.note("occlusion: could not open the \(state) cover") }
            }
            sleepFor(3)  // settle
            let wall = wallNow()
            let a = sampleDaemons(run.daemons)
            let ga = group.compactMap { ownProcessCPU($0.pid) }.reduce(0, +)
            let ta = monoNow()
            sleepFor(seconds)
            let b = sampleDaemons(run.daemons)
            let gb = group.compactMap { ownProcessCPU($0.pid) }.reduce(0, +)
            let tb = monoNow()
            let dt = tb - ta
            func share(_ n: String) -> String { if let x = a[n], let y = b[n] { return f3((y - x) / dt) } else { return "" } }
            let web = webStatus(stim, from: ta, to: tb)
            appendLine(
                path,
                "\(rep),\(state),\(wall),\(f2(dt)),\(share("WindowServer")),\(share("mds_stores")),\(f3((gb - ga) / dt)),\(web.map { f2($0.fps) } ?? ""),\(web.map { f2($0.visible) } ?? "")")
            print("  occlusion rep \(rep) \(state): WindowServer \(share("WindowServer")), web fps \(web.map { f2($0.fps) } ?? "?")")
            fflush(stdout)
            if let cover { stopChild(cover) }
        }
    }
}

// MARK: - Watchdog safety check (ADR 0023: "tests that kill the app mid-test")

/// Role `_crashmain`: stands in for the spike's main process. Starts its own watchdog, stops the
/// victim (a spike-owned burner started by the caller), reports, then dies without resuming
/// (`crash`) or hangs past the watchdog's deadline (`hang`).
func runCrashMain(_ a: Args) -> Never {
    let p = a.positional
    guard p.count >= 6, let pid = pid_t(p[1]), let s = UInt64(p[2]), let u = UInt64(p[3]) else { exit(2) }
    let mode = p[0]
    let id = Identity(pid: pid, startSec: s, startUsec: u, path: p[4], uid: getuid())
    guard let wd = Watchdog.start(exe: executablePath(), logPath: p[5]) else {
        print("ERR watchdog did not start")
        exit(1)
    }
    if let problem = pauseGroup([id], watchdog: wd, deadline: mode == "hang" ? 1.0 : 10.0) {
        print("ERR \(problem)")
        exit(1)
    }
    usleep(300_000)
    let c0 = ownProcessCPU(pid) ?? -1
    usleep(300_000)
    let c1 = ownProcessCPU(pid) ?? -1
    print("STOPPED status=\(procInfo(pid)?.status ?? 0) cpuDelta=\(f3(c1 - c0))")
    fflush(stdout)
    if mode == "hang" {
        sleepFor(3.5)  // "hung" app: the watchdog deadline (1 s) must resume the victim meanwhile
        resumeGroup([id])
        wd.quit()
        exit(0)
    }
    _exit(9)  // simulated crash: no resume, no goodbye; the pipe to the watchdog just closes
}

/// Proves on this Mac that (a) SIGSTOP really stops a spike-owned process and it shows as
/// stopped, (b) the watchdog resumes it when the main process dies, (c) the watchdog deadline
/// resumes it when the main process hangs. Pauses only a burner the spike starts itself.
func safetyCheck(run: Run) -> Bool {
    var allOK = true
    for mode in ["crash", "hang"] {
        guard let victim = startChild(label: "victim", exe: run.exe, args: ["_burn", "--rhythm", "steady", "--max-seconds", "30"], disclaim: false, logPath: run.logPath)
        else {
            run.note("safety check: could not start the victim")
            return false
        }
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return false }
        let args = ["_crashmain", mode, String(victim.id.pid), String(victim.id.startSec), String(victim.id.startUsec), victim.id.path, run.dir + "/watchdog-safety.log"]
        let spawned = spawn(SpawnSpec(exe: run.exe, args: args, fdMap: [(fds[1], 1)], logPath: run.logPath))
        close(fds[1])
        let tSpawn = monoNow()
        let line = readLine(fd: fds[0], timeout: 6) ?? "no answer"
        let tStopped = monoNow()
        let wasStopped = line.hasPrefix("STOPPED status=\(P_STATUS_STOPPED) ") && line.hasSuffix("cpuDelta=0.000")
        // Wait until the victim runs again (CPU time advancing and not flagged stopped).
        var resumedAfter: Double? = nil
        let until = monoNow() + 4
        while monoNow() < until {
            let c0 = ownProcessCPU(victim.id.pid) ?? 0
            usleep(100_000)
            let c1 = ownProcessCPU(victim.id.pid) ?? 0
            if c1 - c0 > 0.02, verify(victim.id)?.status != P_STATUS_STOPPED {
                resumedAfter = monoNow() - tStopped
                break
            }
        }
        if let spawned {
            var st: Int32 = 0
            if mode == "hang" {
                while waitpid(spawned.pid, &st, 0) < 0 && errno == EINTR {}
            } else {
                while waitpid(spawned.pid, &st, 0) < 0 && errno == EINTR {}
            }
        }
        close(fds[0])
        let ok = wasStopped && resumedAfter != nil
        allOK = allOK && ok
        run.note(
            "safety check (\(mode)): stop reported \"\(line)\" \(String(format: "%.1f", tStopped - tSpawn)) s after start; "
                + (resumedAfter.map { String(format: "victim running again within %.1f s of that report", $0) } ?? "victim NOT resumed within 4 s")
                + " → \(ok ? "PASS" : "FAIL")")
        stopChild(victim)
    }
    return allOK
}

// MARK: - Probe (read-only; pauses nothing, opens nothing)

func probe(run: Run) {
    print("daemons: \(run.describeDaemons())")
    print("responsibility_get_pid_responsible_for_pid available: \(responsibilityAvailable)")
    print("screen: \(screenProblem() ?? "usable")")
    let s = sampleDaemons(run.daemons)
    print("ps cumulative CPU now: \(daemonNames.map { "\($0)=\(s[$0].map(f2) ?? "?")" }.joined(separator: " "))")
    if let c = startChild(label: "idle", exe: run.exe, args: ["_idle", "--max-seconds", "5"], disclaim: true, logPath: run.logPath) {
        usleep(100_000)
        let info = procInfo(c.id.pid)
        print(
            "spike-started idle child: pid \(c.id.pid) status \(info?.status ?? 0) flags \(String(info?.flags ?? 0, radix: 16)) "
                + "tdev \(String(info?.tdev ?? 0, radix: 16)) disclaim-requested \(c.disclaimed) responsible \(responsiblePid(c.id.pid).map(String.init) ?? "?") "
                + "protection: \(info.flatMap(protectionProblem) ?? "none (may be paused)")")
        stopChild(c)
        print("idle child ended by closing its lifeline: \(c.reaped)")
    } else {
        print("could not start the idle child")
    }
    print("WebKit helper processes of this user right now (pid, responsible pid → its executable, Apple-signed):")
    for pid in allPids() {
        guard let info = procInfo(pid), info.id.uid == getuid(), info.id.path.contains("/WebKit.framework/") else { continue }
        let resp = responsiblePid(pid)
        let respName = resp.flatMap(procPath).map { ($0 as NSString).lastPathComponent } ?? "?"
        print("  \(pid)  resp \(resp.map(String.init) ?? "?") → \(respName)  apple \(isAppleSigned(pid))  \(info.id.path)")
    }
}

/// Rhythms such as "pulsed:4,3" contain a comma; CSV fields here are never quoted.
func csvSafe(_ s: String) -> String { s.replacingOccurrences(of: ",", with: "/") }
