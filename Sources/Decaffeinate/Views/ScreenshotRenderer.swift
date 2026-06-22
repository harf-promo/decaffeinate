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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var ok = true
        for (suffix, appearance): (String, NSAppearance.Name) in [
            ("light", .aqua), ("dark", .darkAqua),
        ] {
            let state = representativeState()
            let updater = UpdaterController()
            // Warm the icon cache so the menu shot shows real app icons.
            for assertion in state.assertions { _ = AppIconProvider.shared.icon(for: assertion) }

            let theme = Theme.nightcap
            let menu = RedesignMenuView()
                .environment(\.theme, theme)
                .environmentObject(state)
                .environmentObject(state.settingsStore)
                .environmentObject(state.rulesEngine)
                .environmentObject(updater)
            ok =
                capture(
                    menu,
                    size: NSSize(width: theme.popoverWidth, height: RedesignMenuView.menuHeight),
                    appearance: appearance, to: dir.appendingPathComponent("menu-\(suffix).png"))
                && ok

            // The expanded provenance detail for the agentic caffeinate row.
            if let caffeinate = state.assertions.first(where: { $0.processName == "caffeinate" }) {
                let detail = AssertionDetailView(assertion: caffeinate)
                    .environment(\.theme, theme)
                    .environmentObject(state)
                    .frame(width: 360)
                ok =
                    capture(
                        detail, size: NSSize(width: 360, height: 360), appearance: appearance,
                        to: dir.appendingPathComponent("detail-\(suffix).png")) && ok
            }

            let onboarding = OnboardingView(onFinish: {}, onEnableNotifications: {})
            ok =
                capture(
                    onboarding, size: NSSize(width: 480, height: 420), appearance: appearance,
                    to: dir.appendingPathComponent("onboarding-\(suffix).png")) && ok

            let settings = SettingsView()
                .environment(\.theme, theme)
                .environmentObject(state)
                .environmentObject(state.settingsStore)
                .environmentObject(state.rulesEngine)
                .environmentObject(state.history)
                .environmentObject(state.restHistory)
                .environmentObject(updater)
            ok =
                capture(
                    settings, size: NSSize(width: 660, height: 480), appearance: appearance,
                    to: dir.appendingPathComponent("settings-\(suffix).png")) && ok

            // The new Rest & Restart pillar pane, opened directly.
            let freshness = SettingsView(initialPane: .freshness)
                .environment(\.theme, theme)
                .environmentObject(state)
                .environmentObject(state.settingsStore)
                .environmentObject(state.rulesEngine)
                .environmentObject(state.history)
                .environmentObject(state.restHistory)
                .environmentObject(updater)
            ok =
                capture(
                    freshness, size: NSSize(width: 660, height: 480), appearance: appearance,
                    to: dir.appendingPathComponent("rest-restart-\(suffix).png")) && ok
        }
        renderMugStrip(to: dir.appendingPathComponent("mug-states.png"))
        renderMenubarStrip(to: dir.appendingPathComponent("menubar-icons.png"))
        print("Screenshots written to \(dir.path)")
        return ok
    }

    /// A clean single-row strip of the four states for the README, at a friendly
    /// size on white, evenly spaced.
    private static func renderMenubarStrip(to url: URL) {
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
        if let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            try? png.write(to: url)
        }
    }

    /// The 4 menu-bar states at real sizes, black-on-white, so their shape
    /// distinctness can actually be judged (the menu bar renders them at ~18px).
    private static func renderMugStrip(to url: URL) {
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
        if let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            try? png.write(to: url)
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
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
