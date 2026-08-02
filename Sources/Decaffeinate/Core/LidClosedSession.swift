import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`. Not referenced by
/// `AppState.swift` or any View — see `LidHelperClient.swift`'s top comment.

/// Why a lid-closed session ended — mirrors `HoldLifetime`'s "nature" shape:
/// answers the user's plain-language "why did this stop" question. Pure
/// value type.
enum LidClosedEndReason: Equatable, Sendable {
    case userReleased
    case leaseExpired
    case lidReopened
    case batteryFloorBreached
    case thermalRail
    case helperUnreachable
}

/// The lid-closed session's lifecycle — mirrors `HoldLifetime`'s /
/// `CaffeineEngine.ReconcileAction`'s pure-state-machine shape exactly: no
/// XPC, no IOKit, no timers live inside it, only already-known facts a real
/// (never-built-in-this-spike) coordinator would feed in via `Event`. Fully
/// unit-testable without a live helper.
enum LidClosedSession: Equatable, Sendable {
    /// Requested but not yet confirmed active by the helper.
    case armed(ttlSeconds: Int)
    /// The helper confirmed the lease; `expiresAt` mirrors its reply.
    case active(expiresAt: Date)
    /// Ended; retained so the UI could show why before clearing.
    case ending(reason: LidClosedEndReason)

    /// The event stream a real coordinator would drive this with.
    enum Event: Equatable, Sendable {
        case helperConfirmed(expiresAt: Date)
        case helperUnreachable
        case heartbeatRenewed(expiresAt: Date)
        case userReleased
        case leaseExpired
        case lidReopened
        case batteryFloorBreached
        case thermalRail
    }

    /// Pure transition — mirrors `CaffeineEngine.reconcileAction`'s shape: a
    /// static function from (state, event) to the next state, no side
    /// effects, no dependency on wall-clock time beyond what `event` itself
    /// carries.
    static func transition(_ state: LidClosedSession, on event: Event) -> LidClosedSession {
        switch (state, event) {
        case (.armed, .helperConfirmed(let expiresAt)):
            return .active(expiresAt: expiresAt)
        case (.armed, .helperUnreachable):
            return .ending(reason: .helperUnreachable)

        case (.active, .heartbeatRenewed(let expiresAt)):
            return .active(expiresAt: expiresAt)
        case (.active, .userReleased):
            return .ending(reason: .userReleased)
        case (.active, .leaseExpired):
            return .ending(reason: .leaseExpired)
        case (.active, .lidReopened):
            return .ending(reason: .lidReopened)
        case (.active, .batteryFloorBreached):
            return .ending(reason: .batteryFloorBreached)
        case (.active, .thermalRail):
            return .ending(reason: .thermalRail)
        case (.active, .helperUnreachable):
            return .ending(reason: .helperUnreachable)

        // Once ending, the session is done — a further event is ignored
        // rather than resurrecting a session that already told the user why
        // it stopped (mirrors the helper's own dead-man-switch one-way logic
        // in `LidHelperService.renewLease`).
        case (.ending, _):
            return state

        // Any (state, event) pair not covered above is a no-op — e.g.
        // `.armed` doesn't respond to `.active`-only events like
        // `.leaseExpired`. Documented here rather than exhaustively spelling
        // out every irrelevant pair.
        default:
            return state
        }
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
