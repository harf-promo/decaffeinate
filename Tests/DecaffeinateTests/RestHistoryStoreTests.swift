import XCTest

@testable import Decaffeinate

@MainActor
final class RestHistoryStoreTests: XCTestCase {

    private func makeStore() -> (RestHistoryStore, () -> Void) {
        let suite = "decaf.resthistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            RestHistoryStore(defaults: defaults),
            { defaults.removePersistentDomain(forName: suite) }
        )
    }

    func testRecordsNewestFirstAndAccessors() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(RestEvent(date: Date(timeIntervalSince1970: 1), kind: .restart))
        store.record(RestEvent(date: Date(timeIntervalSince1970: 2), kind: .displayOff))
        store.record(RestEvent(date: Date(timeIntervalSince1970: 3), kind: .systemSleep))
        XCTAssertEqual(store.events.first?.kind, .systemSleep)
        XCTAssertEqual(store.lastSystemSleep?.kind, .systemSleep)
        XCTAssertEqual(store.lastDisplayOff?.kind, .displayOff)
        XCTAssertEqual(store.lastRestart?.kind, .restart)
    }

    func testCapsAtFifty() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        for _ in 0..<60 { store.record(RestEvent(date: Date(), kind: .wake)) }
        XCTAssertEqual(store.events.count, 50)
    }

    func testClearAndPersist() {
        let suite = "decaf.resthistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = RestHistoryStore(defaults: defaults)
        a.record(RestEvent(date: Date(), kind: .restart, uptimeSeconds: 1000))
        let b = RestHistoryStore(defaults: defaults)
        XCTAssertEqual(b.events.first?.kind, .restart)
        XCTAssertEqual(b.events.first?.uptimeSeconds, 1000)
        b.clear()
        XCTAssertTrue(RestHistoryStore(defaults: defaults).events.isEmpty)
    }

    func testUnknownKindDecodesToSafeDefault() {
        let json = Data(
            #"[{"id":"00000000-0000-0000-0000-000000000000","date":0,"kind":"futureThing","onBattery":false}]"#
                .utf8)
        let decoded = try? JSONDecoder().decode([RestEvent].self, from: json)
        XCTAssertEqual(decoded?.first?.kind, .systemSleep, "unknown kind degrades, doesn't throw")
    }

    func testCorruptDataDecodesToEmpty() {
        let suite = "decaf.resthistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0xFF, 0x00]), forKey: "DecaffeinateRestHistory.v1")
        XCTAssertTrue(RestHistoryStore(defaults: defaults).events.isEmpty)
    }
}
