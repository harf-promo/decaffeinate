import AppKit
import SwiftUI

/// Captures **real** screenshots of the live SwiftUI surfaces — menu, onboarding,
/// Settings — in light and dark, by hosting each in an offscreen `NSHostingView`
/// and `cacheDisplay`-ing it. Unlike `ImageRenderer` this draws `ScrollView`,
/// `TabView` and `Menu` correctly, so we can actually *see* the product we ship.
/// Driven by the hidden `Decaffeinate --screenshots <dir>` command.
@MainActor
enum ScreenshotRenderer {
    static func renderAll(to directory: String) -> Bool {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(
                Data("Could not create \(dir.path): \(error.localizedDescription)\n".utf8))
            return false
        }

        var ok = true
        for (suffix, appearance): (String, NSAppearance.Name) in [
            ("light", .aqua), ("dark", .darkAqua),
        ] {
            let state = representativeState()
            let updater = UpdaterController()
            // Warm the icon cache so the menu shot shows real app icons.
            for assertion in state.assertions { _ = AppIconProvider.shared.icon(for: assertion) }
            let theme = Theme.nightcap

            func shoot<V: View>(_ view: V, _ size: CGSize, _ name: String) {
                ok =
                    capture(
                        view, size: NSSize(width: size.width, height: size.height),
                        appearance: appearance,
                        to: dir.appendingPathComponent("\(name)-\(suffix).png")) && ok
            }

            shoot(
                menuView(state: state, updater: updater, theme: theme),
                CGSize(width: theme.popoverWidth, height: RedesignMenuView.menuHeight), "menu")

            // The expanded provenance detail for the agentic caffeinate row.
            if let caffeinate = state.assertions.first(where: { $0.processName == "caffeinate" }) {
                let detail = AssertionDetailView(assertion: caffeinate)
                    .environment(\.theme, theme)
                    .environmentObject(state)
                    .frame(width: WindowMetrics.assertionDetailCapture.width)
                shoot(detail, WindowMetrics.assertionDetailCapture, "detail")
            }

            shoot(OnboardingView(onFinish: { _, _ in }), WindowMetrics.onboarding, "onboarding")
            // Panel 2 — the explicit notification-choice + launch-at-login panel.
            shoot(
                OnboardingView(onFinish: { _, _ in }, initialPage: 1), WindowMetrics.onboarding,
                "onboarding-notifications")

            // The pre-sleep warning HUD (v1.22) — a fixed sample countdown.
            shoot(
                SleepWarningHUD(secondsRemaining: 14, onStayAwake: {}), WindowMetrics.hudCapture,
                "sleep-warning-hud")

            // Every Settings pane. `SettingsPane.allCases` drives this so a new
            // pane cannot be added without also being captured — the Schedule
            // pane went un-photographed for four releases that way.
            for pane in SettingsPane.allCases {
                let view = settingsView(
                    pane: pane, state: state, updater: updater, theme: theme)
                shoot(view, WindowMetrics.settings, captureName(for: pane))
            }
        }
        // The Clamshell Assistant panel (v1.24) — ready and missing-requirements
        // states, driven directly (a plain value view, like SleepWarningHUD),
        // no live AppState/IOKit involved.
        for (name, appearance): (String, NSAppearance.Name) in [
            ("light", .aqua), ("dark", .darkAqua),
        ] {
            let ready = ClamshellAssistantBody(
                readiness: .ready, foreignSleepDisabled: false,
                onArmClamshellSession: {}, onKeepScreensOff: {}
            ).environment(\.theme, Theme.nightcap)
            ok =
                capture(
                    ready,
                    size: NSSize(
                        width: WindowMetrics.clamshellReadyCapture.width,
                        height: WindowMetrics.clamshellReadyCapture.height),
                    appearance: appearance,
                    to: dir.appendingPathComponent("clamshell-ready-\(name).png")) && ok

            let missing = ClamshellAssistantBody(
                readiness: .missing(unmet: [.power, .externalDisplay]), foreignSleepDisabled: true,
                onArmClamshellSession: {}, onKeepScreensOff: {}
            ).environment(\.theme, Theme.nightcap)
            ok =
                capture(
                    missing,
                    size: NSSize(
                        width: WindowMetrics.clamshellMissingCapture.width,
                        height: WindowMetrics.clamshellMissingCapture.height),
                    appearance: appearance,
                    to: dir.appendingPathComponent("clamshell-missing-\(name).png")) && ok
        }
        ok = renderMugStrip(to: dir.appendingPathComponent("mug-states.png")) && ok
        ok = renderMenubarStrip(to: dir.appendingPathComponent("menubar-icons.png")) && ok
        if ok {
            print("Screenshots written to \(dir.path)")
        } else {
            FileHandle.standardError.write(
                Data("Some screenshots failed to render or write — see above.\n".utf8))
        }
        return ok
    }

    /// The menu popover with its full environment — one declaration, so a new
    /// dependency cannot be wired into the app and forgotten here.
    private static func menuView(
        state: AppState, updater: UpdaterController, theme: Theme
    ) -> some View {
        RedesignMenuView()
            .environment(\.theme, theme)
            .environmentObject(state)
            .environmentObject(state.settingsStore)
            .environmentObject(state.rulesEngine)
            .environmentObject(updater)
    }

    /// One Settings pane with its full environment. This chain was pasted six
    /// times before; the seventh pane is why it is a function now.
    private static func settingsView(
        pane: SettingsPane, state: AppState, updater: UpdaterController, theme: Theme
    ) -> some View {
        SettingsView(initialPane: pane)
            .environment(\.theme, theme)
            .environmentObject(state)
            .environmentObject(state.settingsStore)
            .environmentObject(state.rulesEngine)
            .environmentObject(state.history)
            .environmentObject(state.restHistory)
            .environmentObject(state.awakeTime)
            .environmentObject(updater)
    }

    /// The README and the docs already link these filenames, so the two panes
    /// that shipped under a different name keep it.
    private static func captureName(for pane: SettingsPane) -> String {
        switch pane {
        case .general: return "settings"
        case .freshness: return "rest-restart"
        default: return "settings-\(pane.rawValue)"
        }
    }

    /// A clean single-row strip of the four states for the README, at a friendly
    /// size on white, evenly spaced.
    private static func renderMenubarStrip(to url: URL) -> Bool {
        let states: [MugState] = [.free, .counting, .blocked, .caffeinated]
        let glyph: CGFloat = 44
        let cell: CGFloat = 96
        let pad: CGFloat = 18
        let size = NSSize(width: cell * CGFloat(states.count), height: glyph + pad * 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (col, state) in states.enumerated() {
            let cx = CGFloat(col) * cell + cell / 2
            let cy = size.height / 2
            MugIcon.image(for: state, size: glyph)
                .draw(in: NSRect(x: cx - glyph / 2, y: cy - glyph / 2, width: glyph, height: glyph))
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return false }
        return write(png, to: url)
    }

    /// The 4 menu-bar states at real sizes, black-on-white, so their shape
    /// distinctness can actually be judged (the menu bar renders them at ~18px).
    private static func renderMugStrip(to url: URL) -> Bool {
        let states: [MugState] = [.free, .counting, .blocked, .caffeinated]
        let sizes: [CGFloat] = [18, 36, 72]
        let cellW: CGFloat = 120
        let rowH: CGFloat = 96
        let size = NSSize(width: cellW * CGFloat(states.count), height: rowH * CGFloat(sizes.count))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (col, state) in states.enumerated() {
            for (rowIndex, glyph) in sizes.enumerated() {
                let cx = CGFloat(col) * cellW + cellW / 2
                let cy = size.height - (CGFloat(rowIndex) * rowH + rowH / 2)
                let mug = MugIcon.image(for: state, size: glyph)
                mug.draw(
                    in: NSRect(x: cx - glyph / 2, y: cy - glyph / 2, width: glyph, height: glyph))
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return false }
        return write(png, to: url)
    }

    /// Writes one PNG, naming the failure instead of discarding it — the whole
    /// point of a screenshot gate is that it can go red.
    private static func write(_ png: Data, to url: URL) -> Bool {
        do {
            try png.write(to: url)
            return true
        } catch {
            let name = url.lastPathComponent
            let message = "Could not write \(name): \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return false
        }
    }

    /// Preview state with a realistic mix: a couple of decided apps + one still
    /// needing a decision, plus a sleep in history — so every menu surface shows.
    private static func representativeState() -> AppState {
        let state = AppState.preview()
        let blockers = state.assertions
        if blockers.count >= 4 {
            state.setPolicy(.allow, for: blockers[0])  // Zoom — allowed
            state.setPolicy(.allow, for: blockers[2])  // Chrome — allowed
            state.setPolicy(.ignore, for: blockers[3])  // caffeinate — ignored
            // blockers[1] (Safari) stays pending → shows the approval card.
        }
        return state
    }

    private static func capture<V: View>(
        _ view: V, size: NSSize, appearance name: NSAppearance.Name, to url: URL
    ) -> Bool {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: name)
        window.contentView = hosting
        window.displayIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI lay out + async .task work (icons) settle before capturing.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        window.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return write(data, to: url)
    }
}
