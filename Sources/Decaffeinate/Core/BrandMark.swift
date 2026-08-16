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
        case moon  // sage-lime in colour; black in template
        case zzz  // ink/grey in colour; black in template
        case cream  // porcelain on the night icon; adaptive ink in-app
        case well  // coffee/night surface inside the cup (so it reads as a vessel)
    }

    /// A rendered element: a filled path + colour role + fill rule.
    struct Element {
        let path: CGPath
        let ink: Ink
        /// Use even-odd fill rule when true (needed for the crescent carve).
        let evenOdd: Bool
    }

    // ── Full-colour logo (in-app mark, app icon, SVG) ───────────────────────

    /// The brand mark: a large crescent with a single Z in its open mouth.
    /// Sleep, not coffee — no cup. Same geometry at Dock, menu bar, and GitHub.
    /// Y-down; AppKit must flip the CTM.
    static func logo(in rect: CGRect) -> [Element] {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func px(_ n: CGFloat) -> CGFloat { ox + n * s }
        func py(_ n: CGFloat) -> CGFloat { oy + n * s }
        func pr(_ n: CGFloat) -> CGFloat { n * s }

        return [
            Element(
                path: crescent(
                    cx: px(Self.markMoonCX), cy: py(Self.markMoonCY), r: pr(Self.markMoonR)),
                ink: .moon, evenOdd: false),
            Element(
                path: zGlyph(
                    x: px(0.60), y: py(0.14), w: pr(0.28), h: pr(0.24), thicknessRatio: 0.28),
                ink: .cream, evenOdd: false),
            Element(
                path: star4(cx: px(0.30), cy: py(0.40), r: pr(0.055)),
                ink: .cream, evenOdd: false),
        ]
    }

    /// Same mark as `logo` — one silhouette at every size.
    static func logoCompact(in rect: CGRect) -> [Element] { logo(in: rect) }

    /// Shared moon placement so the menu-bar glyph is the same mark as the Dock icon.
    static let markMoonCX: CGFloat = 0.44
    static let markMoonCY: CGFloat = 0.54
    static let markMoonR: CGFloat = 0.36

    // ── Menu-bar glyphs (monochrome template, 4 states) ─────────────────────

    /// Menu-bar glyph for `state`. Uses the **same moon placement as `logo`**
    /// so the 16px bar icon is the app mark, not a leftover sliver.
    /// `.free` is the brand (crescent + Z). Other states keep a bold modifier
    /// and, for `.blocked`, a fuller moon. Template images are monochrome.
    static func menuGlyph(for state: MugState, in rect: CGRect) -> [Element] {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func px(_ n: CGFloat) -> CGFloat { ox + n * s }
        func py(_ n: CGFloat) -> CGFloat { oy + n * s }
        func pr(_ n: CGFloat) -> CGFloat { n * s }

        func moon(carveRadiusRatio: CGFloat, carveOffsetRatio: CGFloat) -> Element {
            Element(
                path: crescent(
                    cx: px(Self.markMoonCX), cy: py(Self.markMoonCY), r: pr(Self.markMoonR),
                    carveRadiusRatio: carveRadiusRatio, carveOffsetRatio: carveOffsetRatio),
                ink: .moon, evenOdd: false)
        }

        switch state {
        case .free:
            // The brand mark itself: standard crescent + Z in the mouth.
            return [
                moon(
                    carveRadiusRatio: crescentCarveRadiusRatio,
                    carveOffsetRatio: crescentCarveOffsetRatio),
                Element(
                    path: zGlyph(
                        x: px(0.60), y: py(0.14), w: pr(0.28), h: pr(0.24), thicknessRatio: 0.28),
                    ink: .zzz, evenOdd: false),
            ]

        case .counting:
            return [
                moon(
                    carveRadiusRatio: crescentCarveRadiusRatio,
                    carveOffsetRatio: crescentCarveOffsetRatio),
                Element(
                    path: chevronDown(
                        cx: px(0.76), topY: py(0.16),
                        halfSpan: pr(0.20), height: pr(0.20), barW: pr(0.10)),
                    ink: .zzz, evenOdd: false),
            ]

        case .blocked:
            let (body, dot) = exclamation(
                cx: px(0.78), topY: py(0.16),
                bodyH: pr(0.24), bodyW: pr(0.14),
                gap: pr(0.04), dotR: pr(0.09))
            return [
                moon(carveRadiusRatio: 0.82, carveOffsetRatio: 0.26),
                Element(path: body, ink: .zzz, evenOdd: false),
                Element(path: dot, ink: .zzz, evenOdd: false),
            ]

        case .caffeinated:
            return [
                moon(
                    carveRadiusRatio: crescentCarveRadiusRatio,
                    carveOffsetRatio: crescentCarveOffsetRatio),
                Element(
                    path: bolt(cx: px(0.77), cy: py(0.36), size: s, scale: 1.3),
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
    ///
    /// `carveRadiusRatio`/`carveOffsetRatio` default to the brand's standard
    /// crescent, but callers may override them to change the moon's
    /// **fullness** — a smaller offset/radius keeps more of the disc (a fat,
    /// near-solid gibbous moon); a larger one cuts deeper (a thin sliver). Both
    /// stay a homothety of the same lune about `(cx, cy)`, so the menu-bar
    /// states can vary ink weight on the *same* brand shape instead of only on
    /// a secondary modifier. See `BrandMark.menuGlyph(for:in:)`.
    static func crescent(
        cx: CGFloat, cy: CGFloat, r: CGFloat,
        carveRadiusRatio: CGFloat = crescentCarveRadiusRatio,
        carveOffsetRatio: CGFloat = crescentCarveOffsetRatio
    ) -> CGPath {
        let r2 = r * carveRadiusRatio
        let d = r * carveOffsetRatio
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

    /// A filled disc — the coffee well inside the cup.
    static func disc(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        return path
    }

    /// Filled Z-glyph in a bounding box, y-down.
    /// The path is self-intersecting (the two diagonal inner edges cross);
    /// use non-zero winding rule for a solid fill.
    static func zGlyph(
        x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, thicknessRatio: CGFloat = 0.32
    ) -> CGPath {
        let th = min(w, h) * thicknessRatio
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

    private static func bolt(cx: CGFloat, cy: CGFloat, size s: CGFloat, scale: CGFloat = 1.0)
        -> CGPath
    {
        // Lightning-bolt polygon, y-down. `scale` grows the bolt around its own
        // (cx, cy) without moving its anchor point.
        let k = s * scale
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx + k * 0.06, y: cy - k * 0.15))
        path.addLine(to: CGPoint(x: cx - k * 0.09, y: cy + k * 0.02))
        path.addLine(to: CGPoint(x: cx - k * 0.005, y: cy + k * 0.02))
        path.addLine(to: CGPoint(x: cx - k * 0.06, y: cy + k * 0.15))
        path.addLine(to: CGPoint(x: cx + k * 0.11, y: cy - k * 0.03))
        path.addLine(to: CGPoint(x: cx + k * 0.02, y: cy - k * 0.03))
        path.closeSubpath()
        return path
    }
}
