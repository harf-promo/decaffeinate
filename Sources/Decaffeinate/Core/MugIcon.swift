import AppKit

/// Draws Decaffeinate's custom menu-bar mug glyphs at runtime as **template**
/// images (so the menu bar tints them automatically and they adapt to
/// light/dark). Runtime drawing avoids shipping/locating resource bundles in the
/// hand-assembled `.app`.
///
/// The four states map to the mug metaphor:
/// - `.free` — empty mug (decaffeinated; free to sleep)
/// - `.counting` — half-full mug (winding down)
/// - `.blocked` — full, steaming mug (something's keeping it awake)
/// - `.caffeinated` — mug with a bolt (intentionally awake)
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
        ctx.setLineWidth(s * 0.06)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Cup body: a slightly tapered rounded vessel.
        let cup = CGRect(x: s * 0.20, y: s * 0.26, width: s * 0.46, height: s * 0.46)
        let body = NSBezierPath()
        let r = s * 0.06
        body.move(to: CGPoint(x: cup.minX, y: cup.maxY))
        body.line(to: CGPoint(x: cup.minX + s * 0.03, y: cup.minY + r))
        body.appendArc(
            withCenter: CGPoint(x: cup.minX + s * 0.03 + r, y: cup.minY + r),
            radius: r, startAngle: 180, endAngle: 270)
        body.line(to: CGPoint(x: cup.maxX - s * 0.03 - r, y: cup.minY))
        body.appendArc(
            withCenter: CGPoint(x: cup.maxX - s * 0.03 - r, y: cup.minY + r),
            radius: r, startAngle: 270, endAngle: 360)
        body.line(to: CGPoint(x: cup.maxX, y: cup.maxY))
        body.close()

        // Handle.
        let handle = NSBezierPath()
        handle.appendArc(
            withCenter: CGPoint(x: cup.maxX + s * 0.02, y: cup.midY + s * 0.02),
            radius: s * 0.12, startAngle: -75, endAngle: 75)
        handle.lineWidth = s * 0.07
        handle.stroke()

        // Saucer.
        let saucer = NSBezierPath(
            ovalIn: CGRect(x: s * 0.12, y: s * 0.14, width: s * 0.62, height: s * 0.10))
        saucer.stroke()

        // Coffee fill level per state.
        let fill: CGFloat
        switch state {
        case .free: fill = 0
        case .counting: fill = 0.45
        case .blocked, .caffeinated: fill = 0.82
        }
        if fill > 0 {
            let fillH = cup.height * fill
            let clip = CGRect(x: cup.minX, y: cup.minY, width: cup.width, height: fillH)
            ctx.saveGState()
            body.addClip()
            NSBezierPath(rect: clip).fill()
            ctx.restoreGState()
        }
        body.lineWidth = s * 0.07
        body.stroke()

        switch state {
        case .blocked:
            // Steam — it's hot/awake.
            steam(at: cup.midX, top: cup.maxY, size: s)
        case .caffeinated:
            // Bolt over the cup.
            bolt(centerX: cup.midX, baseY: cup.maxY + s * 0.04, size: s)
        case .free, .counting:
            break
        }
    }

    private static func steam(at x: CGFloat, top: CGFloat, size s: CGFloat) {
        for dx in [-s * 0.10, s * 0.10] {
            let p = NSBezierPath()
            p.lineWidth = s * 0.05
            p.move(to: CGPoint(x: x + dx, y: top + s * 0.06))
            p.curve(
                to: CGPoint(x: x + dx, y: top + s * 0.20),
                controlPoint1: CGPoint(x: x + dx + s * 0.06, y: top + s * 0.11),
                controlPoint2: CGPoint(x: x + dx - s * 0.06, y: top + s * 0.15))
            p.stroke()
        }
    }

    private static func bolt(centerX x: CGFloat, baseY y: CGFloat, size s: CGFloat) {
        let b = NSBezierPath()
        b.move(to: CGPoint(x: x + s * 0.04, y: y + s * 0.20))
        b.line(to: CGPoint(x: x - s * 0.08, y: y + s * 0.07))
        b.line(to: CGPoint(x: x - s * 0.005, y: y + s * 0.07))
        b.line(to: CGPoint(x: x - s * 0.04, y: y - s * 0.06))
        b.line(to: CGPoint(x: x + s * 0.10, y: y + s * 0.09))
        b.line(to: CGPoint(x: x + s * 0.02, y: y + s * 0.09))
        b.close()
        b.fill()
    }
}
