import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// User-configurable global hotkey that forces the Mac to sleep from anywhere.
    /// No default combo — the user opts in via Settings → General.
    static let sleepNow = Self("sleepNow")
    /// User-configurable global hotkey that toggles keep-awake (`caffeinateEnabled`)
    /// on/off from anywhere. Also no default combo: a keep-awake toggle is far
    /// less destructive than force-sleep, but still shouldn't ship with a
    /// surprise default combo the user never chose.
    static let toggleKeepAwake = Self("toggleKeepAwake")
}

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
            RedesignMenuView()
                .environment(\.theme, .nightcap)
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
                if let holderCount = appState.menuBarHolderCountText {
                    Text(holderCount).monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(appState.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdatesUserInitiated() }
                    .disabled(!updater.isAvailable)
            }
        }

        Settings {
            SettingsView()
                .environment(\.theme, .nightcap)
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.rulesEngine)
                .environmentObject(appState.history)
                .environmentObject(appState.restHistory)
                .environmentObject(appState.awakeTime)
                .environmentObject(updater)
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
            // Hand the real Notifier's "Always Allow" / "Sleep Anyway"
            // notification actions back to AppState's policy engine.
            AppState.shared.wireNotificationActions()
            // Watches AppState.pendingIdleSleepWarning and shows/hides the
            // pre-sleep countdown HUD — the idle force-sleep warning, never a
            // user-initiated Sleep Now.
            SleepWarningPresenter.shared.start(appState: AppState.shared)
            // Global "Sleep Now" hotkey (opt-in; recorded in Settings → General).
            // KeyboardShortcuts invokes the handler on the main thread. Same
            // interactive path as the menu button — the call-in-progress
            // confirmation guard in AppState.sleepNow() applies here too.
            KeyboardShortcuts.onKeyUp(for: .sleepNow) {
                MainActor.assumeIsolated { AppState.shared.sleepNow() }
            }
            // Global "toggle keep-awake" hotkey (opt-in; recorded in Settings →
            // General). Flips the exact same `caffeinateEnabled` flag the menu's
            // "Stop keeping awake" row and "Keep awake indefinitely" toggle mutate
            // directly (see `RDActiveControls`/`RDActionBar` in MenuRedesign.swift)
            // — no separate AppState method to keep in sync with the menu's.
            KeyboardShortcuts.onKeyUp(for: .toggleKeepAwake) {
                MainActor.assumeIsolated {
                    AppState.shared.settingsStore.settings.caffeinateEnabled.toggle()
                }
            }
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

    /// Handle the `decaffeinate://…` URL scheme (Shortcuts "Open URLs", scripts).
    /// Delivered on the main thread for schemes registered in Info.plist.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                switch AutomationURL.parse(url) {
                case .sleepNow:
                    // Non-interactive automation call (Shortcuts, a script) —
                    // no one is present to answer a "you appear to be on a
                    // call" confirmation, so this skips that guard and stays
                    // immediate, like the CLI / App Intents / MCP sleep_now.
                    AppState.shared.sleepNow(requireCallConfirmation: false)
                case .keepAwake(let minutes): AppState.shared.stayAwake(forMinutes: minutes)
                case .stopAwake: AppState.shared.clearQuietWindow()
                case .none: break
                }
            }
        }
    }
}

extension AppState {
    /// Single shared instance wired into the menu bar, the Settings window, and
    /// the app delegate's lifecycle hooks.
    static let shared = AppState()
}
