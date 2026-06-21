import AppKit
import SwiftUI

/// Real entry point: dispatch headless CLI commands first, otherwise run the
/// SwiftUI menu-bar app.
@main
enum Main {
    static func main() {
        if MainActor.assumeIsolated({ CLI.handleIfNeeded(CommandLine.arguments) }) {
            return
        }
        DecaffeinateApp.main()
    }
}

struct DecaffeinateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.rulesEngine)
                .environmentObject(updater)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: MugIcon.image(for: appState.mug))
                    .renderingMode(.template)
                if let countdown = appState.menuBarCountdownText {
                    Text(countdown).monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(appState.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.rulesEngine)
                .environmentObject(appState.history)
        }
    }
}

/// Runs the app as a menu-bar accessory (no Dock icon) and drives the engine
/// lifecycle. Bodies are dispatched on the main actor — these callbacks always
/// arrive on the main thread.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            AppState.shared.start()
            // First run: welcome the user (and own the notification prompt).
            OnboardingPresenter.shared.showIfNeeded(
                settingsStore: AppState.shared.settingsStore)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.shutDown()
        }
    }
}

extension AppState {
    /// Single shared instance wired into the menu bar, the Settings window, and
    /// the app delegate's lifecycle hooks.
    static let shared = AppState()
}
