import Foundation

/// How fresh the system is, by uptime — the basis for "a restart would help."
enum RestartAdvice: String, Sendable, Equatable, CaseIterable {
    case fresh  // well under the recommendation window
    case consider  // crossed the window (default 7 days)
    case overdue  // ~2× the window
    case urgent  // approaching the ~49.7-day uptime/networking cliff

    var symbol: String {
        switch self {
        case .fresh: return "checkmark.seal.fill"
        case .consider: return "clock.badge"
        case .overdue: return "clock.badge.exclamationmark"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
}

/// Pure recommendation logic (no clock of its own — takes uptime directly, so
/// tests drive it deterministically). Mirrors `ScheduleEngine`'s stateless style.
enum RestartAdvisor {
    /// macOS's ~49.7-day uptime ceiling where the `tcp_now` counter can overflow
    /// and networking starts failing (Tom's Hardware). We escalate to `.urgent`
    /// a few days before so the user can restart on their own terms.
    static let networkingCliffDays = 49.7
    static let urgentThresholdDays = 45.0

    static func advice(uptime: TimeInterval, recommendAfterDays: Int) -> RestartAdvice {
        let days = uptime / 86_400
        if days >= urgentThresholdDays { return .urgent }
        let window = Double(max(1, recommendAfterDays))
        if days >= window * 2 { return .overdue }
        if days >= window { return .consider }
        return .fresh
    }

    /// "9 days" / "3 hours" / "12 min" — the headline uptime label.
    static func uptimeLabel(_ uptime: TimeInterval) -> String {
        let days = Int(uptime / 86_400)
        if days >= 1 {
            return days == 1 ? L10n.localized("1 day") : L10n.localized("%ld days", days)
        }
        let hours = Int(uptime / 3_600)
        if hours >= 1 {
            return hours == 1 ? L10n.localized("1 hour") : L10n.localized("%ld hours", hours)
        }
        return L10n.localized("%ld min", max(0, Int(uptime / 60)))
    }

    static func daysSinceBoot(_ uptime: TimeInterval) -> Int { Int(uptime / 86_400) }

    /// The calm, in-app one-liner for each level.
    static func message(_ advice: RestartAdvice, uptimeLabel: String) -> String {
        switch advice {
        case .fresh:
            return L10n.localized(
                "Up %@ \u{2014} fresh. Daily sleep is doing its job.", uptimeLabel)
        case .consider:
            return L10n.localized("Up %@ \u{2014} a restart would freshen things up.", uptimeLabel)
        case .overdue:
            return L10n.localized("Up %@ \u{2014} a weekly restart is overdue.", uptimeLabel)
        case .urgent:
            return L10n.localized(
                "Up %@ \u{2014} restart soon: macOS networking can fail near 50 days of uptime.",
                uptimeLabel)
        }
    }

    /// The research reason shown under the message.
    static func reason(_ advice: RestartAdvice) -> String {
        switch advice {
        case .fresh:
            return L10n.localized(
                "Sleep pauses your Mac; a restart clears it. You're in good shape.")
        case .consider, .overdue:
            return L10n.localized(
                "A restart clears memory leaks and caches, resets the network stack, and applies pending updates \u{2014} things sleep can't do."
            )
        case .urgent:
            return L10n.localized(
                "macOS has a ~49-day uptime limit where networking can stop working until you restart."
            )
        }
    }
}
