// Protótipo descartável do "Culpado real" — NÃO é código do Farol.
// Uso: sampler <segundos> [--intervene]
// 1. Amostra a cada 1 s: CPU e bytes gravados de cada processo do usuário (proc_pid_rusage, sem root)
//    e CPU dos daemons do sistema via /bin/ps (setuid da Apple; nosso app não ganha privilégio).
// 2. Correlaciona a variação de cada daemon com a de cada processo do usuário e ranqueia suspeitos.
// 3. --intervene: pausa (SIGSTOP) por 3 s cada suspeito cujo nome começa com "farol-" e mede o efeito.
import Darwin
import Foundation

let daemons = ["WindowServer", "mds_stores"]
let seconds = Int(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let intervene = CommandLine.arguments.contains("--intervene")
let me = getpid()

var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func ticksToSec(_ t: UInt64) -> Double { Double(t) * Double(tb.numer) / Double(tb.denom) / 1e9 }

struct Sample { var cpu: Double; var writes: Double }

func name(of pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 256)
    return proc_name(pid, &buf, 256) > 0 ? String(cString: buf) : ""
}

func userProcesses() -> [pid_t: (String, Sample)] {
    let n = proc_listallpids(nil, 0)
    var pids = [pid_t](repeating: 0, count: Int(n) * 2)
    let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    var out: [pid_t: (String, Sample)] = [:]
    for pid in pids.prefix(Int(max(got, 0))) where pid > 0 && pid != me {
        var ru = rusage_info_v6()
        let r = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        guard r == 0 else { continue }  // processo de outro usuário: bloqueado sem root
        out[pid] = (name(of: pid), Sample(cpu: ticksToSec(ru.ri_user_time + ru.ri_system_time),
                                          writes: Double(ru.ri_diskio_byteswritten)))
    }
    return out
}

func daemonPids() -> [String: pid_t] {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axo", "pid=,comm="]
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    var out: [String: pid_t] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let pid = pid_t(parts[0]) else { continue }
        let comm = String(parts[1].split(separator: "/").last ?? "")
        if daemons.contains(comm) { out[comm] = pid }
    }
    return out
}

func parseCPUTime(_ s: Substring) -> Double {  // "97:02.63" ou "1:02:03.44"
    s.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
}

func daemonCPU(_ pids: [String: pid_t]) -> [String: Double] {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "pid=,time=", "-p", pids.values.map(String.init).joined(separator: ",")]
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    let byPid = Dictionary(uniqueKeysWithValues: pids.map { ($1, $0) })
    var out: [String: Double] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count == 2, let pid = pid_t(parts[0]), let d = byPid[pid] { out[d] = parseCPUTime(parts[1]) }
    }
    return out
}

func pearson(_ a: [Double], _ b: [Double]) -> Double {
    let n = Double(a.count); guard n > 2 else { return 0 }
    let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
    var num = 0.0, da = 0.0, db = 0.0
    for i in a.indices { num += (a[i]-ma)*(b[i]-mb); da += (a[i]-ma)*(a[i]-ma); db += (b[i]-mb)*(b[i]-mb) }
    return (da == 0 || db == 0) ? 0 : num / (da.squareRoot() * db.squareRoot())
}

// ---------- Coleta ----------
let dpids = daemonPids()
print("daemons: \(dpids)  coletando \(seconds) s…")
var userSeries: [[pid_t: (String, Sample)]] = []
var daemonSeries: [[String: Double]] = []
var samplerCost = 0.0
let selfStart = ProcessInfo.processInfo.systemUptime
var startRU = rusage(); getrusage(RUSAGE_SELF, &startRU)
for _ in 0...seconds {
    let t0 = Date()
    userSeries.append(userProcesses())
    daemonSeries.append(daemonCPU(dpids))
    Thread.sleep(forTimeInterval: max(0, 1 - Date().timeIntervalSince(t0)))
}
var endRU = rusage(); getrusage(RUSAGE_SELF, &endRU)
var endChildren = rusage(); getrusage(RUSAGE_CHILDREN, &endChildren)
func tv(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
samplerCost = (tv(endRU.ru_utime) + tv(endRU.ru_stime) - tv(startRU.ru_utime) - tv(startRU.ru_stime)
               + tv(endChildren.ru_utime) + tv(endChildren.ru_stime))
let wall = ProcessInfo.processInfo.systemUptime - selfStart
print(String(format: "custo do amostrador: %.2f%% de um núcleo (incl. /bin/ps)", 100 * samplerCost / wall))

// ---------- Análise ----------
func deltas(_ xs: [Double]) -> [Double] { zip(xs.dropFirst(), xs).map { $0 - $1 } }
var suspects: [String: [(pid_t, String, Double)]] = [:]
for d in daemons {
    let dser = deltas(daemonSeries.map { $0[d] ?? 0 })
    let total = dser.reduce(0, +)
    print("\n== \(d): \(String(format: "%.1f", 100 * total / Double(dser.count)))% CPU médio no período")
    let pidsEverywhere = Set(userSeries.first!.keys).intersection(userSeries.last!.keys)
    var ranking: [(pid_t, String, Double, Double)] = []
    for pid in pidsEverywhere {
        let nm = userSeries[0][pid]!.0
        let metric: (Sample) -> Double = d == "mds_stores" ? { $0.writes } : { $0.cpu }
        let series = deltas(userSeries.map { $0[pid].map { metric($0.1) } ?? 0 })
        let r = pearson(series, dser)
        if series.contains(where: { $0 > 0 }) { ranking.append((pid, nm, r, series.reduce(0, +))) }
    }
    ranking.sort { $0.2 > $1.2 }
    for (pid, nm, r, tot) in ranking.prefix(5) {
        let unit = d == "mds_stores" ? String(format: "%.1f MB gravados", tot / 1e6) : String(format: "%.1f s CPU", tot)
        print(String(format: "  r=%+.2f  %@ (%d)  %@", r, nm, pid, unit))
    }
    suspects[d] = ranking.prefix(3).map { ($0.0, $0.1, $0.2) }
}

// ---------- Intervenção (só nos nossos processos de teste) ----------
guard intervene else { exit(0) }
func rate(_ d: String, over secs: Double) -> Double {
    let a = daemonCPU(dpids)[d] ?? 0; Thread.sleep(forTimeInterval: secs); return ((daemonCPU(dpids)[d] ?? 0) - a) / secs
}
print("\n== Teste de causa (pausa de 3 s em cada suspeito)")
for d in daemons {
    for (pid, nm, _) in suspects[d] ?? [] where nm.hasPrefix("farol-") {
        let before = rate(d, over: 3)
        kill(pid, SIGSTOP); let during = rate(d, over: 3); kill(pid, SIGCONT)
        let drop = before > 0 ? 100 * (before - during) / before : 0
        print(String(format: "  %@ ← pausar %@: %.1f%% → %.1f%% (queda de %.0f%%)", d, nm, 100*before, 100*during, drop))
    }
}
