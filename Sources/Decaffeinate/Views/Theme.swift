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
    /// A — cool, native, airy. Hairlines, zero-radius rows, cool ink.
    ///
    /// Surfaces and ink reference the shared `HarfTheme` `Color.*` tokens so the
    /// palette has a single source of truth — the two used to drift (this theme
    /// once declared its own dark paper `0x121315` vs `Color.paper`'s `0x0F1011`).
    static let nightcap = Theme(
        id: "nightcap",
        displayName: "Nightcap — cool & native",
        paper: .paper,
        card: .paper2,
        cardActive: .paper3,
        hairline: .rule,
        ink1: .ink1,
        ink2: .ink2,
        ink3: .ink3,
        ink4: .ink4,
        accent: Color.harfGreen,
        teal: Color.positive,
        popoverWidth: 340,
        rowMinHeight: 44,
        usesCards: false,
        cardRadius: 0,
        rowGap: 0,
        contentInset: 16,
        headlineSize: 18
    )

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
