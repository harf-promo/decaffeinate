import XCTest

@testable import Decaffeinate

@MainActor
final class SettingsStoreTests: XCTestCase {

    private func withSuite(_ body: (UserDefaults) -> Void) {
        let suite = "decaf.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testCorruptBlobFallsBackToDefaults() {
        withSuite { defaults in
            defaults.set(Data([0xFF, 0x00]), forKey: "DecaffeinateSettings.v1")
            let store = SettingsStore(defaults: defaults)
            XCTAssertEqual(store.settings, DecaffeinateSettings(), "garbage decodes to defaults")
        }
    }

    func testHandEditedZeroIdleIsClampedThroughThePersistedPath() {
        withSuite { defaults in
            // Simulate a hand-edited / corrupted blob with idleThresholdMinutes = 0.
            var s = DecaffeinateSettings()
            s.idleThresholdMinutes = 0
            defaults.set(try! JSONEncoder().encode(s), forKey: "DecaffeinateSettings.v1")

            let store = SettingsStore(defaults: defaults)
            XCTAssertEqual(store.settings.idleThresholdMinutes, 0, "stored value is preserved…")
            XCTAssertEqual(
                store.settings.effectiveIdleSeconds(onBattery: false), 60,
                "…but the effective threshold is clamped to ≥ 1 min so it can't force constant sleep"
            )
        }
    }

    func testRoundTripsCustomValues() {
        let suite = "decaf.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = SettingsStore(defaults: defaults)
        a.settings.scheduleEnabled = true
        a.settings.activeHoursStart = 8
        let b = SettingsStore(defaults: defaults)
        XCTAssertTrue(b.settings.scheduleEnabled)
        XCTAssertEqual(b.settings.activeHoursStart, 8)
    }
}
