import Foundation
import UserNotifications

/// Best-effort user notifications for Decaffeinate events. Entirely guarded:
/// notifications only work from a real app bundle, so when Decaffeinate is run
/// as a bare binary (e.g. in CI or a smoke test) every call is a safe no-op.
///
/// All notification copy uses fixed, classified labels — never raw app-supplied
/// assertion text, which can carry a media title / file name and would leak to
/// the lock screen.
@MainActor
final class Notifier {
    private var authorized = false
    private var requested = false

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorizationIfNeeded() {
        guard isBundled, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    // MARK: Typed notification methods

    func notifyNewBlocker(appName: String, reason: String) {
        post(
            title: "\(appName) is keeping your Mac awake",
            body: "\(reason) — open Decaffeinate to allow it or let your Mac sleep anyway.")
    }

    func notifyForcedSleep(reason: String) {
        post(
            title: "Putting your Mac to sleep",
            body: "Decaffeinate stepped in — \(reason).")
    }

    func notifyAgentFinished(label: String) {
        post(
            title: "\(label) finished",
            body: "Decaffeinate is letting your Mac sleep now.")
    }

    func notifyRestartOverdue(uptimeLabel: String) {
        post(
            title: "A restart is overdue",
            body:
                "Your Mac has been up \(uptimeLabel). A weekly restart clears what sleep can't.")
    }

    // MARK: Private

    private func post(title: String, body: String) {
        // Only post once the user has explicitly granted notification permission.
        // `requestAuthorizationIfNeeded()` is called by the onboarding flow so the
        // OS prompt arrives with context rather than cold at app launch. Never
        // auto-request here — that would bypass the onboarding deferral, surfacing
        // the system sheet on first run before the user understands what it's for.
        guard isBundled, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
