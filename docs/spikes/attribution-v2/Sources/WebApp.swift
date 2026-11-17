// Throwaway validation prototype (attribution spike v2). NOT Farol code.
// GUI roles, each a separate process started by the spike:
//   _webapp  the WindowServer culprit: an AppKit window with a WKWebView that renders
//            stimulus.html (real WebKit, with its helper processes outside the bundle)
//   _cover   a window placed over the culprit for the occlusion measurement:
//            `panel` = small static panel like Farol's planned test UI, `full` = covers it all
import AppKit
import WebKit

@MainActor
final class WebAppController: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    let args: Args
    var window: NSWindow?
    var web: WKWebView?
    var lastFrames = 0
    var lastOn = 1
    var lastMessage = 0.0
    var timer: Timer?

    init(_ a: Args) { args = a }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusPath = args.str("status", "/dev/null")
        guard let screen = NSScreen.main else {
            appendLine(statusPath, "#error no screen")
            exit(3)
        }
        let vf = screen.visibleFrame
        let w = min(1600, floor(vf.width * 0.75))
        let h = min(1000, floor(vf.height * 0.8))
        let frame = NSRect(x: vf.minX + 40, y: vf.maxY - h - 40, width: w, height: h)
        let win = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "Farol spike: test load (closes by itself, do not cover)"
        win.isReleasedWhenClosed = false
        // Floating, so another app's window coming forward cannot cover the load by accident.
        win.level = .floating

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // leave nothing in ~/Library
        var on = 0.0
        var off = 0.0
        if case .pulsed(let a, let b)? = Rhythm(args.str("rhythm", "steady")) {
            on = a
            off = b
        }
        let js = "window.SPIKE = {level: \(args.int("level", 1)), on: \(on), off: \(off)};"
        config.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(self, name: "spike")
        let view = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        win.contentView = view
        let html =
            args.options["html"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.url(forResource: "stimulus", withExtension: "html")
        guard let html else {
            appendLine(statusPath, "#error stimulus.html not found")
            exit(3)
        }
        view.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        win.orderFrontRegardless()
        window = win
        web = view

        let fr = win.frame
        appendLine(statusPath, "#frame \(Int(fr.minX)) \(Int(fr.minY)) \(Int(fr.width)) \(Int(fr.height))")
        appendLine(statusPath, "#columns mono,frames_per_s,window_visible,rhythm_on")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let win = self.window else { return }
                let fresh = monoNow() - self.lastMessage < 1.6
                let visible = win.occlusionState.contains(.visible) ? 1 : 0
                appendLine(statusPath, "\(f3(monoNow())),\(fresh ? self.lastFrames : 0),\(visible),\(self.lastOn)")
            }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }
        lastFrames = (d["frames"] as? NSNumber)?.intValue ?? 0
        lastOn = (d["on"] as? NSNumber)?.intValue ?? 1
        lastMessage = monoNow()
    }
}

@MainActor
func runWebApp(_ a: Args) -> Never {
    watchLifeline { exit(0) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // no Dock icon, does not take the menu bar
    let controller = WebAppController(a)
    app.delegate = controller
    // Hard stop even if everything else fails.
    Timer.scheduledTimer(withTimeInterval: a.num("max-seconds", 4800), repeats: false) { _ in exit(0) }
    app.run()
    exit(0)
}

@MainActor
func runCover(_ a: Args) -> Never {
    watchLifeline { exit(0) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let f = a.str("frame", "100,100,800,600").split(separator: ",").compactMap { Double($0) }
    let target = f.count == 4 ? NSRect(x: f[0], y: f[1], width: f[2], height: f[3]) : NSRect(x: 100, y: 100, width: 800, height: 600)
    let full = a.str("mode", "panel") == "full"
    let win: NSWindow
    if full {
        win = NSWindow(contentRect: target.insetBy(dx: -20, dy: -20), styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "Farol spike: full cover (static)"
    } else {
        let rect = NSRect(x: target.midX - 180, y: target.midY - 90, width: 360, height: 180)
        win = NSPanel(contentRect: rect, styleMask: [.titled, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        win.title = "Farol spike: small static panel"
    }
    win.isOpaque = true
    win.backgroundColor = .windowBackgroundColor
    win.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    let label = NSTextField(wrappingLabelWithString: "Farol is testing… (static panel: no animation, no live chart)")
    label.frame = NSRect(x: 20, y: 40, width: 320, height: 80)
    win.contentView?.addSubview(label)
    win.orderFrontRegardless()
    Timer.scheduledTimer(withTimeInterval: a.num("max-seconds", 600), repeats: false) { _ in exit(0) }
    app.run()
    exit(0)
}
