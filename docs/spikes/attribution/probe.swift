import Darwin
// Quais processos conseguimos ler sem root?
let n = proc_listallpids(nil, 0)
var pids = [pid_t](repeating: 0, count: Int(n) * 2)
let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
var ok = 0, fail = 0
var interesting: [String] = []
for pid in pids.prefix(Int(got)) where pid > 0 {
    var ru = rusage_info_v6()
    let r = withUnsafeMutablePointer(to: &ru) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
    }
    var nameBuf = [CChar](repeating: 0, count: 256)
    proc_name(pid, &nameBuf, 256)
    let name = String(cString: nameBuf)
    if r == 0 { ok += 1 } else { fail += 1 }
    if ["WindowServer","mds_stores","mds","kernel_task","mdworker_shared","launchd","coreaudiod"].contains(name) {
        interesting.append("\(name)(\(pid)): \(r == 0 ? "OK cpu=\(ru.ri_user_time+ru.ri_system_time) writes=\(ru.ri_diskio_byteswritten) energy_nj=\(ru.ri_energy_nj)" : "FALHOU errno=\(errno)")")
    }
}
print("processos: \(got)  legiveis: \(ok)  bloqueados: \(fail)")
interesting.forEach { print($0) }
