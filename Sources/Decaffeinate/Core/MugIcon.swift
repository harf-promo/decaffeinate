import AppKit

/// Draws Decaffeinate's menu-bar glyphs as **template** images using the shared
/// `BrandMark` geometry. Template images are tinted automatically by the menu
/// bar, adapting to light/dark. Each state differs by shape at 18px so the
/// four sleep states are distinguishable without colour.
///
/// The "Moon + Zzz" family:
/// - `.free`       — crescent + z (decaffeinated; free to sleep)
/// - `.counting`   — crescent + downward chevron (winding down)
/// - `.blocked`    — crescent + exclamation (something's keeping it awake)
/// - `.caffeinated`— crescent + bolt (intentionally wired)
enum MugIcon {
    static func image(for state: MugState, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(state, size: size)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func draw(_ state: MugState, size s: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // BrandMark paths are authored in y-down convention (matching SwiftUI).
        // lockFocus uses AppKit's y-up convention; flip the CTM so paths land correctly.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)

        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        for element in BrandMark.menuGlyph(for: state, in: rect) {
            ctx.addPath(element.path)
            // Ink colour is irrelevant for template images; the rule matters.
            ctx.fillPath(using: element.evenOdd ? .evenOdd : .winding)
        }

        ctx.restoreGState()
    }
}
