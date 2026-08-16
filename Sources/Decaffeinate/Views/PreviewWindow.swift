import AppKit
import SwiftUI

/// Fixture UI for visual QA. Sleep Now / display-off / keep-awake are no-ops
/// (`PreviewSleeper` / `PreviewCaffeine`). Does not start the live tick loop.
@MainActor
enum PreviewApp {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = PreviewDelegate()
        app.delegate = delegate
        delegate.show()
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var menuWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var updater: UpdaterController?
    private var state: AppState?

    func show() {
        let state = AppState.preview()
        let updater = UpdaterController()
        self.state = state
        self.updater = updater

        let theme = Theme.nightcap
        let menu = RedesignMenuView()
            .environment(\.theme, theme)
            .environmentObject(state)
            .environmentObject(state.settingsStore)
            .environmentObject(state.rulesEngine)
            .environmentObject(updater)
        menuWindow = makeWindow(
            menu,
            size: NSSize(width: theme.popoverWidth, height: RedesignMenuView.menuHeight),
            title: "Decaffeinate preview — sleep is disabled")
        menuWindow?.setFrameOrigin(NSPoint(x: 80, y: 200))
        menuWindow?.makeKeyAndOrderFront(nil)

        let settings = SettingsView()
            .environment(\.theme, theme)
            .environmentObject(state)
            .environmentObject(state.settingsStore)
            .environmentObject(state.rulesEngine)
            .environmentObject(state.history)
            .environmentObject(state.restHistory)
            .environmentObject(state.awakeTime)
            .environmentObject(updater)
        settingsWindow = makeWindow(
            settings,
            size: NSSize(width: 700, height: 520),
            title: "Settings preview — sleep is disabled")
        settingsWindow?.setFrameOrigin(NSPoint(x: 480, y: 160))
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeWindow<V: View>(_ view: V, size: NSSize, title: String) -> NSWindow {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        return window
    }
}
