import CoreGraphics
import Foundation

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

    /// Semantic ink role. Each renderer maps a role to its own context, so the
    /// one geometry reads correctly as a full-colour badge, an adaptive line
    /// mark, and a monochrome template.
    enum Ink {
        case moon  // harf-green (#A4CD39) in colour; black in template
        case zzz  // ink/grey (#939598) in colour; black in template
        case cream  // porcelain (#F2EDE4) on the night icon; adaptive ink in-app
    }

    /// A rendered element: a filled path + colour role + fill rule.
    struct Element {
        let path: CGPath
        let ink: Ink
        /// Use even-odd fill rule when true (needed for the crescent carve).
        let evenOdd: Bool
    }

    // ── Full-colour logo (in-app mark, app icon, SVG) ───────────────────────

    /// The full brand mark — "the moon in your cup": a top-down porcelain cup
    /// whose coffee surface is the night sky, a green crescent moon floating in
    /// it, a star, and the steam rising as a single green "z". Tells the product
    /// story in one image — the caffeine is gone, the moon is in the cup.
    /// Scaled into `rect`. Y-down coordinate system; AppKit must flip the CTM.
    static func logo(in rect: CGRect) -> [Element] {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func px(_ n: CGFloat) -> CGFloat { ox + n * s }
        func py(_ n: CGFloat) -> CGFloat { oy + n * s }
        func pr(_ n: CGFloat) -> CGFloat { n * s }

        return [
            // Cup rim — a porcelain ring seen top-down (annulus, even-odd carve).
            Element(
                path: ring(cx: px(0.45), cy: py(0.63), outer: pr(0.305), inner: pr(0.245)),
                ink: .cream, evenOdd: true),
            // The handle, attached on the right.
            Element(
                path: ring(cx: px(0.80), cy: py(0.63), outer: pr(0.105), inner: pr(0.052)),
                ink: .cream, evenOdd: true),
            // The crescent moon floating in the coffee, its mouth opening up-right.
            Element(
                path: crescent(cx: px(0.45), cy: py(0.645), r: pr(0.15)),
                ink: .moon, evenOdd: false),
            // A star in the open night-coffee surface, tucked left of the moon.
            Element(
                path: star4(cx: px(0.30), cy: py(0.52), r: pr(0.038)),
                ink: .cream, evenOdd: false),
            // The steam rises as two ascending z's — the universal "sleep" signal.
            Element(
                path: zGlyph(x: px(0.485), y: py(0.255), w: pr(0.09), h: pr(0.075)),
                ink: .moon, evenOdd: false),
            Element(
                path: zGlyph(x: px(0.58), y: py(0.115), w: pr(0.13), h: pr(0.11)),
                ink: .moon, evenOdd: false),
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
            ink: .moon, evenOdd: false)

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

    /// Crescent carve geometry, as fractions of the moon radius. The offset is
    /// large enough that the carve circle reaches `crescentReachRatio` PAST the
    /// rim — a real, wide-mouthed crescent. (The old mark used ~0.76 radius at a
    /// ~0.25 offset, reaching only ~1.007r, so the "moon" read as a near-closed
    /// ring. A test guards `crescentReachRatio` so that can never return.)
    static let crescentCarveRadiusRatio: CGFloat = 1.05
    static let crescentCarveOffsetRatio: CGFloat = 0.50
    /// How far the carve circle reaches past the moon centre, in units of r.
    /// > 1 means the carve clears the rim and opens a genuine crescent mouth.
    static var crescentReachRatio: CGFloat {
        crescentCarveOffsetRatio + crescentCarveRadiusRatio  // ≈ 1.55
    }

    /// A true crescent lune — the region of the moon disc NOT covered by an
    /// offset carve disc — traced as ONE closed path from two circular arcs
    /// meeting at the horns. (Even-odd XOR of two circles would instead fill
    /// *both* opposing lunes, reading as a ring/"eye", not a moon — the bug the
    /// old mark had.) Fill with non-zero winding. Y-down; concave mouth faces
    /// upper-right, toward the rising z / steam.
    static func crescent(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
        let r2 = r * crescentCarveRadiusRatio
        let d = r * crescentCarveOffsetRatio
        let dir = CGPoint(x: 0.94, y: -0.34)  // ≈ unit, 20° above +x (upper-right)
        let cxCarve = cx + d * dir.x
        let cyCarve = cy + d * dir.y

        // Horn intersections of the two circles, along/perpendicular to `dir`.
        let a = (d * d + r * r - r2 * r2) / (2 * d)  // distance from moon centre along dir
        let h = (r * r - a * a).squareRoot()  // half-chord
        let perp = CGPoint(x: -dir.y, y: dir.x)
        let h1 = CGPoint(x: cx + a * dir.x + h * perp.x, y: cy + a * dir.y + h * perp.y)
        let h2 = CGPoint(x: cx + a * dir.x - h * perp.x, y: cy + a * dir.y - h * perp.y)

        // Fat side (moon rim) is opposite the carve; concave side (carve rim)
        // bulges toward it. Sample each arc through the correct midpoint.
        let fat = CGPoint(x: -dir.x, y: -dir.y)  // away from the carve
        let outerThrough = atan2(fat.y, fat.x)
        let innerThrough = atan2(-dir.y, -dir.x)  // carve-rim point toward the fat side

        let outer = arcPoints(
            cx: cx, cy: cy, radius: r,
            from: atan2(h1.y - cy, h1.x - cx), to: atan2(h2.y - cy, h2.x - cx),
            through: outerThrough)
        let inner = arcPoints(
            cx: cxCarve, cy: cyCarve, radius: r2,
            from: atan2(h2.y - cyCarve, h2.x - cxCarve),
            to: atan2(h1.y - cyCarve, h1.x - cxCarve),
            through: innerThrough)

        let path = CGMutablePath()
        path.addLines(between: outer + inner)
        path.closeSubpath()
        return path
    }

    /// Sample a circular arc from `from` to `to` going the way that passes
    /// `through` — direction-agnostic, so callers needn't reason about winding.
    private static func arcPoints(
        cx: CGFloat, cy: CGFloat, radius: CGFloat,
        from: CGFloat, to: CGFloat, through: CGFloat, count: Int = 48
    ) -> [CGPoint] {
        let twoPi = CGFloat.pi * 2
        func norm(_ x: CGFloat) -> CGFloat {
            var v = x.truncatingRemainder(dividingBy: twoPi); if v < 0 { v += twoPi }; return v
        }
        let ccw = norm(to - from)  // CCW sweep from→to
        let throughCCW = norm(through - from)
        let sweep = throughCCW <= ccw ? ccw : ccw - twoPi  // pick the arc containing `through`
        return (0...count).map { i in
            let t = from + sweep * CGFloat(i) / CGFloat(count)
            return CGPoint(x: cx + radius * cos(t), y: cy + radius * sin(t))
        }
    }

    /// A ring / annulus — two concentric ellipses, even-odd, so the centre is
    /// hollow. Used for the cup rim and handle.
    static func ring(cx: CGFloat, cy: CGFloat, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(
            in: CGRect(x: cx - outer, y: cy - outer, width: outer * 2, height: outer * 2))
        path.addEllipse(
            in: CGRect(x: cx - inner, y: cy - inner, width: inner * 2, height: inner * 2))
        return path
    }

    /// A four-point sparkle/star, non-zero winding. Y-down (symmetric).
    static func star4(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
        let d = r * 0.30  // inner vertices sit on the diagonals, pinched in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx, y: cy - r))  // N
        path.addLine(to: CGPoint(x: cx + d, y: cy - d))
        path.addLine(to: CGPoint(x: cx + r, y: cy))  // E
        path.addLine(to: CGPoint(x: cx + d, y: cy + d))
        path.addLine(to: CGPoint(x: cx, y: cy + r))  // S
        path.addLine(to: CGPoint(x: cx - d, y: cy + d))
        path.addLine(to: CGPoint(x: cx - r, y: cy))  // W
        path.addLine(to: CGPoint(x: cx - d, y: cy - d))
        path.closeSubpath()
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
