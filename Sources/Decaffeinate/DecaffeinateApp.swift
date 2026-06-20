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
            Image(nsImage: MugIcon.image(for: appState.mug))
                .renderingMode(.template)
                .accessibilityLabel(appState.mug.accessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.rulesEngine)
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
