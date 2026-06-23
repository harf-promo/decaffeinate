import XCTest

@testable import Decaffeinate

@MainActor
final class SleepHistoryStoreTests: XCTestCase {

    private func makeStore() -> (SleepHistoryStore, () -> Void) {
        let suite = "decaf.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            SleepHistoryStore(defaults: defaults),
            { defaults.removePersistentDomain(forName: suite) }
        )
    }

    func testRecordsNewestFirst() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(
            SleepEvent(date: Date(timeIntervalSince1970: 1), reason: "first", onBattery: false))
        store.record(
            SleepEvent(date: Date(timeIntervalSince1970: 2), reason: "second", onBattery: true))
        XCTAssertEqual(store.events.first?.reason, "second")
        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.batteryCount, 1)
    }

    func testCapsAtFifty() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        for i in 0..<60 {
            store.record(SleepEvent(date: Date(), reason: "#\(i)", onBattery: false))
        }
        XCTAssertEqual(store.events.count, 50)
        XCTAssertEqual(store.events.first?.reason, "#59")
    }

    func testClear() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(SleepEvent(date: Date(), reason: "x", onBattery: false))
        store.clear()
        XCTAssertTrue(store.events.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let suite = "decaf.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = SleepHistoryStore(defaults: defaults)
        a.record(SleepEvent(date: Date(), reason: "persisted", onBattery: true))
        let b = SleepHistoryStore(defaults: defaults)
        XCTAssertEqual(b.events.first?.reason, "persisted")
    }

    func testMeasuredMinutesAsleep_fallsBackTo15PerUnmeasuredEvent() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        // Two events with no measured sleptSeconds → 2 × 15 = 30 min fallback.
        store.record(SleepEvent(date: Date(), reason: "x", onBattery: false))
        store.record(SleepEvent(date: Date(), reason: "y", onBattery: false))
        XCTAssertEqual(store.measuredMinutesAsleep, 30)
    }

    // MARK: Old-schema array persistence

    func testOldSchemaArraySurvivesPersistedRoundTrip() {
        // Simulate data written by v1.9.0 (no sleptSeconds field in any record).
        let suite = "decaf.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldJSON =
            #"[{"id":"A0000000-0000-0000-0000-000000000001","date":978307200,"reason":"idle","onBattery":false}]"#
            .data(using: .utf8)!
        defaults.set(oldJSON, forKey: "DecaffeinateHistory.v1")
        let store = SleepHistoryStore(defaults: defaults)
        XCTAssertEqual(
            store.events.count, 1, "old records must not be wiped by adding sleptSeconds")
        XCTAssertEqual(store.events[0].reason, "idle")
        XCTAssertNil(store.events[0].sleptSeconds, "absent field decodes to nil gracefully")
    }

    // MARK: Wake-duration pairing

    func testRecordWakeDurationPairsUnmatchedEvent() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.record(SleepEvent(date: t0, reason: "idle", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(1200))  // wake 20 min later
        XCTAssertEqual(store.events[0].sleptSeconds ?? 0, 1200, accuracy: 1)
    }

    func testRecordWakeDurationIgnoresEventAfterWakeDate() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // The event is 100 s in the future relative to the wake date.
        store.record(
            SleepEvent(date: t0.addingTimeInterval(100), reason: "future", onBattery: false))
        store.recordWakeDuration(at: t0)  // wake is before the event — nothing eligible
        XCTAssertNil(store.events[0].sleptSeconds, "event after wake date must not be paired")
    }

    func testRecordWakeDurationRespects24HourClamp() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.record(SleepEvent(date: t0, reason: "idle", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(25 * 3600))  // 25 h — implausible
        XCTAssertNil(
            store.events[0].sleptSeconds, "gaps > 24 h exceed the clamp and must be ignored")
    }

    func testRecordWakeDurationPairsOnlyMostRecentUnmatched() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // Record two events; store is newest-first.
        store.record(SleepEvent(date: t0.addingTimeInterval(-1), reason: "older", onBattery: false))
        store.record(SleepEvent(date: t0, reason: "newer", onBattery: false))
        // Wake pairs with the newest unmatched event whose date ≤ wakeDate.
        store.recordWakeDuration(at: t0.addingTimeInterval(600))
        XCTAssertEqual(store.events[0].sleptSeconds ?? 0, 600, accuracy: 1)
        XCTAssertNil(store.events[1].sleptSeconds, "only the newest unmatched event is paired")
    }

    // MARK: measuredMinutesAsleep

    func testMeasuredMinutesAsleep_withActualMeasuredSeconds() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.record(SleepEvent(date: t0, reason: "idle", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(1800))  // 30 min exactly
        XCTAssertEqual(store.measuredMinutesAsleep, 30)
    }

    func testMeasuredMinutesAsleep_mixedMeasuredAndFallback() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // Record two events; wake pairs only the newer one.
        store.record(SleepEvent(date: t0.addingTimeInterval(-1), reason: "older", onBattery: false))
        store.record(SleepEvent(date: t0, reason: "newer", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(1800))  // newer: 30 min measured
        // older: nil → 15 min fallback; total = 30 + 15 = 45.
        XCTAssertEqual(store.measuredMinutesAsleep, 45)
    }

    func testCorruptDataDecodesToEmpty() {
        let suite = "decaf.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0xFF, 0x00, 0x01, 0x02]), forKey: "DecaffeinateHistory.v1")
        let store = SleepHistoryStore(defaults: defaults)
        XCTAssertTrue(store.events.isEmpty, "garbage bytes must decode to an empty log, not crash")
    }

    func testWrongShapeJSONDecodesToEmpty() {
        let suite = "decaf.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("{\"not\":\"an array\"}".utf8), forKey: "DecaffeinateHistory.v1")
        let store = SleepHistoryStore(defaults: defaults)
        XCTAssertTrue(store.events.isEmpty)
    }
}
