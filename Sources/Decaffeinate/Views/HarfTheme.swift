import AppKit
import SwiftUI

// =====================================================================
// Harf design foundation, ported to SwiftUI.
//
// The single source of brand vocabulary for the app. Mirrors the Harf
// design system (colors_and_type.css): two brand colours from the logo
// (grey + green), an ink/paper scale, a status family, a √2 spacing
// ladder, a 5/4 type scale, sharp corners, hairlines — not shadows.
//
// Rules that matter:
//  • Green is *punctuation* — one mark per surface, < 5%. Never a UI state.
//  • Active UI state uses `positive` (teal), not brand green.
//  • Brand green + ink/paper never theme-flip the way semantic surfaces do.
// =====================================================================

extension Color {
    /// Solid sRGB colour from a 0xRRGGBB literal.
    fileprivate init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that resolves to `light` in the light appearance and `dark`
    /// in the dark appearance — the SwiftUI equivalent of CSS `light-dark()`.
    fileprivate init(light: UInt, dark: UInt) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
    }

    // ── Brand (theme-independent — they belong to the brand, not the theme) ──
    static let harfGrey = Color(hex: 0x939598)
    static let harfGreen = Color(hex: 0xA4CD39)
    static let greenHover = Color(hex: 0x8FB72A)  // green-600
    static let greenPress = Color(hex: 0x7AA01D)  // green-700
    /// green-900 — the only green legible as text on paper.
    static let accentText = Color(hex: 0x4D6A0F)
    /// grey-900 — the ONLY legal foreground on a green field (never theme-flips).
    static let onGreen = Color(hex: 0x1A1B1D)

    // ── Ink (text) — theme-aware ──
    static let ink1 = Color(light: 0x1A1B1D, dark: 0xF2F2F3)
    static let ink2 = Color(light: 0x4A4B4E, dark: 0xBBBBBE)
    static let ink3 = Color(light: 0x646669, dark: 0x939598)  // AA on every paper surface
    static let ink4 = Color(light: 0x939598, dark: 0x6E7073)
    static let inkDisabled = Color(light: 0x4A4B4E, dark: 0x939598)
    static let grey800 = Color(hex: 0x2A2B2D)

    // ── Surfaces — theme-aware ──
    static let paper = Color(light: 0xFFFFFF, dark: 0x0F1011)
    static let paper2 = Color(light: 0xFAFAFA, dark: 0x16181A)
    static let paper3 = Color(light: 0xF2F2F3, dark: 0x1D1F22)
    static let paper4 = Color(light: 0xEAEAEC, dark: 0x25282B)

    // ── Rules / hairlines — theme-aware ──
    static let rule = Color(light: 0xE4E4E6, dark: 0x2A2D31)
    static let rule2 = Color(light: 0x9C9EA1, dark: 0x3E4146)  // control boundary (passes 1.4.11)
    static let ruleStrong = Color(light: 0x1A1B1D, dark: 0xFFFFFF)

    // ── Status family — each tint / default / deep. Fixed (stamped-tag colours
    //    read correctly in both themes, like the design system's pills). ──
    static let positive = Color(hex: 0x2F8C5A)
    static let positiveTint = Color(hex: 0xDCEFE3)
    static let positiveDeep = Color(hex: 0x175A37)
    static let warning = Color(hex: 0xD49A2A)
    static let warningTint = Color(hex: 0xF8EED0)
    static let warningDeep = Color(hex: 0x8C6310)
    static let critical = Color(hex: 0xC7432B)
    static let criticalTint = Color(hex: 0xF5D9D2)
    static let criticalDeep = Color(hex: 0x82230F)
    static let info = Color(hex: 0x3E78A8)
    static let infoTint = Color(hex: 0xDEEAF2)
    static let infoDeep = Color(hex: 0x1B4368)
}

extension NSColor {
    fileprivate convenience init(hex: UInt) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}

// =====================================================================
// Spacing — strict √2 ladder (4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 · 96).
// =====================================================================
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64
    static let s9: CGFloat = 96
}

