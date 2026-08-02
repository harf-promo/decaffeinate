import AppKit
import SwiftUI

/// The "Use with lid closed…" readiness panel — Decaffeinate's zero-root
/// Clamshell Assistant (v1.24 Phase A). It DETECTS and EXPLAINS Apple's own
/// built-in clamshell mode (external display + AC power + external
/// keyboard/mouse); it never enables anything the OS doesn't already
/// support, and it never touches `pmset disablesleep` or anything root-only
/// — see `docs/LID-CLOSED.md`. "Arm clamshell session" and the screens-off
/// fallback both just flip the app's EXISTING keep-awake mechanism (the same
/// one the menu's "Keep awake indefinitely" toggle drives); the existing
/// `SafetyRails` (battery floor, thermal) already govern that hold exactly
/// as always — no new rail logic lives here.
///
/// Split into a live wrapper (this type — observes `AppState`, owns the
/// refresh loop) and a plain value body (`ClamshellAssistantBody`) so the
/// checklist itself is trivial to preview/screenshot, mirroring
/// `SleepWarningHUD`'s split.
struct ClamshellAssistantView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    /// How often the panel re-samples lid/display/input while visible. The
    /// pmset-backed foreign-`SleepDisabled` read stays throttled to its own
    /// ~30 s cadence inside `AppState.refreshClamshellReadiness()` regardless
    /// of how often this fires.
    private static let refreshInterval: Duration = .seconds(2)

    var body: some View {
        ClamshellAssistantBody(
            readiness: appState.clamshellReadiness,
            foreignSleepDisabled: appState.foreignSleepDisabled,
            onArmClamshellSession: { settingsStore.settings.caffeinateEnabled = true },
            onKeepScreensOff: {
                settingsStore.settings.caffeinateEnabled = true
                appState.displayOff()
            }
        )
        .task {
            await appState.refreshClamshellReadiness()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                if Task.isCancelled { return }
                await appState.refreshClamshellReadiness()
            }
        }
    }
}

/// The checklist + actions, as a plain value view — no `AppState` reference,
/// so it's trivial to preview/screenshot in both the "ready" and "missing"
/// states (see `ScreenshotRenderer`).
struct ClamshellAssistantBody: View {
    @Environment(\.theme) private var theme
    let readiness: ClamshellReadiness
    let foreignSleepDisabled: Bool
    let onArmClamshellSession: () -> Void
    let onKeepScreensOff: () -> Void

    private var unmet: Set<ClamshellRequirement> {
        if case .missing(let u) = readiness { return u }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            switch readiness {
            case .notApplicable:
                notApplicableRow
            case .ready, .missing:
                checklist
                if foreignSleepDisabled { foreignSleepDisabledNote }
                primaryAction
                Divider()
                screensOffFallback
            }
        }
        .padding(Space.s5)
        .frame(width: 360)
        .background(theme.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.localized("Use with lid closed"), systemImage: "laptopcomputer")
                .scaledFont(16, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(theme.ink1)
            Text(
                L10n.localized(
                    "Decaffeinate detects Apple\u{2019}s own clamshell mode \u{2014} it never forces the lid closed to work on its own."
                )
            )
            .scaledFont(12, relativeTo: .caption)
            .foregroundStyle(theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notApplicableRow: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "desktopcomputer").foregroundStyle(theme.ink3)
            Text(
                L10n.localized(
                    "This Mac doesn\u{2019}t have a lid \u{2014} clamshell mode doesn\u{2019}t apply.")
            )
            .scaledFont(13, relativeTo: .callout)
            .foregroundStyle(theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            checklistRow(.power, readyLabel: L10n.localized("On power"))
            checklistRow(
                .externalDisplay, readyLabel: L10n.localized("External display connected"))
            checklistRow(.externalInput, readyLabel: L10n.localized("Keyboard and mouse connected"))
        }
    }

    private func checklistRow(_ requirement: ClamshellRequirement, readyLabel: String)
        -> some View
    {
        let done = !unmet.contains(requirement)
        let requirementLabel = L10n.localized(requirement.label)
        return HStack(spacing: Space.s2) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? theme.teal : theme.ink4)
                .accessibilityHidden(true)
            Text(done ? readyLabel : requirementLabel)
                .scaledFont(13, relativeTo: .callout)
                .foregroundStyle(done ? theme.ink1 : theme.ink3)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            done
                ? L10n.localized("%@, ready", readyLabel)
                : L10n.localized("%@, not yet", requirementLabel))
    }

    @ViewBuilder private var primaryAction: some View {
        switch readiness {
        case .ready:
            VStack(alignment: .leading, spacing: Space.s2) {
                Button(action: onArmClamshellSession) {
                    Label(L10n.localized("Arm clamshell session"), systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RDPrimaryButton())
                .help(
                    L10n.localized("Turn on keep-awake so the Mac stays up on the external display.")
                )
                Text(
                    L10n.localized(
                        "Close the lid \u{2014} your Mac keeps working on the external display.")
                )
                .scaledFont(12, relativeTo: .caption)
                .foregroundStyle(theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }
        case .missing:
            Text(L10n.localized("Once these are ready, you can arm a clamshell session."))
                .scaledFont(12, relativeTo: .caption)
                .foregroundStyle(theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        case .notApplicable:
            EmptyView()
        }
    }

    private var screensOffFallback: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(L10n.localized("No external display?"))
                .scaledFont(12, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(theme.ink2)
            Button(action: onKeepScreensOff) {
                Label(
                    L10n.localized("Keep working with the screens off"), systemImage: "moon.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(RDSecondaryButton())
            .help(
                L10n.localized(
                    "Keep-awake + turn the display off now. The lid must stay open for this."))
            Text(
                L10n.localized(
                    "The lid must stay open for this \u{2014} screens off isn\u{2019}t the same as lid closed."
                )
            )
            .scaledFont(11, relativeTo: .caption2)
            .foregroundStyle(theme.ink4)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var foreignSleepDisabledNote: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "info.circle").foregroundStyle(Color.warning)
                .accessibilityHidden(true)
            Text(
                L10n.localized(
                    "Sleep is disabled system-wide by something other than Decaffeinate.")
            )
            .scaledFont(11, relativeTo: .caption2)
            .foregroundStyle(theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Owns the Clamshell Assistant's small utility window — mirrors
/// `OnboardingPresenter`'s NSWindow-hosting pattern (already proven to work
/// from this app's `.accessory` activation policy), rather than a SwiftUI
/// `Window` scene: `SettingsWindowOpener`'s comments document that SwiftUI's
/// own scene-opening APIs (`openSettings()`) can silently no-op from an
/// accessory app's `MenuBarExtra` on macOS 26, so this sticks to the
/// AppKit-window path already known to work reliably here.
@MainActor
final class ClamshellAssistantPresenter: NSObject, NSWindowDelegate {
    static let shared = ClamshellAssistantPresenter()

    private var window: NSWindow?

    func present(appState: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = ClamshellAssistantView()
            .environment(\.theme, .nightcap)
            .environmentObject(appState)
            .environmentObject(appState.settingsStore)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.localized("Use With Lid Closed")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
