import Foundation
import Testing

@testable import FarolCore

@Suite("DaemonWatcher")
struct DaemonWatcherTests {
    @Test func parsesPSTimes() {
        #expect(DaemonWatcher.cpuSeconds("0:00.01") == 0.01)
        #expect(DaemonWatcher.cpuSeconds("22:38.29") == 22 * 60 + 38.29)
        #expect(DaemonWatcher.cpuSeconds("1:02:03.50") == 3_723.5)
        #expect(DaemonWatcher.cpuSeconds("2-01:00:00") == 2.0 * 86_400 + 3_600)
    }

    @Test func rejectsMalformedTimes() {
        for bad in ["", "12", "a:b", "-1:00", "1:-2", "1:2:3:4", "inf:00", String(repeating: "9", count: 40) + ":00"] {
            #expect(DaemonWatcher.cpuSeconds(Substring(bad)) == nil, "\(bad)")
        }
    }

    /// The output of `ps` is untrusted text: only well-formed lines for PIDs that were asked for count.
    @Test func parsesOnlyRequestedPIDs() {
        let output = """
              10   0:01.00
              11   0:02.50
              99   9:59.00
            garbage line
              12   1:00.00 extra
              13
            """
        let cpu = DaemonWatcher.parse(output, allowed: [10, 11, 12, 13])
        #expect(cpu == [10: 1.0, 11: 2.5])
    }

    @Test func busyTimeAccumulatesAcrossQueries() throws {
        var watcher = DaemonWatcher(knowledgeBase: try KnowledgeBase.bundled())
        watcher.watch(pid: 50, entryID: "spotlight-store")
        #expect(watcher.update([50: 100], at: 0).isEmpty, "first reading only sets the starting point")
        let first = watcher.update([50: 105], at: 10)  // 50% of a core for 10 s
        #expect(first.first?.coreShare == 0.5)
        #expect(first.first?.busySeconds == 10)
        let second = watcher.update([50: 110], at: 20)
        #expect(second.first?.busySeconds == 20)
        let calm = watcher.update([50: 110.1], at: 30)
        #expect(calm.first?.busySeconds == 0)
    }

    @Test func droppedCumulativeTimeMeansAReusedPID() throws {
        var watcher = DaemonWatcher(knowledgeBase: try KnowledgeBase.bundled())
        watcher.watch(pid: 50, entryID: "spotlight-store")
        _ = watcher.update([50: 100], at: 0)
        #expect(watcher.update([50: 1], at: 10).isEmpty)
        #expect(watcher.update([50: 6], at: 20).first?.coreShare == 0.5)
    }

    @Test func findsTheOutermostAppBundle() {
        let helper = "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper"
        #expect(ProcessPath.outermostAppBundle(in: helper) == "/Applications/Slack.app")
        #expect(ProcessPath.outermostAppBundle(in: "/usr/bin/swift") == nil)
        #expect(ProcessPath.outermostAppBundle(in: "/Applications/.app/x") == nil)
        #expect(ProcessPath.outermostAppBundle(in: "relative/Thing.app/x") == nil)
    }
}

@Suite("Verdict")
struct VerdictTests {
    func app(_ name: String, cores: Double, memoryMB: UInt64 = 100) -> AppUsage {
        AppUsage(
            id: "/Applications/\(name).app", name: name, bundlePath: "/Applications/\(name).app", cores: cores,
            footprint: memoryMB << 20, diskBytesWritten: 0, processCount: 1)
    }

    @Test func calmWhenNotSlow() {
        #expect(Verdict.decide(reasons: nil, apps: [app("Slack", cores: 3)], system: []) == .calm)
    }

    @Test func busySystemProcessWithoutSlowdownIsWork() {
        let spotlight = SystemWork(entryID: "spotlight-store", cores: 0.6, sustained: true)
        let brief = SystemWork(entryID: "photos-analysis", cores: 0.9, sustained: false)
        #expect(Verdict.decide(reasons: nil, apps: [], system: [spotlight, brief]) == .working(spotlight))
    }

    @Test func namesTheBusiestAppAsSuspect() {
        let chrome = app("Chrome", cores: 2.1)
        let verdict = Verdict.decide(reasons: .cpu, apps: [app("Mail", cores: 0.2), chrome], system: [])
        #expect(verdict == .slow(.app(chrome)))
    }

    @Test func doesNotBlameAnAppThatBarelyWorks() {
        let verdict = Verdict.decide(reasons: .cpu, apps: [app("Mail", cores: 0.3)], system: [])
        #expect(verdict == .slow(.unclear))
    }

    @Test func systemWorkWinsWhenItUsesMoreThanAnyApp() {
        let spotlight = SystemWork(entryID: "spotlight-store", cores: 1.5, sustained: false)
        let verdict = Verdict.decide(reasons: .cpu, apps: [app("Mail", cores: 0.8)], system: [spotlight])
        #expect(verdict == .slow(.systemWork(spotlight)))
    }

    @Test func heatComesFirst() {
        let verdict = Verdict.decide(reasons: [.cpu, .thermal], apps: [app("Chrome", cores: 3)], system: [])
        #expect(verdict == .slow(.heat))
    }

    @Test func memoryShortageNamesTheLargestApp() {
        let big = app("Photoshop", cores: 0.1, memoryMB: 9_000)
        let verdict = Verdict.decide(reasons: .swapping, apps: [app("Mail", cores: 0.2), big], system: [])
        #expect(verdict == .slow(.memory(big)))
    }

    @Test func memoryShortageWithProcessorLoadPrefersTheBusyApp() {
        let busy = app("Chrome", cores: 1.2, memoryMB: 500)
        let verdict = Verdict.decide(
            reasons: [.cpu, .memoryPressure], apps: [busy, app("Photoshop", cores: 0, memoryMB: 9_000)], system: [])
        #expect(verdict == .slow(.app(busy)))
    }
}
