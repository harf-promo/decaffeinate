import Foundation

/// The `decaffeinate://…` URL scheme — the always-works automation surface
/// (Shortcuts' "Open URLs" action needs no App Intents metadata). Parsing is pure
/// and testable; `DecaffeinateApp.AppDelegate.application(_:open:)` applies the
/// result against `AppState.shared`.
///
///     decaffeinate://sleep-now
///     decaffeinate://keep-awake?minutes=30
///     decaffeinate://stop-awake
///
/// Actions are applied by `AppState.applyAutomationURL(_:)`. Any local process
/// (or a web page, after a browser "always allow") can open a custom-scheme URL,
/// so the destructive verbs (`sleep-now`, `stop-awake`) are inert unless the
/// user turns on Settings → "Allow URL-scheme actions", and `sleep-now` still
/// honours the in-call guard (a live microphone raises the "Sleep anyway?"
/// confirmation instead of sleeping). `keep-awake` only holds the Mac awake
/// behind the safety rails, so it is not gated.
enum AutomationURL {
    static let scheme = "decaffeinate"

    enum Action: Equatable {
        case sleepNow
        case keepAwake(minutes: Int)
        case stopAwake

        /// Verbs that sleep the Mac or drop the user's keep-awake: gated behind
        /// the opt-in `allowURLSchemeActions` setting.
        var isDestructive: Bool {
            switch self {
            case .sleepNow, .stopAwake: return true
            case .keepAwake: return false
            }
        }

        /// The URL verb, for logs.
        var verb: String {
            switch self {
            case .sleepNow: return "sleep-now"
            case .stopAwake: return "stop-awake"
            case .keepAwake: return "keep-awake"
            }
        }
    }

    /// Parse a URL into an action, or `nil` if it isn't a recognized command.
    static func parse(_ url: URL) -> Action? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        // The verb rides in the host: decaffeinate://<verb>?<query>
        switch url.host()?.lowercased() {
        case "sleep-now":
            return .sleepNow
        case "stop-awake":
            return .stopAwake
        case "keep-awake":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let raw = items?.first { $0.name == "minutes" }?.value
            let minutes = raw.flatMap(Int.init) ?? 30
            return .keepAwake(minutes: min(max(minutes, 1), 24 * 60))
        default:
            return nil
        }
    }
}
