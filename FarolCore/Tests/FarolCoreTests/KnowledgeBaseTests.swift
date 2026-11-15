import Foundation
import Testing

@testable import FarolCore

@Suite("KnowledgeBase")
struct KnowledgeBaseTests {
    let kb: KnowledgeBase

    init() throws { kb = try KnowledgeBase.bundled() }

    @Test func loadsAboutTwentyProcesses() {
        #expect(kb.version == 1)
        #expect(kb.processes.count >= 20)
        #expect(Set(kb.processes.map(\.id)).count == kb.processes.count, "duplicate id")
        let names = kb.processes.flatMap(\.executables)
        #expect(Set(names).count == names.count, "an executable appears in two entries")
    }

    /// ADR 0015: every text exists in English and Brazilian Portuguese.
    @Test func everyEntryIsInBothLanguages() {
        for e in kb.processes {
            #expect(e.languages == ["en", "pt-BR"], "\(e.id)")
            for lang in ["en", "pt-BR"] {
                let t = e.text(language: lang)
                for (field, value) in [("name", t.name), ("what", t.what), ("normal", t.normal), ("action", t.action)] {
                    #expect(!value.isEmpty, "\(e.id) \(lang) \(field) is empty")
                }
            }
        }
    }

    /// ADR 0020: short, plain sentences without exclamation marks.
    @Test func textsAreShortAndCalm() {
        for e in kb.processes {
            for lang in ["en", "pt-BR"] {
                let t = e.text(language: lang)
                #expect(t.name.count <= 40, "\(e.id) \(lang) name too long")
                for value in [t.what, t.normal, t.action, t.typical ?? ""] {
                    #expect(value.count <= 200, "\(e.id) \(lang): \(value)")
                    #expect(!value.contains("!"), "\(e.id) \(lang): \(value)")
                }
            }
        }
    }

    /// ADR 0030: durations are typical, never a prediction of when a task will end.
    @Test func durationsAreAlwaysHedged() {
        let hedges = [
            "en": ["Often", "Usually", "Can ", "Depends", "The first"],
            "pt-BR": ["Costuma", "Pode ", "Depende", "O primeiro"],
        ]
        for e in kb.processes {
            for (lang, starts) in hedges {
                guard let typical = e.text(language: lang).typical else { continue }
                #expect(starts.contains { typical.hasPrefix($0) }, "\(e.id) \(lang) predicts: \(typical)")
            }
        }
    }

    /// ADRs 0021 and 0030: the watch list, without kernel_task, matched by system paths.
    @Test func watchListMatchesTheDecisions() {
        let watched = Set(kb.watched.flatMap(\.executables))
        #expect(
            watched == [
                "WindowServer", "mds_stores", "mds", "mdworker_shared", "photoanalysisd", "mediaanalysisd",
                "backupd", "softwareupdated", "cloudd", "bird", "coreaudiod", "fileproviderd",
            ])
        for e in kb.watched {
            #expect(!e.paths.isEmpty, "\(e.id) is watched without a known path")
            #expect(e.paths.allSatisfy { $0.hasPrefix("/System/") || $0.hasPrefix("/usr/") }, "\(e.id)")
        }
    }

    /// ADR 0029: version 1.0 offers the cause test for WindowServer and Spotlight only.
    @Test func causeTestOnlyForTheTwoClassicCases() {
        #expect(Set(kb.processes.filter(\.causeTest).map(\.id)) == ["windowserver", "spotlight-store"])
    }

    /// ADR 0030: an app cannot pass itself off as a system process by its name.
    @Test func matchingRequiresTheRealPath() {
        let real =
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/"
            + "Versions/A/Support/mds_stores"
        #expect(kb.entry(executableName: "mds_stores", path: real)?.id == "spotlight-store")
        #expect(kb.entry(executableName: "mds_stores", path: "/Users/someone/Downloads/mds_stores") == nil)
        #expect(kb.entry(executableName: "com.apple.WebKit.WebContent", path: "/Applications/Evil.app/x") == nil)
        #expect(kb.entry(executableName: "unknown", path: real) == nil)
    }

    @Test func fallsBackToEnglish() throws {
        let e = try #require(kb.processes.first)
        #expect(e.text(language: "fr") == e.text(language: "en"))
    }
}
