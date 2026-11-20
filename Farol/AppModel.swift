import AppKit
import FarolCore
import Observation

/// Holds what the card shows and runs the monitor in the background.
@MainActor
@Observable
final class AppModel {
    /// What the card shows. Updated only while the card is open, so a closed card costs nothing.
    private(set) var state = MonitorState()
    /// What the menu bar icon shows. Changes only when the kind of verdict changes.
    private(set) var level = Level.calm
    let knowledgeBase: KnowledgeBase?
    /// Knowledge base language: Brazilian Portuguese when the app runs in Portuguese, else English.
    let language: String

    @ObservationIgnored private let monitor: SlowdownMonitor?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var latest = MonitorState()
    @ObservationIgnored private var cardIsOpen = false

    enum Level { case calm, working, slow }

    init() {
        let kb = try? KnowledgeBase.bundled()
        knowledgeBase = kb
        language = Bundle.main.preferredLocalizations.first?.hasPrefix("pt") == true ? "pt-BR" : "en"
        monitor = kb.map { SlowdownMonitor(knowledgeBase: $0) }
        start()
    }

    var menuBarSymbol: String {
        switch level {
        case .calm: "light.beacon.min"
        case .working: "light.beacon.max"
        case .slow: "light.beacon.max.fill"
        }
    }

    var menuBarLabel: String {
        switch level {
        case .calm: String(localized: "Farol: your Mac is running normally")
        case .working: String(localized: "Farol: your Mac is busy")
        case .slow: String(localized: "Farol: your Mac is slow")
        }
    }

    func entry(_ id: String) -> KnowledgeBase.Entry? {
        knowledgeBase?.processes.first { $0.id == id }
    }

    /// Called when the card opens: shows the latest state and measures again right away.
    func cardOpened() async {
        cardIsOpen = true
        state = latest
        guard let monitor else { return }
        receive(await monitor.refreshNow())
    }

    func cardClosed() { cardIsOpen = false }

    private func receive(_ new: MonitorState) {
        latest = new
        if cardIsOpen { state = new }
        let newLevel: Level =
            switch new.verdict {
            case .calm: .calm
            case .working: .working
            case .slow: .slow
            }
        if newLevel != level { level = newLevel }
    }

    private func start() {
        guard let monitor else { return }
        task = Task.detached(priority: .utility) { [weak self] in
            await monitor.run { state in
                Task { @MainActor in self?.receive(state) }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { _ in
            Task { await monitor.systemDidWake() }
        }
    }
}
