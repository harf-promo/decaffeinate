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

    // v1.25 "Fluent": proof that the v1.25 sweep's newly-wired keys — spanning
    // the menu, Settings, the SleepOutlook verdict source, notifications, and
    // the CLI — actually resolve to real German values in Bundle.module,
    // covering both plain keys and the format-string keys used for dynamic
    // copy (interpolated via `L10n.localized(_:_:)` / `String(format:)`).
    func testV125NewKeysResolveInGerman() throws {
        let deURL = try XCTUnwrap(
            L10n.bundle.url(forResource: "de", withExtension: "lproj"),
            "de.lproj not found in Bundle.module")
        let de = try XCTUnwrap(Bundle(url: deURL))
        func localized(_ key: String) -> String {
            de.localizedString(forKey: key, value: "␀", table: nil)
        }

        // Views/MenuRedesign.swift
        XCTAssertEqual(localized("Sleep Now"), "Jetzt schlafen")
        XCTAssertEqual(localized("Settings"), "Einstellungen")
        XCTAssertEqual(localized("Cancel"), "Abbrechen")

        // Views/SettingsView.swift (General + Notifications panes)
        XCTAssertEqual(localized("Auto-sleep when left idle"), "Automatisch schlafen bei Leerlauf")
        XCTAssertEqual(localized("General"), "Allgemein")

        // Core/SleepOutlook.swift — plain and format-string keys
        XCTAssertEqual(localized("Free to sleep"), "Kann schlafen")
        XCTAssertEqual(
            String(format: localized("Your Mac will sleep %@"), "in ~10 Min."),
            "Dein Mac schläft in ~10 Min.")

        // Core/ReasonEngine.swift
        XCTAssertEqual(localized("Microphone in use"), "Mikrofon in Benutzung")

        // Core/Notifier.swift — a format-string notification template
        XCTAssertEqual(
            String(format: localized("%@ is keeping your Mac awake"), "Zoom"),
            "Zoom hält deinen Mac wach")

        // Core/CLI.swift — human CLI output (never the JSON contract)
        XCTAssertEqual(localized("USAGE:"), "VERWENDUNG:")
        XCTAssertEqual(
            String(format: localized("This Mac is free to sleep. Idle %ds."), 42),
            "Dieser Mac kann schlafen. Leerlauf 42s.")

        // Views/ClamshellAssistantView.swift
        XCTAssertEqual(localized("Arm clamshell session"), "Clamshell-Sitzung aktivieren")
    }
}
