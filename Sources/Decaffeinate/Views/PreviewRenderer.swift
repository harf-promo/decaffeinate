import AppKit
import SwiftUI

/// Renders the UI to PNGs with deterministic sample data for the README — no
/// flaky menu-bar-popover screen capture, no private content. Driven by the
/// hidden `Decaffeinate --render-previews <dir>` command.
@MainActor
enum PreviewRenderer {
    static func renderAll(to directory: String) -> Bool {
        _ = NSApplication.shared  // initialize AppKit for offscreen rendering
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = AppState.preview()

        // ImageRenderer can't draw Menu/ScrollView/TabView, so we render the
        // static ShowcaseView (which reuses the real status card + actions).
        let showcase = ShowcaseView()
            .environmentObject(state)
            .environmentObject(state.settingsStore)
            .environmentObject(state.rulesEngine)
            .fixedSize()
        let ok = render(showcase, to: dir.appendingPathComponent("screenshot-menu.png"))

        // Mug icon set strip (inspection + README).
        let states: [MugState] = [.free, .counting, .blocked, .caffeinated]
        let strip = HStack(spacing: 22) {
            ForEach(0..<states.count, id: \.self) { i in
                Image(nsImage: MugIcon.image(for: states[i], size: 44))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
            }
        }
        .padding(20)
        .background(.background)
        let stripOK = render(strip, to: dir.appendingPathComponent("menubar-icons.png"))

        print("  menu showcase: \(ok ? "ok" : "FAILED")  mug strip: \(stripOK ? "ok" : "FAILED")")
        return ok
    }

    private static func render<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view.padding(0))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
