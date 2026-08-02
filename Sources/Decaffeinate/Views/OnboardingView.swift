import AppKit
import SwiftUI

/// First-run welcome: two short panels — what Decaffeinate does + its safety
/// promise, then an explicit notification choice — ending in either "Enable
/// notifications" or "Not now". (Trimmed from four marketing panels in earlier
/// versions: the old flow made the user sit through everything before any
/// value, and its vague final sentence about notifications masked what was
/// actually an unconditional OS permission request — see `OnboardingPresenter`.)
struct OnboardingView: View {
    /// Called exactly once when onboarding completes, from any exit (the
    /// top-level Skip, or panel 2's "Not now" / "Enable notifications").
    /// `notificationsRequested` is true only for "Enable notifications" — the
    /// one path that still asks for OS permission in-context; every other
    /// exit defers the ask to the moment the firewall first actually needs it
    /// (see `OnboardingPresenter.finish`). `launchAtLoginEnabled` is panel 2's
    /// toggle value, applied only if the user actually reached that panel —
    /// nil from an earlier Skip, so the underlying setting is left untouched.
    let onFinish: (_ notificationsRequested: Bool, _ launchAtLoginEnabled: Bool?) -> Void
    /// Which panel to open on — defaults to the first; the screenshot harness
    /// uses this to also capture the notification-choice panel.
    var initialPage: Int = 0

    @State private var page: Int
    /// Defaults to on: a background utility that isn't offered launch-at-login
    /// up front silently stops working after the next restart. The user can
    /// uncheck it right here before finishing.
    @State private var launchAtLoginEnabled = true

    init(
        onFinish: @escaping (Bool, Bool?) -> Void,
        initialPage: Int = 0
    ) {
        self.onFinish = onFinish
        self.initialPage = initialPage
        _page = State(initialValue: initialPage)
    }

    private let panels = OnboardingPanel.all

    var body: some View {
        VStack(spacing: 0) {
            // Masthead — a quiet brand anchor.
            HStack(spacing: Space.s2) {
                DecaffeinateMark(size: 22)
                Text("Decaffeinate").scaledFont(13, weight: .medium).foregroundStyle(Color.ink1)
                Spacer()
                Text(L10n.localized("Welcome")).eyebrow(.ink4)
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s4)

            Hairline()

            Group {
                if isLastPage {
                    NotificationChoicePanel(
                        panel: panels[page],
                        launchAtLoginEnabled: $launchAtLoginEnabled,
                        onEnableNotifications: { onFinish(true, launchAtLoginEnabled) },
                        onNotNow: { onFinish(false, launchAtLoginEnabled) }
                    )
                } else {
                    OnboardingPanelView(panel: panels[page])
                }
            }
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
                Button(L10n.localized("Skip")) {
                    onFinish(false, isLastPage ? launchAtLoginEnabled : nil)
                }
                .buttonStyle(HarfButtonStyle(variant: .text, size: .small))
                .fixedSize()

                Spacer()

                StepNumerals(count: panels.count, current: page)

                Spacer()

                if !isLastPage {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    } label: {
                        HStack(spacing: Space.s2) {
                            Text(L10n.localized("Next"))
                            Text("→").font(HarfFont.code)
                        }
                    }
                    .buttonStyle(HarfButtonStyle(variant: .primary, size: .regular))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
                }
                // Panel 2 supplies its own two finishing actions ("Enable
                // notifications" / "Not now") — no redundant primary button here.
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s4)
        }
        .frame(width: 480, height: 420)
        .background(Color.paper)
    }

    private var isLastPage: Bool { page == panels.count - 1 }
}

