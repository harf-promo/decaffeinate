import AppKit
import Foundation
import UserNotifications

/// Notification action identifiers for the new-blocker category — kept as
/// constants so the delegate and the category registration can't drift.
enum BlockerNotificationAction {
    static let category = "com.harfpromo.decaffeinate.newBlocker"
    static let alwaysAllow = "ALWAYS_ALLOW"
    static let sleepAnyway = "SLEEP_ANYWAY"
    /// Carries the firewall key (the same key `AppState.key(_:)` computes) so
    /// the delegate can resolve the notification back to a live assertion.
    /// Never shown — `userInfo` isn't rendered, only `title`/`body` are — so
    /// this is fine to carry even though the visible copy must stay
    /// classified/fixed (see the file doc comment below).
    static let holderKeyInfoKey = "holderKey"
}

/// Best-effort user notifications for Decaffeinate events. Entirely guarded:
/// notifications only work from a real app bundle, so when Decaffeinate is run
/// as a bare binary (e.g. in CI or a smoke test) every call is a safe no-op.
///
/// All notification copy uses fixed, classified labels — never raw app-supplied
/// assertion text, which can carry a media title / file name and would leak to
/// the lock screen.
@MainActor
final class Notifier: NSObject {
    private var authorized = false
    private var requested = false
    private var categoriesRegistered = false

    /// Resolves a tapped notification action back into a policy change on the
    /// live app state. Weak so `Notifier` never strongly retains `AppState`.
    weak var actionHandler: NotifierActionHandling?

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorizationIfNeeded() {
        registerCategoriesIfNeeded()
        guard isBundled, !requested else { return }
        requested = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    /// Re-check the live OS notification-permission status on demand — unlike
    /// `authorized` above (a one-shot snapshot from the initial request), this
    /// notices a silent denial or a later revoke in System Settings, which
    /// otherwise leaves the firewall's notifications dead with no explanation.
    func refreshAuthorizationStatus(
        _ completion: @escaping @MainActor (NotificationAuthorization) -> Void
    ) {
        guard isBundled else { return completion(.unknown) }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: NotificationAuthorization
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = .authorized
            case .denied: status = .denied
            case .notDetermined: status = .unknown
            @unknown default: status = .unknown
            }
            Task { @MainActor in completion(status) }
        }
    }

    /// Register the "Always Allow" / "Sleep Anyway" actions once — needed
    /// before any notification sets `categoryIdentifier` to this category, so
    /// this is called both from `requestAuthorizationIfNeeded()` (first launch)
    /// and lazily the first time a categorized notification is about to post.
    private func registerCategoriesIfNeeded() {
        guard isBundled, !categoriesRegistered else { return }
        categoriesRegistered = true
        let alwaysAllow = UNNotificationAction(
            identifier: BlockerNotificationAction.alwaysAllow, title: "Always Allow", options: [])
        let sleepAnyway = UNNotificationAction(
            identifier: BlockerNotificationAction.sleepAnyway, title: "Sleep Anyway",
            options: [.destructive])
        let category = UNNotificationCategory(
            identifier: BlockerNotificationAction.category,
            actions: [alwaysAllow, sleepAnyway],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: Typed notification methods

    func notifyNewBlocker(appName: String, reason: String, holderKey: String) {
        post(
            title: "\(appName) is keeping your Mac awake",
            body: "\(reason) — open Decaffeinate to allow it or let your Mac sleep anyway.",
            categoryIdentifier: BlockerNotificationAction.category,
            userInfo: [BlockerNotificationAction.holderKeyInfoKey: holderKey])
    }

    /// A burst of ≥2 new blockers surfacing together — one digest notification
    /// instead of a one-per-app drip. No actions: with several apps at once
    /// there's no single "Always Allow" target, so this just points back to
    /// the app to review them individually.
    func notifyNewBlockers(count: Int, sample: String) {
        post(
            title: "\(count) apps started keeping your Mac awake",
            body: "\(sample) and \(count - 1) other\(count - 1 == 1 ? "" : "s") — open Decaffeinate to review them."
        )
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

    private func post(
        title: String, body: String, categoryIdentifier: String? = nil,
        userInfo: [String: String] = [:]
    ) {
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
        if let categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
        if !userInfo.isEmpty { content.userInfo = userInfo }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Notification action → policy change

    /// Resolve a tapped action and apply it via `actionHandler`. Internal (not
    /// private) so the delegate extension below can call it.
    private func handleAction(_ actionIdentifier: String, holderKey: String?) {
        guard let holderKey,
            let assertion = actionHandler?.resolveAssertion(forFirewallKey: holderKey)
        else { return }
        switch actionIdentifier {
        case BlockerNotificationAction.alwaysAllow:
            actionHandler?.setPolicy(.allow, for: assertion)
        case BlockerNotificationAction.sleepAnyway:
            actionHandler?.setPolicy(.ignore, for: assertion)
        default:
            break
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// `nonisolated` because `UNUserNotificationCenterDelegate`'s requirements
    /// aren't main-actor-isolated in the SDK and the framework may call them
    /// off the main thread — hop back to the main actor explicitly for the
    /// `@MainActor` state this touches (`handleAction`, `actionHandler`).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let holderKey =
            response.notification.request.content.userInfo[BlockerNotificationAction.holderKeyInfoKey]
            as? String
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor in
            self.handleAction(actionIdentifier, holderKey: holderKey)
        }
        completionHandler()
    }

    /// Show the banner even while Decaffeinate is frontmost — a menu-bar
    /// accessory app has no window to "already be looking at", so the default
    /// (silent-while-foreground) behavior would just make notifications vanish.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension Notifier {
    /// Deep-link into System Settings → Notifications — the "Notifications:
    /// Off — Enable" nudge (menu + Settings) when the user has denied or later
    /// revoked permission.
    static func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
