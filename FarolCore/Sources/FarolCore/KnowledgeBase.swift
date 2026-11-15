import Foundation

/// Plain-language explanations of common macOS processes (ADRs 0003, 0020, 0029, 0032),
/// loaded from `Resources/KnowledgeBase.json`. The file is data the community can extend;
/// tests enforce the writing and identity rules.
public struct KnowledgeBase: Sendable, Decodable {
    /// Measurable evidence that makes a process's work "normal" (ADR 0032). How each one is
    /// measured is decided when the detector is implemented.
    public enum Evidence: String, Sendable, Codable, CaseIterable {
        /// The macOS build changed recently.
        case macosUpdate = "macos-update"
        /// Many files were written or changed recently.
        case largeFileChange = "large-file-change"
        /// A Time Machine backup is running.
        case backupInProgress = "backup-in-progress"
        /// An app was opened for the first time or updated.
        case newAppOpened = "new-app-opened"
        /// The thermal state is serious or critical.
        case thermalPressure = "thermal-pressure"
    }

    public struct Text: Sendable, Codable, Equatable {
        /// Friendly name shown instead of the process name.
        public let name: String
        /// What it does, in one sentence.
        public let what: String
        /// When its work is normal.
        public let normal: String
        /// A *typical* duration, always hedged; never a prediction (ADR 0030). `nil` when
        /// the process works continuously.
        public let typical: String?
        /// What the person can do.
        public let action: String
    }

    public struct Entry: Sendable, Decodable, Identifiable {
        public let id: String
        /// Executable names (the last path component).
        public let executables: [String]
        /// Exact executable paths. When present, a process matches only at one of these paths,
        /// so an app cannot pass itself off as a system process by its name (ADR 0030).
        public let paths: [String]
        public let category: String
        /// Watched by the sentinel through `ps` (ADR 0021).
        public let watched: Bool
        /// Offered the cause test in version 1.0 (ADR 0029).
        public let causeTest: Bool
        public let normalEvidence: [Evidence]
        /// How long the process takes to react to a pause (ADR 0033); `nil` until measured.
        public let lagSeconds: Double?
        let text: [String: Text]

        /// Text in the requested language (e.g. "pt-BR"), falling back to English.
        public func text(language: String) -> Text {
            text[language] ?? text["en"]!
        }

        public var languages: [String] { text.keys.sorted() }
    }

    public let version: Int
    public let processes: [Entry]

    /// The knowledge base shipped with FarolCore.
    public static func bundled() throws -> KnowledgeBase {
        guard let url = Bundle.module.url(forResource: "KnowledgeBase", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(KnowledgeBase.self, from: Data(contentsOf: url))
    }

    /// Finds the entry for a running process. Entries with known paths require an exact path
    /// match; entries without paths match by name only for executables under `/System/` or
    /// `/usr/` (`kernel_task` has no path and is explained from the thermal state instead).
    public func entry(executableName: String, path: String) -> Entry? {
        processes.first { e in
            guard e.executables.contains(executableName) else { return false }
            if !e.paths.isEmpty { return e.paths.contains(path) }
            return path.hasPrefix("/System/") || path.hasPrefix("/usr/")
        }
    }

    /// Entries the sentinel watches through `ps` (ADR 0021).
    public var watched: [Entry] { processes.filter(\.watched) }
}
