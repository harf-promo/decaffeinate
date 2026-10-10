import AppKit
import Foundation

/// The system's sleep/wake/display transitions, as ``AppState`` consumes them.
/// One case per public `NSWorkspace` notification the app observes — no
/// interpretation here; what each event *means* stays in
/// `AppState.handlePowerEvent(_:)`.
enum SystemPowerEvent: Equatable, Sendable {
    /// `NSWorkspace.willSleepNotification` — the kernel is beginning a real
    /// sleep transition.
    case willSleep
    /// `NSWorkspace.didWakeNotification`.
    case didWake
    /// `NSWorkspace.screensDidSleepNotification`.
    case screensDidSleep
    /// `NSWorkspace.screensDidWakeNotification`.
    case screensDidWake
}

/// The seam for the sleep/wake event stream, so tests can play a scripted
/// sleep → wake sequence into `AppState` instead of waiting on a real Mac to
/// sleep (see `Tests/DecaffeinateTests/SleepSimulator.swift`).
@MainActor
protocol SystemPowerEventSource {
    /// Begin delivering events to `handler`, on the main actor. Calling it again
    /// while already started is a no-op (the first handler stays registered).
    func start(_ handler: @escaping @MainActor (SystemPowerEvent) -> Void)
    /// Stop delivering events. Safe to call when not started.
    func stop()
}

/// The production source: public `NSWorkspace` notifications — local AppKit
/// callbacks, not user notifications.
@MainActor
final class WorkspacePowerEventSource: SystemPowerEventSource {
    private var tokens: [NSObjectProtocol] = []

    func start(_ handler: @escaping @MainActor (SystemPowerEvent) -> Void) {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, SystemPowerEvent)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
        ]
        for (name, event) in pairs {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(event) }
            }
            tokens.append(token)
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }
}
