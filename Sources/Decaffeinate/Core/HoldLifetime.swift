import Foundation

/// How a hold will end — its "nature". Answers the user's question: is this
/// keeping the Mac awake until a task finishes, on a timer, or indefinitely?
/// Pure value type.
enum HoldLifetime: Equatable, Sendable {
    /// `caffeinate -w <pid>` with a live target — ends when that process exits.
    case untilProcess(String)
    /// Decaffeinate is actively watching this hold and will sleep when it's done.
    case untilWatchedFinishes
    /// A timeout (`caffeinate -t` / an auto-releasing assertion). Agents re-arm.
    case timed(reArms: Bool)
    /// No timeout, no wait target — held until the process releases it.
    case indefinite

    /// Short caps badge text for the row — three glanceable states.
    var badgeLabel: String {
        switch self {
        case .untilProcess, .untilWatchedFinishes: return "until done"
        case .timed: return "timed"
        case .indefinite: return "indefinite"
        }
    }

    /// The detail-view "Ends" copy.
    var detailLabel: String {
        switch self {
        case .untilProcess(let name): return "When \(name) finishes"
        case .untilWatchedFinishes: return "When the watched task finishes"
        case .timed(let reArms):
            return reArms ? "On a timer (re-arms automatically)" : "On a timer"
        case .indefinite: return "No timeout — held until released"
        }
    }

    /// True when the hold ends on its own / soon — the reassuring cases.
    var isBounded: Bool {
        switch self {
        case .untilProcess, .untilWatchedFinishes, .timed: return true
        case .indefinite: return false
        }
    }
}
