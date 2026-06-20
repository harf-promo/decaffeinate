import Foundation

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
        case .ignore: return "Block"
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

    init(id: UUID = UUID(),
         bundleIdentifier: String?,
         processName: String,
         displayName: String,
         policy: RulePolicy) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.processName = processName
        self.displayName = displayName
        self.policy = policy
    }

    func matches(_ assertion: PowerAssertion) -> Bool {
        // A bundle-scoped rule must match by bundle id — never fall back to the
        // process name, or it would also catch unrelated nil-bundle daemons that
        // happen to share the executable name.
        if let bundleIdentifier {
            guard let other = assertion.bundleIdentifier else { return false }
            return bundleIdentifier.caseInsensitiveCompare(other) == .orderedSame
        }
        return processName.caseInsensitiveCompare(assertion.processName) == .orderedSame
    }
}
