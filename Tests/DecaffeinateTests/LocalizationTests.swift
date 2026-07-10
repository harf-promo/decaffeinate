import XCTest

@testable import Decaffeinate

/// Proves the localization plumbing actually works end to end: the string tables
/// compile into `Bundle.module`, ship, and resolve per language. These fail hard
/// if `resources:` regresses, if the `.lproj` tables don't get bundled, or if the
/// `Bundle.module` accessor can't find the resource bundle (the 1.12.0 crash
/// class).
final class LocalizationTests: XCTestCase {

    // Referencing L10n.bundle triggers the synthesized Bundle.module accessor —
    // it would trap if the resource bundle weren't wired into the target.
    func testModuleBundleResolves() {
        XCTAssertNotNil(L10n.bundle.bundleURL)
    }

    // `L10n.localized` returns a real value and falls back to the key on a miss —
    // asserted locale-independently (on a German host, "Skip" resolves to
    // "Überspringen", so we must NOT assume the English value here).
    func testLocalizedResolvesAndFallsBackToKey() {
        XCTAssertFalse(L10n.localized("Skip").isEmpty, "a seeded key resolves to a non-empty value")
        XCTAssertEqual(
            L10n.localized("‹no such key›"), "‹no such key›",
            "a missing key falls back to the key text, never empty")
    }

    // The English base table holds the source strings (locale-independent: load
    // en.lproj directly rather than relying on the host language being English).
    func testEnglishBaseTableValues() throws {
        let enURL = try XCTUnwrap(L10n.bundle.url(forResource: "en", withExtension: "lproj"))
        let en = try XCTUnwrap(Bundle(url: enURL))
        XCTAssertEqual(en.localizedString(forKey: "Skip", value: "␀", table: nil), "Skip")
        XCTAssertEqual(
            en.localizedString(forKey: "Get started", value: "␀", table: nil), "Get started")
    }

    // Both seeded language tables actually shipped inside the module bundle.
    func testCompiledTablesShipped() throws {
        XCTAssertNotNil(
            L10n.bundle.url(forResource: "en", withExtension: "lproj"),
            "en.lproj missing — base string table not bundled")
        XCTAssertNotNil(
            L10n.bundle.url(forResource: "de", withExtension: "lproj"),
            "de.lproj missing — seed language not bundled")
    }

    // Strong end-to-end proof: load the German table directly and confirm a seeded
    // value round-trips, without relying on the host's language setting.
    func testGermanSeedValuesResolve() throws {
        let deURL = try XCTUnwrap(
            L10n.bundle.url(forResource: "de", withExtension: "lproj"),
            "de.lproj not found in Bundle.module")
        let de = try XCTUnwrap(Bundle(url: deURL))
        XCTAssertEqual(de.localizedString(forKey: "Welcome", value: "␀", table: nil), "Willkommen")
        XCTAssertEqual(de.localizedString(forKey: "Skip", value: "␀", table: nil), "Überspringen")
        XCTAssertEqual(de.localizedString(forKey: "Next", value: "␀", table: nil), "Weiter")
    }
}
