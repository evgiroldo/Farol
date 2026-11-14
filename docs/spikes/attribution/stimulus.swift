// Geradores de carga com "culpado conhecido" para validar o protótipo.
// O modo vem do nome do executável: farol-render, farol-burn-sync, farol-burn-random,
// farol-write <pasta>, farol-write-decoy <pasta>. Duração: 60 s.
import AppKit

let mode = (CommandLine.arguments[0] as NSString).lastPathComponent
let duration = 60.0
let start = Date()
func elapsed() -> Double { Date().timeIntervalSince(start) }
func onPhase(period: Double) -> Bool { Int(Date().timeIntervalSince1970 / period) % 2 == 0 }  // alinhado ao relógio
var rng = SystemRandomNumberGenerator()
var randomOn = false, randomUntil = 0.0
func randomPhase() -> Bool {
    if elapsed() > randomUntil { randomOn.toggle(); randomUntil = elapsed() + Double.random(in: 1...5, using: &rng) }
    return randomOn
}

final class Canvas: NSView {  // redesenha a janela inteira a 120 Hz na fase "ligada", sem piscar
    var t = 0.0
    override func draw(_ r: NSRect) {
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill(); bounds.fill()
        for i in 0..<400 {
            let x = (Double(i * 37) + t * 40).truncatingRemainder(dividingBy: bounds.width)
            let y = Double(i * 53).truncatingRemainder(dividingBy: bounds.height)
            NSColor(calibratedHue: Double(i % 40) / 40, saturation: 0.3, brightness: 0.5, alpha: 0.6).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 30, height: 30)).fill()
        }
    }
}

switch mode {
case "farol-render":
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.title = "Farol — teste de renderização (fecha sozinho em 60 s)"
    let c = Canvas(); w.contentView = c; w.orderFrontRegardless()
    Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
        if elapsed() > duration { exit(0) }
        if onPhase(period: 4) { c.t += 1; c.needsDisplay = true }
    }
    app.run()
case "farol-burn-sync", "farol-burn-random":
    while elapsed() < duration {
        let on = mode == "farol-burn-sync" ? onPhase(period: 4) : randomPhase()
        if on { var x = 0.0; for i in 0..<2_000_000 { x += Double(i).squareRoot() }; _ = x }
        else { usleep(50_000) }
    }
case "farol-write", "farol-write-decoy":
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var n = 0
    let text = String(repeating: "Farol prototipo de atribuicao causal. ", count: 1500)
    while elapsed() < duration {
        let on = mode == "farol-write" ? onPhase(period: 6) : randomPhase()
        if on {
            for _ in 0..<20 { try? text.write(to: dir.appendingPathComponent("nota-\(n % 400).txt"), atomically: true, encoding: .utf8); n += 1 }
        }
        usleep(100_000)
    }
default:
    print("modo desconhecido: \(mode)")
}
