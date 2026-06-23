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

    func testMeasuredMinutesAsleep_zeroWhenNoWakesObserved() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        // Two events with no observed wakes → measured minutes = 0 (no fabricated estimate).
        store.record(SleepEvent(date: Date(), reason: "x", onBattery: false))
        store.record(SleepEvent(date: Date(), reason: "y", onBattery: false))
        XCTAssertEqual(store.measuredMinutesAsleep, 0)
    }

    func testUnmeasuredSleepCount() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.record(SleepEvent(date: t0, reason: "a", onBattery: false))
        store.record(SleepEvent(date: t0.addingTimeInterval(-1), reason: "b", onBattery: false))
        XCTAssertEqual(store.unmeasuredSleepCount, 2, "both events start unmeasured")
        // Pair the newer event with a wake; only one should remain unmeasured.
        store.recordWakeDuration(at: t0.addingTimeInterval(600))
        XCTAssertEqual(store.unmeasuredSleepCount, 1)
        XCTAssertEqual(store.measuredMinutesAsleep, 10)
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

    func testRecordWakeDurationRespects4HourClamp() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.record(SleepEvent(date: t0, reason: "idle", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(5 * 3600))  // 5 h — beyond 4 h clamp
        XCTAssertNil(
            store.events[0].sleptSeconds,
            "gaps > 4 h exceed the default clamp and must not be paired")
    }

    func testRecordWakeDurationPairsWithin4HourClamp() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.record(SleepEvent(date: t0, reason: "idle", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(3 * 3600))  // 3 h — within 4 h clamp
        XCTAssertNotNil(store.events[0].sleptSeconds, "3 h gap is within the clamp and must pair")
        XCTAssertEqual(store.events[0].sleptSeconds ?? 0, 3 * 3600, accuracy: 1)
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

    func testMeasuredMinutesAsleep_measuredOnlyIgnoresUnobservedEvent() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // Record two events; wake pairs only the newer one.
        store.record(SleepEvent(date: t0.addingTimeInterval(-1), reason: "older", onBattery: false))
        store.record(SleepEvent(date: t0, reason: "newer", onBattery: false))
        store.recordWakeDuration(at: t0.addingTimeInterval(1800))  // newer: 30 min measured
        // older: nil → excluded from measured total; count = 30 min (no fabricated estimate).
        XCTAssertEqual(store.measuredMinutesAsleep, 30)
        XCTAssertEqual(store.unmeasuredSleepCount, 1)
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
