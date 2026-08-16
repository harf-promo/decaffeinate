import AppKit
import SwiftUI

/// The on-screen warning shown before a *routine idle* force-sleep actually
/// fires — never before a user-initiated Sleep Now (that stays immediate) or a
/// safety-rail sleep (battery floor / thermal — unconditional backstops). A
/// forced sleep should never be a silent surprise: this gives the user a few
/// seconds to notice it coming and back out with "Stay awake".
///
/// A plain value view — it takes the countdown and callback directly rather
/// than observing `AppState` itself, so it's trivial to preview/screenshot.
/// `SleepWarningPresenter` owns the floating panel this renders inside and
/// recomputes `secondsRemaining` once a second from `AppState.pendingIdleSleepWarning`.
struct SleepWarningHUD: View {
    let secondsRemaining: Int
    let onStayAwake: () -> Void

    private var clamped: Int { max(0, secondsRemaining) }

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.harfGreen)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.localized("Sleeping in %ds", clamped))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink1)
                Text(
                    L10n.localized(
                        "You\u{2019}ve been idle a while \u{2014} Decaffeinate is stepping in.")
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            Button(L10n.localized("Stay awake"), action: onStayAwake)
                .buttonStyle(HarfButtonStyle(variant: .accent, size: .small))
                .fixedSize()
                .keyboardShortcut(.defaultAction)
        }
        .padding(Space.s4)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: Radius.soft * 2).fill(Color.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.soft * 2).stroke(Color.rule, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.localized("Sleeping in %d seconds", clamped))
        .accessibilityAction(named: Text(L10n.localized("Stay awake")), onStayAwake)
    }
}

/// Owns the floating pre-sleep warning panel: shows/hides itself as
/// `AppState.pendingIdleSleepWarning` changes, and refreshes the countdown
/// once a second while visible. A small, non-activating, always-on-top panel
/// so it interrupts nothing else the user is doing — it never steals focus or
/// flips the app out of its menu-bar-accessory activation policy.
@MainActor
final class SleepWarningPresenter {
    static let shared = SleepWarningPresenter()

    private var panel: NSPanel?
    private var timer: Timer?
    private weak var appState: AppState?

    /// Start watching `AppState.pendingIdleSleepWarning`. Called once from the
    /// app delegate at launch. Polls at the same 1 Hz cadence as
    /// `AppState.tick()` — a dedicated timer rather than an `objectWillChange`
    /// subscription, since that publisher fires *before* the tick's new values
    /// land.
    func start(appState: AppState) {
        self.appState = appState
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    private func refresh() {
        guard let appState, let warning = appState.pendingIdleSleepWarning else {
            hidePanel()
            return
        }
        showPanel(for: warning, appState: appState)
    }

    private func showPanel(for warning: PendingSleepWarning, appState: AppState) {
        let remaining = Int(warning.fireAt.timeIntervalSinceNow.rounded(.up))
        let view = SleepWarningHUD(secondsRemaining: remaining) { [weak appState] in
            appState?.cancelPendingIdleSleep()
        }
        if let panel, let hosting = panel.contentView as? NSHostingView<SleepWarningHUD> {
            hosting.rootView = view
            panel.orderFrontRegardless()
            return
        }
        let hosting = NSHostingView(rootView: view)
        let newPanel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false  // the HUD draws its own shadow
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.contentView = hosting
        newPanel.setContentSize(hosting.fittingSize)
        position(newPanel)
        newPanel.orderFrontRegardless()
        panel = newPanel
    }

    /// Top-right of the main screen — visible without covering the content
    /// the user is actually looking at.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20))
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }
}
