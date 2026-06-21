import AppKit

/// Draws Decaffeinate's menu-bar glyphs at runtime as **template** images (the
/// menu bar tints them and they adapt to light/dark). Runtime drawing avoids
/// shipping/locating resource bundles in the hand-assembled `.app`.
///
/// The "nightcap" family: a constant coffee cup whose *fill* carries the state
/// (more coffee = more awake), with a small crescent moon on the resting state.
/// - `.free` — empty cup + a crescent (decaffeinated; free to sleep)
/// - `.counting` — cup draining (winding down)
/// - `.blocked` — full cup, steaming (something's keeping it awake)
/// - `.caffeinated` — full cup + a bolt (intentionally wired)
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
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Cup body — a slightly tapered rounded vessel.
        let cup = CGRect(x: s * 0.22, y: s * 0.24, width: s * 0.44, height: s * 0.42)
        let r = s * 0.07
        let body = NSBezierPath()
        body.move(to: CGPoint(x: cup.minX, y: cup.maxY))
        body.line(to: CGPoint(x: cup.minX + s * 0.04, y: cup.minY + r))
        body.appendArc(
            withCenter: CGPoint(x: cup.minX + s * 0.04 + r, y: cup.minY + r),
            radius: r, startAngle: 180, endAngle: 270)
        body.line(to: CGPoint(x: cup.maxX - s * 0.04 - r, y: cup.minY))
        body.appendArc(
            withCenter: CGPoint(x: cup.maxX - s * 0.04 - r, y: cup.minY + r),
            radius: r, startAngle: 270, endAngle: 360)
        body.line(to: CGPoint(x: cup.maxX, y: cup.maxY))
        body.close()

        // Handle.
        let handle = NSBezierPath()
        handle.appendArc(
            withCenter: CGPoint(x: cup.maxX + s * 0.02, y: cup.midY - s * 0.01),
            radius: s * 0.12, startAngle: -78, endAngle: 78)
        handle.lineWidth = s * 0.075
        handle.stroke()

        // Saucer.
        let saucer = NSBezierPath(
            ovalIn: CGRect(x: s * 0.13, y: s * 0.12, width: s * 0.60, height: s * 0.10))
        saucer.lineWidth = s * 0.07
        saucer.stroke()

        // Coffee fill — the state lives here.
        let fill: CGFloat
        switch state {
        case .free: fill = 0
        case .counting: fill = 0.40
        case .blocked, .caffeinated: fill = 0.85
        }
        if fill > 0 {
            ctx.saveGState()
            body.addClip()
            let h = cup.height * fill
            NSBezierPath(rect: CGRect(x: cup.minX, y: cup.minY, width: cup.width, height: h)).fill()
            ctx.restoreGState()
        }
        body.lineWidth = s * 0.075
        body.stroke()

        switch state {
        case .free:
            // A small crescent — the nightcap, resting. Sits above the rim, clear
            // of the handle, and a touch fatter so it reads at 18px.
            crescent(cx: s * 0.71, cy: s * 0.81, r: s * 0.155).fill()
        case .blocked:
            steam(centerX: cup.midX, top: cup.maxY, size: s)
        case .caffeinated:
            bolt(centerX: cup.midX, baseY: cup.maxY + s * 0.05, size: s)
        case .counting:
            break
        }
    }

    /// A clean filled crescent via an internally-tangent carve (even-odd). A
    /// fatter carve ratio keeps it legible at menu-bar size.
    private static func crescent(cx: CGFloat, cy: CGFloat, r: CGFloat) -> NSBezierPath {
        let r2 = r * 0.72
        let d = r - r2
        let path = NSBezierPath()
        path.appendOval(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        let ox = cx + d * 0.85
        let oy = cy + d * 0.55
        path.appendOval(in: CGRect(x: ox - r2, y: oy - r2, width: r2 * 2, height: r2 * 2))
        path.windingRule = .evenOdd
        return path
    }

    private static func steam(centerX x: CGFloat, top: CGFloat, size s: CGFloat) {
        for dx in [-s * 0.09, s * 0.09] {
            let p = NSBezierPath()
            p.lineWidth = s * 0.05
            p.move(to: CGPoint(x: x + dx, y: top + s * 0.06))
            p.curve(
                to: CGPoint(x: x + dx, y: top + s * 0.21),
                controlPoint1: CGPoint(x: x + dx + s * 0.07, y: top + s * 0.11),
                controlPoint2: CGPoint(x: x + dx - s * 0.07, y: top + s * 0.16))
            p.stroke()
        }
    }

    private static func bolt(centerX x: CGFloat, baseY y: CGFloat, size s: CGFloat) {
        let b = NSBezierPath()
        b.move(to: CGPoint(x: x + s * 0.05, y: y + s * 0.22))
        b.line(to: CGPoint(x: x - s * 0.09, y: y + s * 0.07))
        b.line(to: CGPoint(x: x - s * 0.005, y: y + s * 0.07))
        b.line(to: CGPoint(x: x - s * 0.05, y: y - s * 0.07))
        b.line(to: CGPoint(x: x + s * 0.11, y: y + s * 0.10))
        b.line(to: CGPoint(x: x + s * 0.02, y: y + s * 0.10))
        b.close()
        b.fill()
    }
}
