import AppKit
import SwiftUI

/// First-run welcome: three short panels — what Decaffeinate does, the safety
/// promise, and the one notification permission — ending in "Get started".
struct OnboardingView: View {
    /// Called when the user finishes (or skips) onboarding.
    let onFinish: () -> Void
    /// Called when the user opts into notifications on the final panel.
    let onEnableNotifications: () -> Void

    @State private var page = 0

    private let panels = OnboardingPanel.all

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(panels.enumerated()), id: \.offset) { index, panel in
                    OnboardingPanelView(panel: panel).tag(index)
                }
            }
            .tabViewStyle(.automatic)
            // The page dots are intentionally hidden from VoiceOver (color-only),
            // so carry the progress here instead.
            .accessibilityValue("Page \(page + 1) of \(panels.count)")

            Divider()

            HStack {
                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                PageDots(count: panels.count, current: page)

                Spacer()

                if page < panels.count - 1 {
                    Button("Next") { withAnimation { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get started") {
                        onEnableNotifications()
                        onFinish()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 400)
    }
}

private struct OnboardingPanel: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let body: String
    /// Optional bullet points shown beneath the body.
    var bullets: [String] = []

    static let all: [OnboardingPanel] = [
        OnboardingPanel(
            symbol: "moon.zzz.fill",
            tint: .indigo,
            title: "Your Mac, finally asleep",
            body:
                "Caffeine apps keep Macs awake. Decaffeinate does the opposite: when you step away, it puts your Mac to sleep — even when a rogue app is trying to keep it up."
        ),
        OnboardingPanel(
            symbol: "shield.lefthalf.filled",
            tint: .green,
            title: "Safe by default",
            body: "It never cuts off something that matters. Decaffeinate stands down during:",
            bullets: [
                "Calls, screen sharing and active media",
                "Time Machine backups and macOS updates",
                "Apps you've explicitly allowed",
            ]
        ),
        OnboardingPanel(
            symbol: "bell.badge.fill",
            tint: .orange,
            title: "Know what's keeping you up",
            body:
                "Decaffeinate can tell you the moment a new app starts holding your Mac awake — with the real reason, like “microphone in use” or “playing media” — so you decide what to allow. Turn on notifications to get the heads-up."
        ),
    ]
}

private struct OnboardingPanelView: View {
    let panel: OnboardingPanel

    var body: some View {
        // Scroll so large Dynamic Type sizes can pan rather than clip in the
        // fixed-size onboarding window. (Content is split out so the headless
        // preview renderer — which can't draw a ScrollView — can render it.)
        ScrollView { OnboardingPanelContent(panel: panel) }
    }
}

private struct OnboardingPanelContent: View {
    let panel: OnboardingPanel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: panel.symbol)
                .font(.system(size: 52))
                .foregroundStyle(panel.tint)
                .padding(.top, 8)
                .accessibilityHidden(true)
            Text(panel.title)
                .font(.title2.bold())
            Text(panel.body)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !panel.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(panel.bullets, id: \.self) { bullet in
                        Label(bullet, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single static onboarding panel for headless preview rendering — the live
/// `TabView` can't be drawn by `ImageRenderer`, so the README shot uses this.
struct OnboardingPreview: View {
    var body: some View {
        // Render the content directly (not the live ScrollView wrapper, which
        // ImageRenderer can't draw).
        OnboardingPanelContent(panel: OnboardingPanel.all[1])
            .frame(width: 480, height: 340)
            .background(.background)
    }
}

/// Owns the first-run window for an accessory (menu-bar) app: flips the
/// activation policy to `.regular` while it's up so the window can take focus,
/// and back to `.accessory` when it closes.
@MainActor
final class OnboardingPresenter: NSObject, NSWindowDelegate {
    static let shared = OnboardingPresenter()

    private var window: NSWindow?
    private weak var settingsStore: SettingsStore?

    /// Show the welcome window only if the user hasn't completed it before.
    func showIfNeeded(settingsStore: SettingsStore) {
        guard !settingsStore.settings.hasCompletedOnboarding else { return }
        present(settingsStore: settingsStore)
    }

    /// Show the welcome window unconditionally (e.g. from a "Show welcome" action).
    func present(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(
            onFinish: { [weak self] in self?.finish() },
            onEnableNotifications: { AppState.shared.requestNotificationAuthorization() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Decaffeinate"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 480, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        settingsStore?.settings.hasCompletedOnboarding = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Treat any dismissal as "seen it" so first-run only nags once.
        settingsStore?.settings.hasCompletedOnboarding = true
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
