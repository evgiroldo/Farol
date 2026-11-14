import Dispatch
import Synchronization

/// Tracks the system memory-pressure level through the public `DispatchSource`
/// memory-pressure events, without polling.
///
/// The events only report changes, so the level is `nil` ("unavailable") until the first
/// event arrives; Farol never assumes `.normal` (ADR 0019). No undocumented sysctl is read.
public final class MemoryPressureMonitor: Sendable {
    private let state = Mutex<MemoryPressure?>(nil)
    private let source: DispatchSourceMemoryPressure

    /// - Parameter queue: where events are delivered; use a low-QoS queue.
    public init(queue: DispatchQueue) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            let level: MemoryPressure? =
                event.contains(.critical)
                ? .critical
                : event.contains(.warning)
                    ? .warning
                    : event.contains(.normal) ? .normal : nil
            if let level { self.record(level) }
        }
        source.activate()
    }

    deinit { source.cancel() }

    /// The last level reported by the system, or `nil` if none has been reported yet.
    public var current: MemoryPressure? { state.withLock { $0 } }

    /// Records a level directly (tests, or a future documented source).
    func record(_ level: MemoryPressure) { state.withLock { $0 = level } }
}
