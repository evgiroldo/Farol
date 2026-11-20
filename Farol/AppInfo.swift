import AppKit
import FarolCore
import UniformTypeIdentifiers

/// Display names and icons of apps, read from their bundles (ADR 0027).
@MainActor
enum AppInfo {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static func name(of usage: AppUsage) -> String {
        if let cached = names[usage.id] { return cached }
        var name = usage.name
        if let path = usage.bundlePath, let bundle = Bundle(path: path) {
            let info = bundle.localizedInfoDictionary ?? [:]
            let display =
                info["CFBundleDisplayName"] as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            if let display, !display.isEmpty { name = display }
        }
        // A bundle's name is chosen by the app, so it is cleaned like a process name.
        name = String(ProcessSampler.sanitized(name).prefix(60))
        names[usage.id] = name
        return name
    }

    static func icon(of usage: AppUsage) -> NSImage {
        if let cached = icons[usage.id] { return cached }
        let icon =
            usage.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .unixExecutable)
        icons[usage.id] = icon
        return icon
    }
}
