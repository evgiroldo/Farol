import FarolCore
import SwiftUI

/// The verdict-first card (ADR 0031): one plain answer, the evidence, then details.
struct CardView: View {
    let model: AppModel
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.knowledgeBase == nil {
                Message(
                    symbol: "exclamationmark.triangle",
                    headline: String(localized: "Farol could not start"),
                    lines: [
                        String(localized: "Its list of macOS processes is missing or damaged. Please reinstall Farol.")
                    ])
            } else {
                verdict
                if case .calm = model.state.verdict, let past = model.state.lastSlowdown {
                    PastSlowdownView(past: past, model: model)
                }
                Divider()
                DisclosureGroup(isExpanded: $showDetails) {
                    DetailsView(state: model.state)
                } label: {
                    Text("Details").font(.subheadline.weight(.medium))
                }
            }
            Divider()
            HStack {
                Text("Preview 0.1 · it explains, it does not change anything")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 380)
        .task { await model.cardOpened() }
        .onDisappear { model.cardClosed() }
    }

    @ViewBuilder private var verdict: some View {
        switch model.state.verdict {
        case .calm:
            Message(
                symbol: "checkmark.circle", tint: .green,
                headline: String(localized: "Your Mac is running normally"),
                lines: [String(localized: "Nothing is using much of its power right now.")])
        case .working(let work):
            SystemWorkView(work: work, slow: false, model: model)
        case .slow(let cause):
            CauseView(cause: cause, model: model)
        }
    }
}

/// Explains a cause. Used for the current slowdown and for the last one.
struct CauseView: View {
    let cause: Cause
    let model: AppModel

    var body: some View {
        switch cause {
        case .app(let app):
            let name = AppInfo.name(of: app)
            Message(
                icon: AppInfo.icon(of: app),
                headline: String(localized: "\(name) may be slowing down your Mac"),
                lines: [
                    String(
                        localized: "We're not sure yet. It is using much more of your Mac's power than anything else."),
                    String(localized: "If you don't need it right now, quitting it the usual way may help."),
                ],
                evidence: String(
                    localized: "Measured: \(name) is using \(Format.share(app.cores)) of your Mac's processing power."))
        case .systemWork(let work):
            SystemWorkView(work: work, slow: true, model: model)
        case .memory(let app):
            Message(
                symbol: "memorychip", tint: .orange,
                headline: String(localized: "Your Mac is running out of memory"),
                lines: [
                    String(
                        localized:
                            "It is moving data to the disk to make room, and that slows everything down. Closing apps or windows you don't need frees memory."
                    )
                ],
                evidence: app.map {
                    String(
                        localized:
                            "Measured: \(AppInfo.name(of: $0)) is using the most memory (\(Format.bytes($0.footprint)))."
                    )
                })
        case .heat:
            let text = model.entry("kernel-task")?.text(language: model.language)
            Message(
                symbol: "thermometer.high", tint: .red,
                headline: String(localized: "Your Mac is too hot"),
                lines: [String(localized: "It slows itself down to cool off.")] + (text.map { [$0.action] } ?? []),
                evidence: String(localized: "Measured: macOS reports a high temperature level."))
        case .unclear:
            Message(
                symbol: "gauge.with.dots.needle.67percent", tint: .orange,
                headline: String(localized: "Your Mac is busy"),
                lines: [String(localized: "Many apps are each doing a little; none of them stands out. See Details.")])
        }
    }
}

/// A system process from the knowledge base, explained in plain words (ADR 0031, "normal macOS work").
struct SystemWorkView: View {
    let work: SystemWork
    let slow: Bool
    let model: AppModel

    var body: some View {
        let entry = model.entry(work.entryID)
        let text = entry?.text(language: model.language)
        let name = text?.name ?? work.entryID
        var lines: [String] = []
        if let text {
            lines.append(text.what)
            lines.append(text.normal)
            if let typical = text.typical { lines.append(typical) }
            // Texts of entries offered the cause test describe version 1.0 (ADR 0044).
            if entry?.causeTest == false { lines.append(text.action) }
        }
        return Message(
            symbol: "gearshape.2", tint: .blue,
            headline: slow
                ? String(localized: "Your Mac is slow: \(name) is working hard")
                : String(localized: "Your Mac is busy: \(name) is working"),
            lines: lines,
            evidence: String(localized: "Measured: \(Format.cores(work.cores)) of one processor core."))
    }
}

struct PastSlowdownView: View {
    let past: PastSlowdown
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "Earlier, your Mac was slow from \(past.started.formatted(date: .omitted, time: .shortened)) to \(past.ended.formatted(date: .omitted, time: .shortened))."
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            CauseView(cause: past.cause, model: model)
                .opacity(0.8)
        }
    }
}

/// Busiest apps, with measured values.
struct DetailsView: View {
    let state: MonitorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.apps.isEmpty || state.windowSeconds == 0 {
                Text("Measuring… the first numbers appear in a few seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Busiest apps over the last \(Format.duration(state.windowSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(state.apps.prefix(6)) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: AppInfo.icon(of: app))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(AppInfo.name(of: app))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Format.share(app.cores))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Text(Format.bytes(app.footprint))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .font(.callout)
                }
                Text(
                    "Measured. The first number is the share of your Mac's total processing power; the second is the memory the app uses."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }
}

/// One card: icon, headline, plain lines and the measured evidence.
struct Message: View {
    var icon: NSImage?
    var symbol: String?
    var tint: Color = .accentColor
    let headline: String
    let lines: [String]
    var evidence: String?

    init(
        icon: NSImage? = nil, symbol: String? = nil, tint: Color = .accentColor, headline: String, lines: [String],
        evidence: String? = nil
    ) {
        self.icon = icon
        self.symbol = symbol
        self.tint = tint
        self.headline = headline
        self.lines = lines
        self.evidence = evidence
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else if let symbol {
                    Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(tint)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.headline)
                ForEach(lines, id: \.self) { Text($0) }
                if let evidence {
                    Text(evidence).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum Format {
    /// Cores as a share of the whole Mac (all cores).
    static func share(_ cores: Double) -> String {
        let total = Double(max(SystemCounters.coreCount, 1))
        return (cores / total).formatted(.percent.precision(.fractionLength(0...1)))
    }

    /// Cores as a share of one core.
    static func cores(_ cores: Double) -> String {
        cores.formatted(.percent.precision(.fractionLength(0)))
    }

    static func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }

    static func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}
