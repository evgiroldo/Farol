// Throwaway validation prototype (attribution spike v2, ADR 0033). NOT Farol code.
// Single entry point. Public subcommands: record, analyze, test, occlusion, all, plus
// safety-check, probe and selftest. Names starting with "_" are internal roles: the spike
// starts copies of itself as watchdog, load generators and windows.
import Darwin
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let argv = Array(CommandLine.arguments.dropFirst())
let command = argv.first ?? "help"
let args = Args(Array(argv.dropFirst()))

/// The spike folder: the executable lives in <spike>/build/ (or inside the app bundle there).
let spikeDir: String = {
    var p = executablePath()
    while p != "/" && (p as NSString).lastPathComponent != "build" { p = (p as NSString).deletingLastPathComponent }
    return p == "/" ? FileManager.default.currentDirectoryPath : (p as NSString).deletingLastPathComponent
}()

func newRunDir() -> String {
    if let o = args.options["out"] { return o }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return spikeDir + "/data/" + f.string(from: Date())
}

func latestRunDir() -> String? {
    let base = spikeDir + "/data"
    let names = (try? FileManager.default.contentsOfDirectory(atPath: base))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
    return names.last.map { base + "/" + $0 }
}

func minutes(_ s: Double) -> String { String(format: "%.0f min", (s / 60).rounded(.up)) }
let secondsPerTest = 43.0  // 37.5 s protocol + trace tail, start-up and 4 s settling

func announce(_ what: String, estimate: Double, dir: String, pauses: Bool, windows: Bool) {
    print("Farol attribution spike v2 — \(what)")
    print("Estimated duration: about \(minutes(estimate)).  Data folder: \(dir)")
    print(windows ? "Windows WILL appear on screen (a test-load window; small panels during the occlusion step)." : "No window is opened.")
    print(pauses ? "It pauses ONLY processes it starts itself (and the WebKit helpers of its own test window)." : "Nothing is paused.")
    print("START TIME: \(wallNow())   (note it: exclude this run from other measurements)")
    if pauses || windows {
        print("Press Ctrl-C at any time to stop safely. Starting in 5 seconds…")
        sleepFor(5)
    }
}

/// Commands that show the test load need a screen that is on and unlocked; stop early if not.
func requireScreen(_ run: Run) {
    if let p = screenProblem() {
        print("Cannot run: \(p). Wake and unlock the Mac, then start again. Nothing was started.")
        exit(1)
    }
    run.keepDisplayAwake()
}

func finish(_ run: Run) {
    shutdownEverything()
    print("END TIME: \(wallNow())")
}

func requireDaemons(_ run: Run) {
    print("Watched daemons: \(run.describeDaemons())")
    for n in daemonNames where run.daemons[n] == nil { run.note("daemon \(n) not found; its columns stay empty") }
}

/// Writes a synthetic run (known answer) and analyses it: checks the arithmetic end to end
/// without touching any process. CPU only, a fraction of a second.
func selftest() {
    let dir = newRunDir() + "-selftest"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var rows = ["wall,mono_before,mono_after,epoch,WindowServer,mds_stores"]
    var ws = 100.0
    var mds = 50.0
    for i in 0..<900 {
        ws += 0.30 + Double.random(in: -0.05...0.05)
        mds += (i / 20) % 2 == 0 ? 0.35 : 0.10 + Double.random(in: 0...0.05)
        rows.append("synthetic,\(f3(Double(i))),\(f3(Double(i) + 0.005)),0,\(f2(ws)),\(f2(mds))")
    }
    try? (rows.joined(separator: "\n") + "\n").write(toFile: dir + "/record-loaded-synthetic.csv", atomically: true, encoding: .utf8)
    appendLine(dir + "/tests.csv", "test,rhythm,target,wall_start,wall_end,group_size,group_pids,stop_times_s,resume_times_s,status,self_cpu_pct,web_fps_obs,web_visible_obs")
    for n in 1...3 {
        var tr = ["k,rel_before,rel_after,WindowServer,mds_stores,target_cpu"]
        ws = 10
        mds = 10
        for k in 0...150 {
            let t = Double(k) * 0.25
            let inPause = t >= 18 && t < 36 && Int((t - 18) / 3) % 2 == 0
            let lagged = t >= 18.5 && t < 36.5 && Int((t - 18.5) / 3) % 2 == 0  // 0.5 s lag
            tr.append("\(k),\(f3(t)),\(f3(t + 0.004)),\(f2(ws)),\(f2(mds)),\(f3(inPause ? 0 : t))")
            ws += (lagged ? 0.04 : 0.30) * 0.25 + Double.random(in: -0.004...0.004)
            mds += 0.2 * 0.25 + Double.random(in: -0.01...0.01)
        }
        try? (tr.joined(separator: "\n") + "\n").write(toFile: dir + "/trace-synthetic-web-\(n).csv", atomically: true, encoding: .utf8)
        appendLine(dir + "/tests.csv", "synthetic-web-\(n),steady,web,synthetic,synthetic,1,1,18.001;24.001;30.001,21.001;27.001;33.001,ok,0.5,60,1")
    }
    analyze(dir: dir)
    print("Expected: WindowServer proven in 3 of 3 (share about 68% unshifted, higher with the lag shift), lag to drop 0.5 s; mds_stores inconclusive.")
}

