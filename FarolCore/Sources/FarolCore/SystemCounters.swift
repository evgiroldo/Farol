import Darwin
import Foundation

/// Thermal pressure as reported by `ProcessInfo.thermalState` (public API).
public enum ThermalLevel: Int, Sendable, Comparable, Codable {
    case nominal = 0
    case fair, serious, critical

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}

/// Memory-pressure level, as delivered by the public `DispatchSource` memory-pressure
/// events (see `MemoryPressureMonitor`).
public enum MemoryPressure: Int, Sendable, Comparable, Codable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (a: MemoryPressure, b: MemoryPressure) -> Bool { a.rawValue < b.rawValue }
}

/// One reading of cheap, system-wide counters. Reading it costs microseconds,
/// which is what lets the sentinel run continuously (ADR 0011).
public struct SystemSnapshot: Sendable, Equatable {
    /// Seconds since boot (monotonic).
    public var uptime: TimeInterval
    /// CPU ticks spent in user, system and nice, summed over all cores. Wraps around.
    public var busyTicks: UInt32
    /// All CPU ticks including idle, summed over all cores. Wraps around.
    public var totalTicks: UInt32
    /// Pages swapped out since boot.
    public var swapouts: UInt64
    /// `nil` when unavailable — never guessed as `.normal`.
    public var memoryPressure: MemoryPressure?
    public var thermal: ThermalLevel

    public init(
        uptime: TimeInterval, busyTicks: UInt32, totalTicks: UInt32, swapouts: UInt64,
        memoryPressure: MemoryPressure?, thermal: ThermalLevel
    ) {
        self.uptime = uptime
        self.busyTicks = busyTicks
        self.totalTicks = totalTicks
        self.swapouts = swapouts
        self.memoryPressure = memoryPressure
        self.thermal = thermal
    }
}

/// System load between two snapshots.
public struct SystemLoad: Sendable, Equatable {
    /// Average number of busy cores over the interval (0...core count).
    public var busyCores: Double
    /// Pages swapped out per second during the interval.
    public var swapoutsPerSecond: Double
    public var memoryPressure: MemoryPressure?
    public var thermal: ThermalLevel
    public var interval: TimeInterval

    public init(
        busyCores: Double, swapoutsPerSecond: Double = 0, memoryPressure: MemoryPressure? = .normal,
        thermal: ThermalLevel = .nominal, interval: TimeInterval = 2
    ) {
        self.busyCores = busyCores
        self.swapoutsPerSecond = swapoutsPerSecond
        self.memoryPressure = memoryPressure
        self.thermal = thermal
        self.interval = interval
    }

    /// Computes the load between `earlier` and `later`. Tick counters are 32-bit and
    /// wrap around, so the subtraction is wrapping.
    public init(from earlier: SystemSnapshot, to later: SystemSnapshot, cores: Int) {
        let busy = Double(later.busyTicks &- earlier.busyTicks)
        let total = Double(later.totalTicks &- earlier.totalTicks)
        busyCores = total > 0 ? min(busy / total, 1) * Double(cores) : 0
        interval = later.uptime - earlier.uptime
        let swapped = later.swapouts >= earlier.swapouts ? Double(later.swapouts - earlier.swapouts) : 0
        swapoutsPerSecond = interval > 0 ? swapped / interval : 0
        memoryPressure = later.memoryPressure
        thermal = later.thermal
    }
}

public enum SystemCounters {
    /// Number of CPU cores the system currently uses.
    public static var coreCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// Reads all counters. `memoryPressure` comes from a `MemoryPressureMonitor` (event
    /// driven), so this call stays a pure read. Returns `nil` if the kernel refuses.
    public static func read(memoryPressure: MemoryPressure?) -> SystemSnapshot? {
        guard let ticks = cpuTicks(), let swapouts = swapouts() else { return nil }
        return SystemSnapshot(
            uptime: ProcessInfo.processInfo.systemUptime,
            busyTicks: ticks.busy,
            totalTicks: ticks.total,
            swapouts: swapouts,
            memoryPressure: memoryPressure,
            thermal: ThermalLevel(ProcessInfo.processInfo.thermalState)
        )
    }

    /// Boot time in seconds since 1970 (`kern.boottime`, documented in sysctl(3)).
    public static func bootTime() -> Double? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return nil }
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
    }

    static func cpuTicks() -> (busy: UInt32, total: UInt32)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks  // (user, system, idle, nice)
        let busy = t.0 &+ t.1 &+ t.3
        return (busy, busy &+ t.2)
    }

    static func swapouts() -> UInt64? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? vm.swapouts : nil
    }
}
