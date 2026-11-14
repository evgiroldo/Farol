// Protótipo descartável da Sentinela do Farol (item de barra de menus).
// Uso: farol-sentinel <intervalo_s> <duração_s>
// Repouso: só contadores globais baratos (CPU total, VM, térmico) num timer de baixa prioridade.
// Incidente: liga a coleta detalhada por processo (1 Hz) por 30 s quando a carga foge do normal.
// A cada 30 s imprime o próprio custo: CPU, memória (phys_footprint), wakeups e energia.
import AppKit
import Darwin

let interval = Double(CommandLine.arguments.dropFirst().first ?? "2") ?? 2
let duration = Double(CommandLine.arguments.dropFirst(2).first ?? "300") ?? 300
let started = Date()
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func secs(_ t: UInt64) -> Double { Double(t) * Double(tb.numer) / Double(tb.denom) / 1e9 }

// ---------- Contadores globais (baratos) ----------
func cpuTicks() -> (busy: Double, total: Double) {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
    }
    let t = info.cpu_ticks
    let busy = Double(t.0) + Double(t.1) + Double(t.3)  // user + system + nice
    return (busy, busy + Double(t.2))
}
func swapouts() -> UInt64 {
    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    return vm.swapouts
}
let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

// ---------- Coleta detalhada (só durante incidente) ----------
var ring: [[pid_t: Double]] = []  // CPU acumulada por processo, últimas 60 amostras
func detailedSample() {
    let n = proc_listallpids(nil, 0)
    var pids = [pid_t](repeating: 0, count: Int(n) * 2)
    let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    var snap: [pid_t: Double] = [:]
    for pid in pids.prefix(Int(max(got, 0))) where pid > 0 {
        var ru = rusage_info_v6()
        let r = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        if r == 0 { snap[pid] = secs(ru.ri_user_time + ru.ri_system_time) }
    }
    ring.append(snap); if ring.count > 60 { ring.removeFirst() }
}

// ---------- Autoavaliação ----------
func selfUsage() -> (cpu: Double, mem: Double, wakeups: UInt64, energyJ: Double) {
    var ru = rusage_info_v6()
    _ = withUnsafeMutablePointer(to: &ru) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) }
    }
    return (secs(ru.ri_user_time + ru.ri_system_time), Double(ru.ri_phys_footprint) / 1e6,
            ru.ri_pkg_idle_wkups + ru.ri_interrupt_wkups, Double(ru.ri_energy_nj) / 1e9)
}

// ---------- App de barra de menus ----------
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
func setIcon(_ incident: Bool) {  // redesenha só quando o estado muda (redesenho custa WindowServer)
    item.button?.image = NSImage(systemSymbolName: incident ? "exclamationmark.triangle.fill" : "light.beacon.max",
                                 accessibilityDescription: "Farol")
}
setIcon(false)

var last = cpuTicks(), lastSwap = swapouts()
var baseline: Double? = nil        // média móvel de núcleos ocupados
var strikes = 0
var incidentUntil: Date? = nil
var incidents = 0, firstDetection: Double? = nil
var lastReport = Date(), lastCost = selfUsage()

let q = DispatchQueue(label: "farol.sentinela", qos: .utility)  // núcleos de eficiência
let timer = DispatchSource.makeTimerSource(queue: q)
timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(interval * 250)))  // deixa o sistema agrupar wakeups
var detailTimer: DispatchSourceTimer? = nil

timer.setEventHandler {
    let now = cpuTicks(), sw = swapouts()
    let busyCores = (now.busy - last.busy) / max(now.total - last.total, 1) * cores
    let swapping = sw > lastSwap
    last = now; lastSwap = sw
    let thermal = ProcessInfo.processInfo.thermalState.rawValue >= 2

    if let b = baseline {
        strikes = (busyCores > b + 1.0 || swapping || thermal) ? strikes + 1 : 0
        if incidentUntil == nil { baseline = b * 0.95 + busyCores * 0.05 }
    } else { baseline = busyCores }

    if strikes >= 2 && incidentUntil == nil {   // anomalia sustentada → modo incidente
        incidents += 1
        if firstDetection == nil { firstDetection = Date().timeIntervalSince(started) }
        incidentUntil = Date().addingTimeInterval(30)
        DispatchQueue.main.async { setIcon(true) }
        let d = DispatchSource.makeTimerSource(queue: q)
        d.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(100))
        d.setEventHandler { detailedSample() }
        d.resume(); detailTimer = d
        print(String(format: "[%5.0fs] INCIDENTE: %.1f núcleos ocupados (normal %.1f)", Date().timeIntervalSince(started), busyCores, baseline ?? 0))
    }
    if let until = incidentUntil, Date() > until, strikes == 0 {
        detailTimer?.cancel(); detailTimer = nil; incidentUntil = nil
        DispatchQueue.main.async { setIcon(false) }
        print(String(format: "[%5.0fs] fim do incidente (%d amostras detalhadas guardadas)", Date().timeIntervalSince(started), ring.count))
    } else if let until = incidentUntil, Date() > until { incidentUntil = Date().addingTimeInterval(10) }

    if Date().timeIntervalSince(lastReport) >= 30 {  // relatório do próprio custo
        let u = selfUsage(), dt = Date().timeIntervalSince(lastReport)
        print(String(format: "[%5.0fs] modo=%@ CPU=%.3f%% de um núcleo  memória=%.1f MB  wakeups=%.1f/s  energia=%.2f mW",
                     Date().timeIntervalSince(started), incidentUntil == nil ? "repouso  " : "incidente",
                     100 * (u.cpu - lastCost.cpu) / dt, u.mem, Double(u.wakeups - lastCost.wakeups) / dt,
                     1000 * (u.energyJ - lastCost.energyJ) / dt))
        lastCost = u; lastReport = Date()
    }
    if Date().timeIntervalSince(started) > duration { print("incidentes: \(incidents)"); exit(0) }
}
timer.resume()
setvbuf(stdout, nil, _IOLBF, 0)
app.run()
