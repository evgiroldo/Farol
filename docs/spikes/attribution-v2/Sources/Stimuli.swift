// Throwaway validation prototype (attribution spike v2). NOT Farol code.
// Load generators with a known ground truth, each started by the spike as its own process:
//   _burn    CPU only, no drawing, no writing (decoy)
//   _writer  writes text files into a folder Spotlight indexes (Spotlight culprit)
//   _idle    does nothing (used by `probe` and `safety-check`)
// The WebKit culprit lives in WebApp.swift.
import Darwin
import Foundation

/// When a stimulus is "on". `steady` = always; `pulsed` = on/off aligned to the wall clock, so
/// the culprit and the "same rhythm" decoy are in step; `random` = own random on/off phases.
enum Rhythm {
    case steady
    case pulsed(on: Double, off: Double)
    case random

    init?(_ text: String) {
        if text == "steady" {
            self = .steady
        } else if text == "random" {
            self = .random
        } else if text.hasPrefix("pulsed:") {
            let p = text.dropFirst(7).split(separator: ",").compactMap { Double($0) }
            guard p.count == 2, p[0] > 0, p[1] > 0 else { return nil }
            self = .pulsed(on: p[0], off: p[1])
        } else {
            return nil
        }
    }

    var text: String {
        switch self {
        case .steady: return "steady"
        case .random: return "random"
        case .pulsed(let on, let off): return "pulsed:\(on),\(off)"
        }
    }
}

final class RhythmClock {
    let rhythm: Rhythm
    private var randomOn = false
    private var randomUntil = 0.0
    init(_ r: Rhythm) { rhythm = r }

    func isOn() -> Bool {
        switch rhythm {
        case .steady:
            return true
        case .pulsed(let on, let off):
            return Date().timeIntervalSince1970.truncatingRemainder(dividingBy: on + off) < on
        case .random:
            let now = monoNow()
            if now >= randomUntil {
                randomOn.toggle()
                randomUntil = now + Double.random(in: 1...5)
            }
            return randomOn
        }
    }
}

/// Exits the process (after `onClose`) when the spike closes fd 3 or dies. No signal involved.
func watchLifeline(onClose: @escaping () -> Void) {
    let t = Thread {
        var c: UInt8 = 0
        while true {
            let n = read(3, &c, 1)
            if n == 0 || (n < 0 && errno != EINTR) { break }
        }
        onClose()
    }
    t.start()
}

func runIdle(_ a: Args) -> Never {
    watchLifeline { exit(0) }
    sleepFor(a.num("max-seconds", 60))
    exit(0)
}

func runBurn(_ a: Args) -> Never {
    watchLifeline { exit(0) }
    let clock = RhythmClock(Rhythm(a.str("rhythm", "steady")) ?? .steady)
    let end = monoNow() + a.num("max-seconds", 4800)
    var x = 0.0
    while monoNow() < end {
        if clock.isOn() {
            let until = monoNow() + 0.01
            while monoNow() < until { for i in 0..<20_000 { x += Double(i).squareRoot() } }
        } else {
            usleep(20_000)
        }
    }
    if x < 0 { print(x) }
    exit(0)
}

let writerFilePrefix = "farolspike-note-"

func runWriter(_ a: Args) -> Never {
    let dir = a.str("dir", "")
    guard !dir.isEmpty else { exit(2) }
    var stopping = false
    let lock = NSLock()
    watchLifeline {
        lock.lock()
        stopping = true
        lock.unlock()
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let clock = RhythmClock(Rhythm(a.str("rhythm", "steady")) ?? .steady)
    let level = max(1, min(3, a.int("level", 1)))
    let filesPerBatch = [10, 20, 30][level - 1]
    let wordsPerFile = [1200, 1800, 2400][level - 1]  // roughly 9, 13, 18 KB per file
    let words = [
        "lighthouse", "harbor", "signal", "window", "margin", "ledger", "orchard", "copper", "meadow", "lantern",
        "invoice", "garden", "railway", "summit", "thread", "kernel", "packet", "harvest", "violin", "glacier",
        "notebook", "compass", "bridge", "canvas", "anchor", "saffron", "timber", "voyage", "quartz", "ember",
    ]
    let end = monoNow() + a.num("max-seconds", 4800)
    var n = 0
    var rng = SystemRandomNumberGenerator()
    while monoNow() < end {
        lock.lock()
        let stop = stopping
        lock.unlock()
        if stop { break }
        if clock.isOn() {
            for _ in 0..<filesPerBatch {
                var text = "Farol attribution spike test note \(n). Safe to delete.\n"
                text.reserveCapacity(wordsPerFile * 8)
                for _ in 0..<wordsPerFile {
                    text += words[Int.random(in: 0..<words.count, using: &rng)]
                    text += " "
                }
                let path = "\(dir)/\(writerFilePrefix)\(n % 400).txt"
                // Non-atomic on purpose: no temporary file names, so cleanup by prefix is complete.
                try? text.write(toFile: path, atomically: false, encoding: .utf8)
                n += 1
            }
        }
        usleep(100_000)
    }
    // Clean up our own files before exiting (the spike also does it, as a second guard).
    removeGeneratedFiles(dir: dir, prefix: writerFilePrefix)
    exit(0)
}
