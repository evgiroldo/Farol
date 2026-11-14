import Darwin
import Dispatch
import Foundation
import Testing

@testable import FarolCore

@Suite("SystemCounters")
struct SystemCountersTests {
    @Test func readsSaneValues() throws {
        let a = try #require(SystemCounters.read(memoryPressure: nil))
        // Burn a little CPU so the interval is not empty.
        var x = 0.0
        for i in 0..<2_000_000 { x += Double(i).squareRoot() }
        #expect(x > 0)
        let b = try #require(SystemCounters.read(memoryPressure: nil))
        let load = SystemLoad(from: a, to: b, cores: SystemCounters.coreCount)
        #expect(load.busyCores >= 0)
        #expect(load.busyCores <= Double(SystemCounters.coreCount))
        #expect(load.interval >= 0)
        #expect(load.memoryPressure == nil)
    }

    @Test func tickCountersWrapAround() {
        let base = SystemSnapshot(
            uptime: 0, busyTicks: UInt32.max - 10, totalTicks: UInt32.max - 30,
            swapouts: 5, memoryPressure: .normal, thermal: .nominal)
        var later = base
        later.uptime = 2
        later.busyTicks = base.busyTicks &+ 50  // wraps
        later.totalTicks = base.totalTicks &+ 100  // wraps
        later.swapouts = 105
        let load = SystemLoad(from: base, to: later, cores: 8)
        #expect(load.busyCores == 4)
        #expect(load.swapoutsPerSecond == 50)
    }

    @Test func bootTimeIsInThePast() throws {
        let boot = try #require(SystemCounters.bootTime())
        #expect(boot > 1_600_000_000)
        #expect(boot < Date().timeIntervalSince1970)
    }

    /// Budget (ADR 0011): the sentinel reads these counters every 2 s, forever.
    /// Generous bound for noisy machines; real budgets are measured in CPU time (ADR 0019).
    @Test func readingIsCheap() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<1_000 { _ = SystemCounters.read(memoryPressure: nil) }
        }
        #expect(elapsed < .milliseconds(200), "1000 reads took \(elapsed)")
    }
}

@Suite("MemoryPressureMonitor")
struct MemoryPressureMonitorTests {
    @Test func startsUnavailableAndRecordsLevels() {
        let monitor = MemoryPressureMonitor(queue: DispatchQueue(label: "test", qos: .utility))
        // Events only report changes; without one, the level is unknown, not "normal".
        if monitor.current == nil { monitor.record(.warning) }
        #expect(monitor.current != nil)
        monitor.record(.critical)
        #expect(monitor.current == .critical)
    }
}

@Suite("ProcessSampler")
struct ProcessSamplerTests {
    func sample(_ pid: pid_t, start: UInt64, cpu: Double, written: UInt64 = 0, name: String = "p") -> ProcessSample {
        ProcessSample(
            identity: ProcessIdentity(pid: pid, startTime: start), name: name, uid: 501, cpuSeconds: cpu,
            diskBytesWritten: written, footprint: 1)
    }

    @Test func seesProcessesOfTheCurrentUser() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        let snapshot = ProcessSampler().snapshot()
        let found = try #require(snapshot.processes.first { $0.identity.pid == child.processIdentifier })
        #expect(found.name == "sleep")
        #expect(found.uid == getuid())
        // Wall-clock start time: in the recent past, and before the snapshot.
        #expect(found.identity.startTime <= snapshot.time)
        #expect(snapshot.time - found.identity.startTime < 60_000_000)
        #expect(!snapshot.processes.contains { $0.identity.pid == getpid() })
    }

    @Test func deltasKeepOnlyActiveProcessesAndRespectIdentity() {
        let earlier = ProcessSnapshot(
            time: 1_000, processes: [sample(10, start: 1, cpu: 5, written: 100), sample(11, start: 1, cpu: 1)])
        let later = ProcessSnapshot(
            time: 2_000,
            processes: [
                sample(10, start: 1_500, cpu: 0.5, written: 10, name: "new"),  // PID reused after `earlier`
                sample(11, start: 1, cpu: 1),  // idle
            ])
        let deltas = ProcessSampler.deltas(from: earlier, to: later)
        #expect(deltas.count == 1)
        #expect(deltas.first?.name == "new")
        #expect(deltas.first?.cpuSeconds == 0.5)
        #expect(deltas.first?.diskBytesWritten == 10)
    }

    /// Review finding: a long-lived process missing from the previous snapshot must not
    /// show its lifetime CPU as a one-second burst (it would become the top suspect).
    @Test func longLivedNewcomerIsNotABurst() {
        let earlier = ProcessSnapshot(time: 1_000, processes: [])
        let later = ProcessSnapshot(time: 2_000, processes: [sample(20, start: 10, cpu: 3_600)])
        #expect(ProcessSampler.deltas(from: earlier, to: later).isEmpty)
    }

    @Test func namesCannotSpoofTheInterface() {
        #expect(ProcessSampler.sanitized("Finder\u{202E}gpj.exe") == "Findergpj.exe")
        #expect(ProcessSampler.sanitized("evil\nname\u{0007}") == "evilname")
        #expect(ProcessSampler.sanitized("Safari Web Content") == "Safari Web Content")
    }

    /// Budget (ADR 0011): in incident mode the sentinel samples every process once per
    /// second; one pass must stay well under 50 ms of wall time.
    @Test func fullSampleIsCheapEnough() {
        let sampler = ProcessSampler()
        _ = sampler.snapshot()  // warm up
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = sampler.snapshot() }
        #expect(elapsed < .milliseconds(50), "one pass took \(elapsed)")
    }
}
