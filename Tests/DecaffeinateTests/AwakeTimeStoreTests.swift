import XCTest

@testable import Decaffeinate

@MainActor
final class AwakeTimeStoreTests: XCTestCase {

    private func makeStore(calendar: Calendar = .current) -> (AwakeTimeStore, () -> Void) {
        let suite = "decaf.awaketime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            AwakeTimeStore(defaults: defaults, calendar: calendar),
            { defaults.removePersistentDomain(forName: suite) }
        )
    }

    // MARK: Accumulation

    func testRecordAccumulatesWithinTheSameDay() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(appName: "Zoom", seconds: 30, date: t0)
        store.record(appName: "Zoom", seconds: 45, date: t0.addingTimeInterval(30))
        XCTAssertEqual(store.entries.count, 1, "same app, same day merges into one entry")
        XCTAssertEqual(store.entries[0].seconds, 75, accuracy: 0.01)
    }

    func testRecordKeepsDistinctAppsSeparate() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(appName: "Zoom", seconds: 30, date: t0)
        store.record(appName: "Google Chrome", seconds: 20, date: t0)
        XCTAssertEqual(store.entries.count, 2)
    }

    func testRecordIgnoresNonPositiveDuration() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(appName: "Zoom", seconds: 0, date: Date())
        store.record(appName: "Zoom", seconds: -5, date: Date())
        XCTAssertTrue(
            store.entries.isEmpty, "a non-positive duration must not create a phantom entry")
    }

    func testRecordIgnoresEmptyAppName() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(appName: "", seconds: 30, date: Date())
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: Day bucketing

    func testRecordBucketsByCalendarDay() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let calendar = Calendar.current
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        store.record(appName: "Zoom", seconds: 30, date: today)
        store.record(appName: "Zoom", seconds: 40, date: yesterday)
        XCTAssertEqual(store.entries.count, 2, "same app on different days stays as two entries")
        XCTAssertEqual(store.entries.reduce(0) { $0 + $1.seconds }, 70, accuracy: 0.01)
    }

    func testRecordTruncatesToStartOfDay() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let calendar = Calendar.current
        let morning = calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_700_000_000))!
        let evening = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: morning)!
        store.record(appName: "Zoom", seconds: 30, date: morning)
        store.record(appName: "Zoom", seconds: 40, date: evening)
        XCTAssertEqual(
            store.entries.count, 1,
            "different times of the same calendar day still merge into one entry")
        XCTAssertEqual(store.entries[0].seconds, 70, accuracy: 0.01)
    }

    // MARK: Pruning

    func testOldEntriesArePruned() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let longAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        store.record(appName: "OldApp", seconds: 30, date: longAgo)
        store.record(appName: "Zoom", seconds: 30, date: now)
        XCTAssertEqual(store.entries.count, 1, "entries far beyond the retention window are pruned")
        XCTAssertEqual(store.entries[0].appName, "Zoom")
    }

    func testRecentEntriesSurviveSubsequentRecords() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        store.record(appName: "Zoom", seconds: 30, date: threeDaysAgo)
        store.record(appName: "Chrome", seconds: 30, date: now)
        XCTAssertEqual(store.entries.count, 2, "an entry within the retention window must survive")
    }

    // MARK: Weekly ranking

    func testWeeklyRankingSortsDescending() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(appName: "Zoom", seconds: 100, date: now)
        store.record(appName: "Chrome", seconds: 500, date: now)
        store.record(appName: "Slack", seconds: 300, date: now)
        let ranking = store.weeklyRanking(now: now)
        XCTAssertEqual(ranking.map(\.appName), ["Chrome", "Slack", "Zoom"])
        XCTAssertEqual(ranking.map(\.seconds), [500, 300, 100])
    }

    func testWeeklyRankingSumsAcrossDaysWithinTheWeek() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        store.record(appName: "Zoom", seconds: 100, date: now)
        store.record(appName: "Zoom", seconds: 200, date: twoDaysAgo)
        let ranking = store.weeklyRanking(now: now)
        XCTAssertEqual(ranking.count, 1)
        XCTAssertEqual(ranking[0].seconds, 300, accuracy: 0.01)
    }

    func testWeeklyRankingExcludesEntriesOlderThanAWeek() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: now)!
        store.record(appName: "OldApp", seconds: 100, date: eightDaysAgo)
        store.record(appName: "Zoom", seconds: 50, date: now)
        let ranking = store.weeklyRanking(now: now)
        XCTAssertEqual(ranking.map(\.appName), ["Zoom"], "an entry older than 7 days must not rank")
    }

    func testWeeklyRankingRespectsLimit() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<12 {
            store.record(appName: "App\(i)", seconds: Double(i + 1), date: now)
        }
        let ranking = store.weeklyRanking(now: now, limit: 5)
        XCTAssertEqual(ranking.count, 5)
        // Highest seconds (App11..App7) should be the top 5.
        XCTAssertEqual(ranking.map(\.appName), ["App11", "App10", "App9", "App8", "App7"])
    }

    func testWeeklyRankingEmptyWhenNoEntries() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        XCTAssertTrue(store.weeklyRanking().isEmpty)
    }

    // MARK: Clear

    func testClear() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        store.record(appName: "Zoom", seconds: 30, date: Date())
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: Persistence

    func testPersistsAcrossInstances() {
        let suite = "decaf.awaketime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = AwakeTimeStore(defaults: defaults)
        a.record(appName: "Zoom", seconds: 42, date: Date())
        let b = AwakeTimeStore(defaults: defaults)
        XCTAssertEqual(b.entries.count, 1)
        XCTAssertEqual(b.entries[0].appName, "Zoom")
        XCTAssertEqual(b.entries[0].seconds, 42, accuracy: 0.01)
    }

    func testCorruptDataDecodesToEmpty() {
        let suite = "decaf.awaketime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0xFF, 0x00, 0x01, 0x02]), forKey: "DecaffeinateAwakeTime.v1")
        let store = AwakeTimeStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty, "garbage bytes must decode to an empty log, not crash")
    }

    func testMissingFieldsDecodeWithSafeDefaults() {
        let suite = "decaf.awaketime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // Simulate a future/partial record shape missing `seconds`.
        let oldJSON = #"[{"day":1700000000,"appName":"Zoom"}]"#.data(using: .utf8)!
        defaults.set(oldJSON, forKey: "DecaffeinateAwakeTime.v1")
        let store = AwakeTimeStore(defaults: defaults)
        XCTAssertEqual(
            store.entries.count, 1, "a record missing a field must not fail the whole array")
        XCTAssertEqual(store.entries[0].appName, "Zoom")
        XCTAssertEqual(store.entries[0].seconds, 0, "a missing field decodes to its safe default")
    }
}