/// 01 · 02 — Harf uses numerals (not dots) as step indicators.
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
                "Running Claude Code, a build, or a long download? These hold your Mac awake until they\u{2019}re done — and sometimes after. Decaffeinate watches what\u{2019}s keeping your Mac up and puts it to sleep the moment it\u{2019}s safe, even when a rogue process disagrees.\n\nAnd it never cuts off what matters — it quietly stands down during:",
            bullets: [
                "Calls, screen sharing and active media",
                "Time Machine backups and macOS updates",
                "Apps you\u{2019}ve explicitly allowed",
            ]
        ),
        OnboardingPanel(
            step: "02 — Stay informed",
            title: "Know what\u{2019}s keeping you up",
            body:
                "Decaffeinate can tell you the moment a new app starts holding your Mac awake — with the real reason, like \u{201c}microphone in use\u{201d} or \u{201c}playing media\u{201d} — so you decide what to allow."
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
                .scaledFont(30, weight: .semibold, relativeTo: .largeTitle)
                .foregroundStyle(Color.ink1)
                .tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
            Text(panel.body)
                .scaledFont(15)
                .foregroundStyle(Color.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !panel.bullets.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(panel.bullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Circle().fill(Color.harfGreen).frame(width: 5, height: 5)
                            Text(bullet).scaledFont(13).foregroundStyle(Color.ink2)
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

/// Panel 2: the explicit notification choice + trust line + (when available)
/// the launch-at-login checkbox — replaces the old vague "turn on
/// notifications" sentence with two real buttons, per the v1.22 audit.
private struct NotificationChoicePanel: View {
    let panel: OnboardingPanel
    @Binding var launchAtLoginEnabled: Bool
    let onEnableNotifications: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(panel.step).eyebrow()
                Text(panel.title)
                    .scaledFont(30, weight: .semibold, relativeTo: .largeTitle)
                    .foregroundStyle(Color.ink1)
                    .tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(panel.body)
                    .scaledFont(15)
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.s3) {
                    Button(action: onEnableNotifications) {
                        Text(L10n.localized("Enable notifications"))
                    }
                    .buttonStyle(HarfButtonStyle(variant: .primary, size: .regular))
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()

                    Button(action: onNotNow) {
                        Text(L10n.localized("Not now"))
                    }
                    .buttonStyle(HarfButtonStyle(variant: .ghost, size: .regular))
                    .fixedSize()
                }
                .padding(.top, Space.s1)

                Text(
                    "No screen recording, no accessibility access \u{2014} everything stays on your Mac."
                )
                .scaledFont(12)
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)

                if LoginItem.isAvailable {
                    Toggle(isOn: $launchAtLoginEnabled) {
                        Text(L10n.localized("Launch Decaffeinate at login"))
                            .scaledFont(13)
                            .foregroundStyle(Color.ink1)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, Space.s2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        let view = OnboardingView(onFinish: { [weak self] notificationsRequested, launchAtLogin in
            self?.finish(
                notificationsRequested: notificationsRequested,
                applyingLaunchAtLogin: launchAtLogin)
        })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Decaffeinate"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // Size the (non-resizable) window from the view's own fitting size so
        // the two can never drift apart — a hardcoded height once clipped the
        // footer 20pt off the bottom of the first thing a new user ever sees.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `notificationsRequested` is true only when the user tapped "Enable
    /// notifications" — that path requests OS permission immediately, in
    /// context. Every other exit (Skip, "Not now") must NOT request it here:
    /// doing so unconditionally, on every exit, was the bug — it fired the OS
    /// prompt cold at the exact moment a user chose to skip. Instead it's
    /// deferred (`declinedNotificationsAtOnboarding`) to the moment the
    /// firewall first actually needs it (see `AppState.updateFirewallQueue`).
    private func finish(notificationsRequested: Bool, applyingLaunchAtLogin launchAtLogin: Bool?) {
        settingsStore?.settings.hasCompletedOnboarding = true
        if notificationsRequested {
            AppState.shared.requestNotificationAuthorization()
            settingsStore?.settings.declinedNotificationsAtOnboarding = false
        } else {
            settingsStore?.settings.declinedNotificationsAtOnboarding = true
        }
        // Only when the user actually reached panel 2 (launchAtLogin != nil) —
        // an early Skip on panel 1 never saw the checkbox, so it must leave
        // `AppSettings.launchAtLogin`'s default untouched for headless/CLI-only
        // launches and any pre-v1.22 users who already made their own choice.
        if let launchAtLogin, LoginItem.isAvailable {
            if LoginItem.setEnabled(launchAtLogin) {
                settingsStore?.settings.launchAtLogin = launchAtLogin
            }
            // If SMAppService registration fails, leave the setting as-is —
            // never claim a login-item state the OS didn't actually adopt.
        }
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Restores the accessory-app activation policy now that the window is gone.
        // Do NOT mark onboarding complete here — only the Skip / "Not now" /
        // "Enable notifications" exits should do that. A plain red-button close
        // means the user just dismissed it temporarily, so it should reappear
        // next launch.
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
