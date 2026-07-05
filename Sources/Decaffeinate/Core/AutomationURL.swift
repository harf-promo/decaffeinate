import Foundation

/// The `decaffeinate://…` URL scheme — the always-works automation surface
/// (Shortcuts' "Open URLs" action needs no App Intents metadata). Parsing is pure
/// and testable; `DecaffeinateApp.AppDelegate.application(_:open:)` applies the
/// result against `AppState.shared`.
///
///     decaffeinate://sleep-now
///     decaffeinate://keep-awake?minutes=30
///     decaffeinate://stop-awake
enum AutomationURL {
    static let scheme = "decaffeinate"

    enum Action: Equatable {
        case sleepNow
        case keepAwake(minutes: Int)
        case stopAwake
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
