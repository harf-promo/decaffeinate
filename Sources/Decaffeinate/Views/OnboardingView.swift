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
            // Masthead — a quiet brand anchor.
            HStack(spacing: Space.s2) {
                DecaffeinateMark(size: 20)
                Text("Decaffeinate").font(HarfFont.bodyMedium).foregroundStyle(Color.ink1)
                Spacer()
                Text("Welcome").eyebrow(.ink4)
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s4)

            Hairline()

            OnboardingPanelView(panel: panels[page])
                .id(page)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .accessibilityValue("Step \(page + 1) of \(panels.count)")

            Hairline()

            HStack(spacing: Space.s3) {
                Button("Skip") { onFinish() }
                    .buttonStyle(HarfButtonStyle(variant: .text, size: .small))
                    .fixedSize()

                Spacer()

                StepNumerals(count: panels.count, current: page)

                Spacer()

                if page < panels.count - 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    } label: {
                        HStack(spacing: Space.s2) {
                            Text("Next")
                            Text("→").font(HarfFont.code)
                        }
                    }
                    .buttonStyle(HarfButtonStyle(variant: .primary, size: .regular))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
                } else {
                    Button {
                        onEnableNotifications()
                        onFinish()
                    } label: {
                        HStack(spacing: Space.s2) {
                            Text("Get started")
                            Text("→").font(HarfFont.code)
                        }
                    }
                    .buttonStyle(HarfButtonStyle(variant: .primary, size: .regular))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
                }
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s4)
        }
        .frame(width: 480, height: 420)
        .background(Color.paper)
    }
}

/// 01 · 02 · 03 — Harf uses numerals (not dots) as step indicators.
private struct StepNumerals: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<count, id: \.self) { i in
                Text(String(format: "%02d", i + 1))
                    .font(HarfFont.codeSmall)
                    .foregroundStyle(i == current ? Color.ink1 : Color.ink4)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingPanel: Identifiable {
    let id = UUID()
    let step: String
    let title: String
    let body: String
    /// Optional bullet points shown beneath the body.
    var bullets: [String] = []

    static let all: [OnboardingPanel] = [
        OnboardingPanel(
            step: "01 — What it does",
            title: "Your Mac, finally asleep",
            body:
                "Running Claude Code, a build, or a long download? These hold your Mac awake until they\u{2019}re done — and sometimes after. Decaffeinate watches what\u{2019}s keeping your Mac up and puts it to sleep the moment it\u{2019}s safe, even when a rogue process disagrees."
        ),
        OnboardingPanel(
            step: "02 — Safe by default",
            title: "It never cuts off what matters",
            body: "Decaffeinate quietly stands down during:",
            bullets: [
                "Calls, screen sharing and active media",
                "Time Machine backups and macOS updates",
                "Apps you've explicitly allowed",
            ]
        ),
        OnboardingPanel(
            step: "03 — Stay informed",
            title: "Know what's keeping you up",
            body:
                "Decaffeinate tells you the moment a new app starts holding your Mac awake — with the real reason, like “microphone in use” or “playing media” — so you decide what to allow. Turn on notifications to get the heads-up."
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
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(panel.step).eyebrow()
            Text(panel.title)
                .font(HarfFont.display)
                .foregroundStyle(Color.ink1)
                .tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
            Text(panel.body)
                .font(HarfFont.lede)
                .foregroundStyle(Color.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !panel.bullets.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(panel.bullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Circle().fill(Color.harfGreen).frame(width: 5, height: 5)
                            Text(bullet).font(HarfFont.body).foregroundStyle(Color.ink2)
                        }
                    }
                }
                .padding(.top, Space.s1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Restores the accessory-app activation policy now that the window is gone.
        // Do NOT mark onboarding complete here — only the Skip and "Get started"
        // buttons should do that. A plain red-button close means the user just
        // dismissed it temporarily, so it should reappear next launch.
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
