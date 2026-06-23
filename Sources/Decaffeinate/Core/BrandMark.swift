import CoreGraphics

/// Decaffeinate's brand geometry — the "Moon + Zzz" mark.
///
/// A single source of truth for all renderers:
/// - `DecaffeinateMark` (SwiftUI Canvas) uses `logo(in:)` via `Path(cgPath)`.
/// - `MugIcon` (AppKit template image) uses `menuGlyph(for:in:)` via CGContext.
/// - `IconRenderer` uses `logo(in:)` via CGContext.
///
/// All paths use a **y-down** coordinate system (top-left origin, matching
/// SwiftUI Canvas). AppKit consumers using `lockFocus()` (y-up, bottom-left
/// origin) must flip the CTM before drawing:
///
///     ctx.translateBy(x: 0, y: size)
///     ctx.scaleBy(x: 1, y: -1)
///
enum BrandMark {
    // ── Color role ──────────────────────────────────────────────────────────

    /// Semantic ink role in the full-colour logo.
    enum Ink {
        case moon  // harf-green (#A4CD39) in colour; black in template
        case zzz  // ink/grey (#939598) in colour; black in template
    }

    /// A rendered element: a filled path + colour role + fill rule.
    struct Element {
        let path: CGPath
        let ink: Ink
        /// Use even-odd fill rule when true (needed for the crescent carve).
        let evenOdd: Bool
    }

    // ── Full-colour logo (in-app mark, app icon, SVG) ───────────────────────

    /// The full brand mark — a green crescent moon with three rising z's —
    /// scaled into `rect`. Y-down coordinate system; AppKit must flip the CTM.
    static func logo(in rect: CGRect) -> [Element] {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func px(_ n: CGFloat) -> CGFloat { ox + n * s }
        func py(_ n: CGFloat) -> CGFloat { oy + n * s }
        func pr(_ n: CGFloat) -> CGFloat { n * s }

        return [
            Element(
                path: crescent(cx: px(0.36), cy: py(0.58), r: pr(0.29)),
                ink: .moon, evenOdd: true),
            Element(
                path: zGlyph(x: px(0.64), y: py(0.50), w: pr(0.21), h: pr(0.18)),
                ink: .zzz, evenOdd: false),
            Element(
                path: zGlyph(x: px(0.75), y: py(0.34), w: pr(0.15), h: pr(0.12)),
                ink: .zzz, evenOdd: false),
            Element(
                path: zGlyph(x: px(0.84), y: py(0.22), w: pr(0.10), h: pr(0.08)),
                ink: .zzz, evenOdd: false),
        ]
    }

    // ── Menu-bar glyphs (monochrome template, 4 states) ─────────────────────

    /// Menu-bar glyph for `state`, scaled into `rect`. All elements fill solid
    /// black in a template `NSImage` (tinted automatically by the menu bar).
    /// The crescent is the constant brand anchor; a modifier distinguishes state.
    /// Y-down coordinate system; AppKit must flip the CTM.
    static func menuGlyph(for state: MugState, in rect: CGRect) -> [Element] {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func px(_ n: CGFloat) -> CGFloat { ox + n * s }
        func py(_ n: CGFloat) -> CGFloat { oy + n * s }
        func pr(_ n: CGFloat) -> CGFloat { n * s }

        // The crescent is constant across every state.
        let moon = Element(
            path: crescent(cx: px(0.40), cy: py(0.55), r: pr(0.27)),
            ink: .moon, evenOdd: true)

        switch state {
        case .free:
            // A z rises from the crescent's open side — the hero resting state.
            return [
                moon,
                Element(
                    path: zGlyph(
                        x: px(0.69), y: py(0.26), w: pr(0.22), h: pr(0.19)),
                    ink: .zzz, evenOdd: false),
            ]

        case .counting:
            // Filled downward chevron — winding down toward sleep.
            return [
                moon,
                Element(
                    path: chevronDown(
                        cx: px(0.76), topY: py(0.22),
                        halfSpan: pr(0.17), height: pr(0.16), barW: pr(0.08)),
                    ink: .zzz, evenOdd: false),
            ]

        case .blocked:
            // Exclamation mark — something is keeping the Mac awake.
            let (body, dot) = exclamation(
                cx: px(0.78), topY: py(0.22),
                bodyH: pr(0.19), bodyW: pr(0.11),
                gap: pr(0.04), dotR: pr(0.07))
            return [
                moon,
                Element(path: body, ink: .zzz, evenOdd: false),
                Element(path: dot, ink: .zzz, evenOdd: false),
            ]

        case .caffeinated:
            // Lightning bolt — intentionally wired awake.
            return [
                moon,
                Element(
                    path: bolt(cx: px(0.77), cy: py(0.36), size: s),
                    ink: .zzz, evenOdd: false),
            ]
        }
    }

