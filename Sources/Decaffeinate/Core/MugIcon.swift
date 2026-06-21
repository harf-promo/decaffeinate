import AppKit

/// Draws Decaffeinate's menu-bar glyphs at runtime as **template** images (so the
/// menu bar tints them automatically and they adapt to light/dark). Runtime
/// drawing avoids shipping/locating resource bundles in the hand-assembled `.app`.
///
/// The four states map to a moon ↔ sun metaphor (sleep ↔ awake), matching the
/// crescent app icon:
/// - `.free` — a crescent moon (free to sleep; the resting state)
/// - `.counting` — crescent + a star dot (settling into night; winding down)
/// - `.blocked` — a sun (something's keeping it awake against your wishes)
/// - `.caffeinated` — a bolt (intentionally awake)
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
        NSColor.black.setFill()
        NSColor.black.setStroke()

        switch state {
        case .free:
            crescent(cx: s * 0.50, cy: s * 0.50, r: s * 0.36).fill()
        case .counting:
            crescent(cx: s * 0.44, cy: s * 0.46, r: s * 0.34).fill()
            dot(cx: s * 0.74, cy: s * 0.74, r: s * 0.075).fill()
        case .blocked:
            sun(cx: s * 0.50, cy: s * 0.50, size: s)
        case .caffeinated:
            bolt(cx: s * 0.50, cy: s * 0.50, size: s)
        }
    }

    /// A clean crescent: the outer disc minus an internally-tangent smaller disc
    /// (even-odd), so the horns meet to a point — no opaque background needed.
    private static func crescent(cx: CGFloat, cy: CGFloat, r: CGFloat) -> NSBezierPath {
        let r2 = r * 0.76
        let d = r - r2  // internal tangency → a closed crescent, not a ring
        let path = NSBezierPath()
        path.appendOval(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        let ox = cx + d * 0.78  // offset up-and-right (~40°) so it opens toward the star
        let oy = cy + d * 0.62
        path.appendOval(in: CGRect(x: ox - r2, y: oy - r2, width: r2 * 2, height: r2 * 2))
        path.windingRule = .evenOdd
        return path
    }

    private static func dot(cx: CGFloat, cy: CGFloat, r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    /// A small filled disc with eight short rays.
    private static func sun(cx: CGFloat, cy: CGFloat, size s: CGFloat) {
        let core = s * 0.18
        dot(cx: cx, cy: cy, r: core).fill()
        let inner = core + s * 0.06
        let outer = core + s * 0.16
        let rays = NSBezierPath()
        rays.lineWidth = s * 0.075
        rays.lineCapStyle = .round
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            rays.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
            rays.line(to: CGPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer))
        }
        rays.stroke()
    }

    /// A filled lightning bolt, centred.
    private static func bolt(cx: CGFloat, cy: CGFloat, size s: CGFloat) {
        let b = NSBezierPath()
        b.move(to: CGPoint(x: cx + s * 0.07, y: cy + s * 0.34))
        b.line(to: CGPoint(x: cx - s * 0.16, y: cy - s * 0.02))
        b.line(to: CGPoint(x: cx - s * 0.01, y: cy - s * 0.02))
        b.line(to: CGPoint(x: cx - s * 0.07, y: cy - s * 0.34))
        b.line(to: CGPoint(x: cx + s * 0.16, y: cy + s * 0.04))
        b.line(to: CGPoint(x: cx + s * 0.01, y: cy + s * 0.04))
        b.close()
        b.fill()
    }
}