switch command {
// ---- internal roles ----------------------------------------------------------------------
case "_watchdog": runWatchdog()
case "_burn": runBurn(args)
case "_writer": runWriter(args)
case "_idle": runIdle(args)
case "_webapp": MainActor.assumeIsolated { runWebApp(args) }
case "_cover": MainActor.assumeIsolated { runCover(args) }
case "_crashmain": runCrashMain(args)

// ---- public subcommands --------------------------------------------------------------------
case "probe":
    let run = Run(dir: newRunDir() + "-probe")
    installAbortHandlers()
    print("START TIME: \(wallNow())")
    probe(run: run)
    finish(run)

case "record":
    // Passive by default: no load, no window, nothing paused. --load steady|pulsed:on,off adds
    // the spike's own load (a window appears) but still pauses nothing.
    let seconds = args.num("seconds", 900)
    let load = args.str("load", "none")
    let run = Run(dir: newRunDir())
    installAbortHandlers()
    announce("record (\(load == "none" ? "passive" : "with spike load \(load)"))", estimate: seconds + (load == "none" ? 2 : 70), dir: run.dir, pauses: false, windows: load != "none")
    requireDaemons(run)
    var stim: Stimuli? = nil
    if load != "none" {
        requireScreen(run)
        guard Rhythm(load) != nil, load != "random" else {
            print("unknown --load \(load); use none, steady or pulsed:ON,OFF")
            exit(2)
        }
        run.phase("start-load") { stim = startStimuli(run, rhythm: load, tune: true) }
        if stim == nil {
            finish(run)
            exit(1)
        }
    }
    let label = args.str("label", load == "none" ? "idle-passive" : "loaded-\(load.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ",", with: "-"))")
    run.phase("record-\(label)") { record(run: run, label: label, seconds: seconds, interval: args.num("interval", 1)) }
    if stim != nil { run.phase("stop-load") { stopStimuli(run, stim) } }
    finish(run)
    print("Analyse with: build/attrib2 analyze \"\(run.dir)\"")

case "analyze":
    guard let dir = args.positional.first ?? latestRunDir() else {
        print("no data folder; pass one: attrib2 analyze <folder>")
        exit(2)
    }
    analyze(dir: dir)

case "safety-check":
    let run = Run(dir: newRunDir() + "-safety")
    installAbortHandlers()
    announce("watchdog safety check", estimate: 15, dir: run.dir, pauses: true, windows: false)
    var ok = false
    run.phase("safety-check") { ok = safetyCheck(run: run) }
    finish(run)
    print(ok ? "SAFETY CHECK PASSED" : "SAFETY CHECK FAILED — do not run pause tests")
    exit(ok ? 0 : 1)

case "test":
    let n = args.int("n", 3)
    let rhythm = args.str("rhythm", "steady")
    let targets = args.str("targets", "web,writer,burn-sync,burn-random").split(separator: ",").map(String.init)
    guard Rhythm(rhythm) != nil, rhythm != "random" else {
        print("unknown --rhythm \(rhythm); use steady or pulsed:ON,OFF")
        exit(2)
    }
    let run = Run(dir: newRunDir())
    installAbortHandlers()
    requireScreen(run)
    announce("real cause tests (\(n) per target, rhythm \(rhythm))", estimate: 15 + 70 + Double(n * targets.count) * secondsPerTest, dir: run.dir, pauses: true, windows: true)
    requireDaemons(run)
    var ok = false
    run.phase("safety-check") { ok = safetyCheck(run: run) }
    guard ok else {
        finish(run)
        print("Safety check failed: no pause test was run.")
        exit(1)
    }
    var stim: Stimuli? = nil
    run.phase("start-load") { stim = startStimuli(run, rhythm: rhythm, tune: true) }
    if let stim {
        run.phase("tests") { runTests(run: run, stim: stim, targets: targets, n: n, block: rhythm.hasPrefix("pulsed") ? "pulsed" : "steady") }
    }
    run.phase("stop-load") { stopStimuli(run, stim) }
    analyze(dir: run.dir)
    finish(run)

case "occlusion":
    let reps = args.int("reps", 3)
    let seconds = args.num("seconds", 20)
    let run = Run(dir: newRunDir())
    installAbortHandlers()
    requireScreen(run)
    announce("occlusion measurement", estimate: 70 + Double(reps * 3) * (seconds + 4), dir: run.dir, pauses: false, windows: true)
    requireDaemons(run)
    var stim: Stimuli? = nil
    run.phase("start-load") { stim = startStimuli(run, rhythm: "steady", tune: true) }
    if let stim { run.phase("occlusion") { runOcclusion(run: run, stim: stim, reps: reps, seconds: seconds) } }
    run.phase("stop-load") { stopStimuli(run, stim) }
    analyze(dir: run.dir)
    finish(run)

case "all":
    let idleS = args.num("idle-min", 3) * 60
    let steadyS = args.num("steady-min", 12) * 60
    let pulsedS = args.num("pulsed-min", 8) * 60
    let nSteady = args.int("n-steady", 5)
    let nPulsed = args.int("n-pulsed", 3)
    let pulsed = "pulsed:" + args.str("pulsed", "4,3")
    let occReps = args.int("occlusion-reps", 3)
    let occSeconds = args.num("occlusion-seconds", 20)
    let targets = ["web", "writer", "burn-sync", "burn-random"]
    guard Rhythm(pulsed) != nil else {
        print("bad --pulsed; use ON,OFF in seconds, e.g. 4,3")
        exit(2)
    }
    let estimate =
        15 + idleS + 70 + steadyS + Double(nSteady * targets.count) * secondsPerTest + Double(occReps * 3) * (occSeconds + 4) + 30 + pulsedS
        + Double(nPulsed * targets.count) * secondsPerTest + 15
    let run = Run(dir: newRunDir())
    installAbortHandlers()
    requireScreen(run)
    announce("everything", estimate: estimate, dir: run.dir, pauses: true, windows: true)
    requireDaemons(run)
    var safe = false
    run.phase("safety-check") { safe = safetyCheck(run: run) }
    if !safe { run.note("SAFETY CHECK FAILED: recordings and occlusion run, but NO pause test is run") }
    run.phase("record-idle") { record(run: run, label: "idle", seconds: idleS, interval: 1) }
    var stim: Stimuli? = nil
    run.phase("start-load-steady") { stim = startStimuli(run, rhythm: "steady", tune: true) }
    if let steady = stim {
        run.phase("record-loaded-steady") { record(run: run, label: "loaded-steady", seconds: steadyS, interval: 1) }
        if safe { run.phase("tests-steady") { runTests(run: run, stim: steady, targets: targets, n: nSteady, block: "steady") } }
        run.phase("occlusion") { runOcclusion(run: run, stim: steady, reps: occReps, seconds: occSeconds) }
        run.phase("restart-load-pulsed") {
            stopStimuli(run, steady)
            stim = startStimuli(run, rhythm: pulsed, tune: false, reuse: steady)
        }
        if let p = stim {
            run.phase("record-loaded-pulsed") { record(run: run, label: "loaded-pulsed", seconds: pulsedS, interval: 1) }
            if safe { run.phase("tests-pulsed") { runTests(run: run, stim: p, targets: targets, n: nPulsed, block: "pulsed") } }
        }
    } else {
        run.note("the test load could not be started; only the idle recording exists")
    }
    run.phase("stop-load") { stopStimuli(run, stim) }
    analyze(dir: run.dir)
    finish(run)
    print("Done. Summary: \(run.dir)/results.md")

case "selftest":
    selftest()

default:
    print(
        """
        Farol attribution spike v2 (throwaway prototype, not Farol code)

        usage: build/attrib2 <subcommand> [options]

          all            everything in order, about 52 minutes; writes data/<time>/results.md
          record         passive recording of WindowServer and mds_stores CPU (no window, no pause)
                           --seconds 900  --interval 1  --load none|steady|pulsed:4,3  --label NAME
          analyze [DIR]  sham-test calibration + verdicts + results.md for a data folder (default: latest)
          test           real cause tests with the watchdog   --n 3  --rhythm steady|pulsed:4,3
                           --targets web,writer,burn-sync,burn-random
          occlusion      WindowServer load: culprit visible / small panel on top / fully covered
                           --reps 3  --seconds 20
          safety-check   proves the watchdog resumes a paused process when the spike dies or hangs
          probe          read-only look at daemons, responsibility and WebKit helpers (5 seconds)
          selftest       analyses synthetic data with a known answer (no process touched)

        Common option: --out DIR (data folder). See RUN.md before running `all`.
        """)
}