    // ── Primitive shapes (internal — accessible to tests via @testable import) ──

    /// Crescent via two offset ellipses with even-odd winding. Y-down.
    /// The carve is shifted upper-right; the concave side faces upper-right.
    static func crescent(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
        let r2 = r * 0.76
        let d = r - r2
        let path = CGMutablePath()
        // Main circle.
        path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        // Carve circle: shifted right (+x) and up (-y in y-down).
        path.addEllipse(
            in: CGRect(
                x: cx + d * 0.90 - r2,
                y: cy - d * 0.50 - r2,
                width: r2 * 2, height: r2 * 2))
        return path
    }

    /// Filled Z-glyph in a bounding box, y-down.
    /// The path is self-intersecting (the two diagonal inner edges cross);
    /// use non-zero winding rule for a solid fill.
    static func zGlyph(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGPath {
        let th = min(w, h) * 0.32  // bar thickness ~32% of the short dimension
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: y))  // TL
        path.addLine(to: CGPoint(x: x + w, y: y))  // TR
        path.addLine(to: CGPoint(x: x + w, y: y + th))  // TR-inner
        path.addLine(to: CGPoint(x: x + th, y: y + h - th))  // diagonal end
        path.addLine(to: CGPoint(x: x + w, y: y + h - th))  // BR-inner
        path.addLine(to: CGPoint(x: x + w, y: y + h))  // BR
        path.addLine(to: CGPoint(x: x, y: y + h))  // BL
        path.addLine(to: CGPoint(x: x, y: y + h - th))  // BL-inner
        path.addLine(to: CGPoint(x: x + w - th, y: y + th))  // diagonal start
        path.addLine(to: CGPoint(x: x, y: y + th))  // TL-inner
        path.closeSubpath()
        return path
    }

    // ── Menu-bar state modifier helpers ─────────────────────────────────────

    private static func chevronDown(
        cx: CGFloat, topY: CGFloat, halfSpan: CGFloat, height: CGFloat, barW: CGFloat
    ) -> CGPath {
        let tipY = topY + height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - halfSpan, y: topY))
        path.addLine(to: CGPoint(x: cx, y: tipY))
        path.addLine(to: CGPoint(x: cx + halfSpan, y: topY))
        path.addLine(to: CGPoint(x: cx + halfSpan - barW, y: topY))
        path.addLine(to: CGPoint(x: cx, y: tipY - barW * 1.4))
        path.addLine(to: CGPoint(x: cx - halfSpan + barW, y: topY))
        path.closeSubpath()
        return path
    }

    private static func exclamation(
        cx: CGFloat, topY: CGFloat, bodyH: CGFloat, bodyW: CGFloat,
        gap: CGFloat, dotR: CGFloat
    ) -> (CGPath, CGPath) {
        let body = CGMutablePath()
        body.addRect(CGRect(x: cx - bodyW / 2, y: topY, width: bodyW, height: bodyH))
        let dot = CGMutablePath()
        dot.addEllipse(
            in: CGRect(
                x: cx - dotR, y: topY + bodyH + gap, width: dotR * 2, height: dotR * 2))
        return (body, dot)
    }

    private static func bolt(cx: CGFloat, cy: CGFloat, size s: CGFloat) -> CGPath {
        // Lightning-bolt polygon, y-down.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx + s * 0.06, y: cy - s * 0.15))
        path.addLine(to: CGPoint(x: cx - s * 0.09, y: cy + s * 0.02))
        path.addLine(to: CGPoint(x: cx - s * 0.005, y: cy + s * 0.02))
        path.addLine(to: CGPoint(x: cx - s * 0.06, y: cy + s * 0.15))
        path.addLine(to: CGPoint(x: cx + s * 0.11, y: cy - s * 0.03))
        path.addLine(to: CGPoint(x: cx + s * 0.02, y: cy - s * 0.03))
        path.closeSubpath()
        return path
    }
}