// =====================================================================
// Radii — sharp by default; one soft 4px corner (buttons/inputs); pills.
// =====================================================================
enum Radius {
    static let sharp: CGFloat = 0
    static let soft: CGFloat = 4
    static let pill: CGFloat = 999
}

/// Shared layout constants used across more than one view.
enum Metrics {
    /// The app-icon size in a blocker row; the expanded detail indents past it.
    static let rowIcon: CGFloat = 26
}

// =====================================================================
// Type — SF Pro at the Harf 5/4 scale + tracking + casing. (Geist is the
// design system's Latin face; the app keeps the system font but adopts
// the scale, tracking and UPPERCASE-tracked label voice.)
// =====================================================================
enum HarfFont {
    static let display = Font.system(size: 30, weight: .semibold)  // onboarding hero
    static let h2 = Font.system(size: 20, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)  // card headline / settings header
    static let lede = Font.system(size: 15, weight: .regular)  // onboarding body
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12, weight: .regular)
    static let micro = Font.system(size: 11, weight: .regular)
    static let eyebrow = Font.system(size: 10, weight: .semibold)
    static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let codeSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
}

extension View {
    /// The tracked UPPERCASE small-caps label voice (eyebrows, section heads).
    func eyebrow(_ color: Color = .ink3) -> some View {
        self.font(HarfFont.eyebrow)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(color)
    }

    /// Secondary explanatory caption.
    func harfExplanatory() -> some View {
        self.font(HarfFont.caption).foregroundStyle(Color.ink3)
    }

    /// A 1px Harf hairline below/above the view's row context.
    func harfCardChrome() -> some View {
        self
            .background(Color.paper)
            .overlay(Rectangle().stroke(Color.rule, lineWidth: 1))
    }
}

/// A 1px hairline rule — the system runs on these, not shadows.
struct Hairline: View {
    var color: Color = .rule
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// The Decaffeinate brand mark — the "nightcap": a coffee cup with one harf-green
/// crescent moon rising like steam (matches the app icon, tonally adapted so the
/// cup stays legible on a paper surface). The same mark used everywhere.
struct DecaffeinateMark: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height)

            // Saucer.
            ctx.fill(
                Path(
                    ellipseIn: CGRect(
                        x: s * 0.235, y: s * 0.690, width: s * 0.45, height: s * 0.075)),
                with: .color(.ink1))

            // Handle (stroked C on the right).
            var handle = Path()
            handle.move(to: CGPoint(x: s * 0.61, y: s * 0.44))
            handle.addCurve(
                to: CGPoint(x: s * 0.60, y: s * 0.61),
                control1: CGPoint(x: s * 0.76, y: s * 0.44),
                control2: CGPoint(x: s * 0.76, y: s * 0.61))
            ctx.stroke(
                handle, with: .color(.ink1),
                style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))

            // Cup body (filled), tapered with a rounded bottom.
            var cup = Path()
            cup.move(to: CGPoint(x: s * 0.295, y: s * 0.38))
            cup.addLine(to: CGPoint(x: s * 0.625, y: s * 0.38))
            cup.addLine(to: CGPoint(x: s * 0.597, y: s * 0.61))
            cup.addQuadCurve(
                to: CGPoint(x: s * 0.542, y: s * 0.66), control: CGPoint(x: s * 0.592, y: s * 0.66))
            cup.addLine(to: CGPoint(x: s * 0.378, y: s * 0.66))
            cup.addQuadCurve(
                to: CGPoint(x: s * 0.323, y: s * 0.61), control: CGPoint(x: s * 0.328, y: s * 0.66))
            cup.closeSubpath()
            ctx.fill(cup, with: .color(.ink1))

            // Crescent moon (green) rising at the upper-right.
            let r1 = s * 0.085
            let r2 = s * 0.068
            var moon = Path()
            moon.addEllipse(
                in: CGRect(x: s * 0.62 - r1, y: s * 0.26 - r1, width: r1 * 2, height: r1 * 2))
            moon.addEllipse(
                in: CGRect(x: s * 0.65 - r2, y: s * 0.235 - r2, width: r2 * 2, height: r2 * 2))
            ctx.fill(moon, with: .color(.harfGreen), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The tracked uppercase section eyebrow used between menu sections.
struct Eyebrow: View {
    let text: String
    var trailing: String?
    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }
    var body: some View {
        HStack {
            Text(text).eyebrow()
            Spacer()
            if let trailing { Text(trailing).eyebrow(.ink4) }
        }
    }
}

