import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`. The lease's
/// externally-visible status: what every XPC reply in `LidHelperXPCProtocol`
/// carries, and what `LidHelperService` hands back after each call. Pure
/// value type — `Codable` so it can cross the XPC boundary JSON-encoded (see
/// `LidHelperXPCProtocol`'s doc comment for why), and so both this type and
/// `LidHelperService`'s bookkeeping are fully unit-testable without any live
/// XPC connection.
public struct LeaseState: Equatable, Sendable, Codable {
    public var isActive: Bool
    public var expiresAt: Date?
    public var helperVersion: String

    public init(isActive: Bool, expiresAt: Date?, helperVersion: String = LeaseState.currentHelperVersion) {
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.helperVersion = helperVersion
    }

    /// Bumped when the helper's XPC surface or lease semantics change —
    /// echoed by `helperVersion(reply:)` so an app client could refuse to
    /// talk to a helper version it doesn't understand, rather than guessing.
    public static let currentHelperVersion = "1.0.0-spike"

    public static func inactive(helperVersion: String = currentHelperVersion) -> LeaseState {
        LeaseState(isActive: false, expiresAt: nil, helperVersion: helperVersion)
    }
}
