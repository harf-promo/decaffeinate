import Foundation

/// Preset durations for a temporary "allow" — the firewall's
/// "Allow for a custom duration" action.
enum AllowDuration: CaseIterable, Hashable, Sendable {
    case thirtyMinutes
    case oneHour
    case fourHours
    case untilTomorrow

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .fourHours: return "4 hours"
        case .untilTomorrow: return "Until tomorrow"
        }
    }

    /// The expiry date for this duration, measured from `now`.
    func expiry(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .thirtyMinutes: return now.addingTimeInterval(30 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .fourHours: return now.addingTimeInterval(4 * 60 * 60)
        case .untilTomorrow:
            // 8am the next calendar day.
            let tomorrow =
                calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.date(
                bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
                ?? tomorrow
        }
    }
}

/// What Decaffeinate should do about a given application's sleep-blocking
/// assertions. Mirrors the four firewall prompt actions in the PRD.
enum RulePolicy: Codable, Hashable, Sendable {
    /// Whitelist: this app is *allowed* to keep the Mac awake. While it holds a
    /// system-sleep assertion, Decaffeinate will not force sleep.
    case allow
    /// Allow, but only until the given date (e.g. "for this 1-hour download").
    case allowUntil(Date)
    /// Blacklist: this app's sleep-blocking assertions are disregarded — the Mac
    /// is free to sleep when idle even while this app is running.
    case ignore

    var isCurrentlyAllowing: Bool {
        switch self {
        case .allow: return true
        case .allowUntil(let date): return date > Date()
        case .ignore: return false
        }
    }

    var shortLabel: String {
        switch self {
        case .allow: return "Always allow"
        case .allowUntil: return "Allow temporarily"
        case .ignore: return "Ignored"
        }
    }
}

/// A persisted firewall rule, matched against a running process either by bundle
/// identifier (preferred, stable) or by executable name (for daemons/helpers).
struct Rule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Bundle identifier, e.g. `com.google.Chrome`. `nil` for non-GUI processes.
    var bundleIdentifier: String?
    /// Executable name, e.g. `Google Chrome` or `node`.
    var processName: String
    /// Friendly label shown in the rules editor.
    var displayName: String
    var policy: RulePolicy

    init(
        id: UUID = UUID(),
        bundleIdentifier: String?,
        processName: String,
        displayName: String,
        policy: RulePolicy
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.processName = processName
        self.displayName = displayName
        self.policy = policy
    }

    func matches(_ assertion: PowerAssertion) -> Bool {
        // Match either the owning process or, for holds routed through a shared
        // daemon, the attributed real owner — so "Always allow" on the app the
        // user actually sees ("Safari (via runningboardd)") keeps working.
        if matchesIdentity(bundle: assertion.bundleIdentifier, process: assertion.processName) {
            return true
        }
        if let owner = assertion.realOwner,
            matchesIdentity(bundle: owner.bundleIdentifier, process: owner.name)
        {
            return true
        }
        return false
    }

    private func matchesIdentity(bundle: String?, process: String) -> Bool {
        // A bundle-scoped rule must match by bundle id — never fall back to the
        // process name, or it would also catch unrelated nil-bundle daemons that
        // happen to share the executable name.
        if let bundleIdentifier {
            guard let bundle else { return false }
            return bundleIdentifier.caseInsensitiveCompare(bundle) == .orderedSame
        }
        return processName.caseInsensitiveCompare(process) == .orderedSame
    }
}