// =====================================================================
// Button — primary is INK (darkens on hover); brand green is reserved for
// :active. Variants: primary · accent · ghost · destructive · text.
// =====================================================================
struct HarfButtonStyle: ButtonStyle {
    enum Variant { case primary, accent, ghost, destructive, text }
    enum Size { case regular, large, small }

    var variant: Variant = .primary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        HarfButtonBody(variant: variant, size: size, configuration: configuration)
    }
}

private struct HarfButtonBody: View {
    let variant: HarfButtonStyle.Variant
    let size: HarfButtonStyle.Size
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.soft)
                    .stroke(border, lineWidth: border == .clear ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.soft))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.55)
    }

    private var pressed: Bool { configuration.isPressed }

    private var font: Font {
        switch size {
        case .small: return HarfFont.caption
        case .regular: return HarfFont.bodyMedium
        case .large: return Font.system(size: 14, weight: .semibold)
        }
    }
    private var padH: CGFloat { size == .small ? Space.s3 : Space.s4 }
    private var padV: CGFloat {
        switch size {
        case .small: return 6
        case .regular: return 9
        case .large: return 11
        }
    }

    private var bg: Color {
        guard enabled else { return .paper3 }
        switch variant {
        case .primary: return pressed ? .greenPress : (hovering ? .grey800 : .ink1)
        case .accent: return pressed ? .greenPress : (hovering ? .greenHover : .harfGreen)
        case .ghost: return pressed ? .greenPress : (hovering ? .ink1 : .clear)
        case .destructive: return pressed ? .criticalDeep : (hovering ? .critical : .paper)
        case .text: return .clear
        }
    }
    private var fg: Color {
        guard enabled else { return .inkDisabled }
        switch variant {
        case .primary: return .paper
        case .accent: return pressed ? .paper : .onGreen
        case .ghost: return (hovering || pressed) ? .paper : .ink1
        case .destructive: return (hovering || pressed) ? .paper : .criticalDeep
        case .text: return .ink1
        }
    }
    private var border: Color {
        switch variant {
        case .ghost: return (hovering || pressed) ? bg : .ink1
        case .destructive: return pressed ? .criticalDeep : .critical
        default: return .clear
        }
    }
}

// =====================================================================
// Pill / tag — sharp pill, hairline currentColor border, UPPERCASE label.
// Status tags read as stamped, not floating chips.
// =====================================================================
struct HarfPill: View {
    enum Variant { case neutral, positive, warning, critical, info, ink, live }
    let label: String
    var variant: Variant = .neutral
    var dot: Bool = false

    var body: some View {
        HStack(spacing: Space.s1) {
            if dot { Circle().fill(fg).frame(width: 5, height: 5) }
            Text(label).textCase(.uppercase).tracking(0.7)
        }
        .font(HarfFont.eyebrow)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 2)
        .foregroundStyle(fg)
        .background(bg)
        .overlay(Capsule().stroke(border, lineWidth: border == .clear ? 0 : 1))
        .clipShape(Capsule())
    }

    private var fg: Color {
        switch variant {
        case .neutral: return .ink2
        case .positive: return .positiveDeep
        case .warning: return .warningDeep
        case .critical: return .criticalDeep
        case .info: return .infoDeep
        case .ink: return .paper
        case .live: return .onGreen
        }
    }
    private var bg: Color {
        switch variant {
        case .neutral: return .paper
        case .positive: return .positiveTint
        case .warning: return .warningTint
        case .critical: return .criticalTint
        case .info: return .infoTint
        case .ink: return .ink1
        case .live: return .harfGreen
        }
    }
    private var border: Color {
        switch variant {
        case .neutral: return .rule2
        case .ink, .live: return .clear
        default: return fg
        }
    }
}
