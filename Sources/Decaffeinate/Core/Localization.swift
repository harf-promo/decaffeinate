import Foundation

/// Localization scaffolding (v1.20 "Global").
///
/// The app's translatable strings live in per-language tables at
/// `Resources/<lang>.lproj/Localizable.strings` (NOT a `.xcstrings` String
/// Catalog — the plain `swift build` used here doesn't compile catalogs; see
/// `docs/LOCALIZATION.md`). With `defaultLocalization` set in `Package.swift`,
/// SwiftPM copies them into the **executable target's own** resource bundle —
/// `Bundle.module` (`Decaffeinate_Decaffeinate.bundle`), NOT the app's
/// `Bundle.main`. SwiftUI's `Text("literal")` localizes against `Bundle.main`
/// and would never see these tables, so seeded call sites resolve through
/// `L10n.localized(_:)`, which targets `Bundle.module`. This one helper also
/// covers `Button`, `Toggle`, `Label`, `.help(_:)`, and `NSWindow.title`, none
/// of which expose a `bundle:` parameter.
///
/// This is deliberately a *seed*: only the onboarding + About surfaces are wired,
/// as a template for contributors (see `docs/LOCALIZATION.md`). Adding a raw
/// `Text("…")` elsewhere is NOT localized until it, too, is routed through here
/// and added to the string tables.
enum L10n {
    /// The bundle carrying the compiled string tables. Referencing it triggers
    /// the synthesized `Bundle.module` accessor, which traps if the resource
    /// bundle is absent at runtime — the same failure mode as the 1.12.0 crash,
    /// guarded by `build-app.sh`.
    static var bundle: Bundle { .module }

    /// Resolve a catalog key against the app's own resource bundle, honoring the
    /// user's language. Falls back to the English source text (which is the key)
    /// when a translation is missing — never an empty or placeholder string.
    static func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
