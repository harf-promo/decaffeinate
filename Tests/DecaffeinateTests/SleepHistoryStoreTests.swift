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

    func testEstimate() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(SleepEvent(date: Date(), reason: "x", onBattery: false))
        store.record(SleepEvent(date: Date(), reason: "y", onBattery: false))
        XCTAssertEqual(store.estimatedMinutesAvoided, 30)
    }
}
