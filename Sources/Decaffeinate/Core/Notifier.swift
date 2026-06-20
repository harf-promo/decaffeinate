import Foundation
import UserNotifications

/// Best-effort user notifications for firewall alerts ("a new app is keeping
/// your Mac awake"). Entirely guarded: notifications only work from a real app
/// bundle, so when Decaffeinate is run as a bare binary (e.g. in CI or a smoke
/// test) every call is a safe no-op instead of a crash.
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

    func notifyNewBlocker(appName: String, assertionName: String) {
        guard isBundled else { return }
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "\(appName) is keeping your Mac awake"
        content.body = "“\(assertionName)” — open Decaffeinate to Allow or Block it."
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
