/// Where a value comes from (ADR 0003). Every number Farol shows carries one.
public enum Provenance: Sendable, Equatable {
    /// Read directly from the operating system.
    case measured
    /// Derived from measured values with a known approximation.
    case estimated
    /// Concluded statistically; `confidence` is in 0...1.
    case inferred(confidence: Double)
}

/// A value together with its provenance. `nil` means the reading is unavailable,
/// which is different from a measured zero.
public struct Reading<Value: Sendable>: Sendable {
    public let value: Value?
    public let provenance: Provenance

    public init(_ value: Value?, _ provenance: Provenance) {
        self.value = value
        self.provenance = provenance
    }

    public static func unavailable(_ provenance: Provenance = .measured) -> Reading {
        Reading(nil, provenance)
    }
}

extension Reading: Equatable where Value: Equatable {}
