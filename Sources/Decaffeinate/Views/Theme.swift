import AppKit
import SwiftUI

// =====================================================================
// Theme — the swappable skin the design council produced.
//
// Two genuinely distinct poles share ONE set of structural fixes (the
// "universal fixes"); they differ only in this token bundle: surface
// warmth, hairlines-vs-cards, density and the headline size. Everything
// downstream reads `@Environment(\.theme)`, so rendering a direction is
// just injecting a different `Theme`.
//
//   • A "Nightcap" — cool, native, airy: white paper, hairline-separated
//     zero-radius rows, near-monochrome cool ink, one green moon.
//   • B "Dusk" — warm, cozy: warm off-white paper, soft tinted 10px cards,
//     warm ink, one green crescent.
// =====================================================================
struct Theme: Equatable {
    var id: String
    var displayName: String

    // ── Surfaces (dynamic light/dark) ──
    var paper: Color
    var card: Color  // raised surface / row card fill
    var cardActive: Color  // pending / selected fill
    var hairline: Color

    // ── Ink ──
    var ink1: Color
    var ink2: Color
    var ink3: Color
    var ink4: Color

    // ── Accents ──
    var accent: Color  // brand green — the one mark per surface
    var teal: Color  // positive dot (the "allowed" tag)

    // ── Shape / density ──
    var popoverWidth: CGFloat
    var rowMinHeight: CGFloat
    var usesCards: Bool  // true → soft cards; false → hairline rows
    var cardRadius: CGFloat
    var rowGap: CGFloat
    var contentInset: CGFloat

    // ── Type ──
    var headlineSize: CGFloat

    var headlineFont: Font { .system(size: headlineSize, weight: .semibold) }

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }
}

extension Theme {
    /// Dynamic light/dark colour from two 0xRRGGBB literals.
    fileprivate static func dyn(_ light: UInt, _ dark: UInt) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
            })
    }

    /// A — cool, native, airy. Hairlines, zero-radius rows, cool ink.
    static let nightcap = Theme(
        id: "nightcap",
        displayName: "Nightcap — cool & native",
        paper: dyn(0xFFFFFF, 0x121315),
        card: dyn(0xFAFAF9, 0x1B1C1E),
        cardActive: dyn(0xF1F1F2, 0x232427),
        hairline: dyn(0xE6E6E7, 0x2C2E32),
        ink1: dyn(0x1A1B1D, 0xF2F2F3),
        ink2: dyn(0x3A3B3D, 0xC9CACB),
        ink3: dyn(0x6B6C6E, 0x9A9B9D),
        ink4: dyn(0x939598, 0x6B6C6E),
        accent: Color.harfGreen,
        teal: Color(srgb: 0x2F8C5A),
        popoverWidth: 340,
        rowMinHeight: 44,
        usesCards: false,
        cardRadius: 0,
        rowGap: 0,
        contentInset: 16,
        headlineSize: 18
    )

}

extension Color {
    /// Solid sRGB colour from a 0xRRGGBB literal (non-fileprivate helper for themes).
    fileprivate init(srgb hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .nightcap
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
