import XCTest

@testable import Decaffeinate

/// Covers the pure logic behind the automation surface (App Intents + URL scheme).
/// The `perform()` bodies are one-line shells over `AppState`/engine methods that
/// are already tested elsewhere; the testable substance is here.
final class AppIntentsTests: XCTestCase {

    private let nothingAwake = AwakeSummary(
        spoken: "Nothing is keeping your Mac awake.", items: [])

    // MARK: AwakeReport.summarize

    func testAwakeReportEmptyWhenNothingBlocks() {
        XCTAssertEqual(AwakeReport.summarize([]), nothingAwake)
    }

    func testAwakeReportSingleSystemBlocker() {
        let a = Fixtures.assertion(
            process: "Chrome", bundle: nil, type: AssertionType.preventUserIdleSystemSleep)
        let summary = AwakeReport.summarize([a])
        XCTAssertEqual(summary.items.count, 1)
        XCTAssertTrue(summary.items[0].hasPrefix("Chrome — "), "items list name — why")
        XCTAssertTrue(summary.spoken.contains("Chrome"))
        XCTAssertTrue(summary.spoken.contains("is keeping your Mac awake"))
    }

    func testAwakeReportExcludesDisplayOnlyAssertions() {
        // A display-sleep hold (media/call) does not block *system* sleep.
        let displayOnly = Fixtures.assertion(
            process: "QuickTime", bundle: nil, type: AssertionType.preventUserIdleDisplaySleep)
        XCTAssertEqual(AwakeReport.summarize([displayOnly]), nothingAwake)
    }

    func testAwakeReportMultipleDeDupesNamesButListsAll() {
        let sys = AssertionType.preventUserIdleSystemSleep
        let a = Fixtures.assertion(pid: 1, process: "Chrome", bundle: nil, type: sys)
        let b = Fixtures.assertion(pid: 2, process: "Xcode", bundle: nil, type: sys)
        // A second Chrome hold — must collapse to one *name* in the spoken summary.
        let c = Fixtures.assertion(pid: 3, process: "Chrome", bundle: nil, type: sys)
        let summary = AwakeReport.summarize([a, b, c])
        XCTAssertEqual(summary.items.count, 3, "every blocker is listed in items")
        XCTAssertTrue(
            summary.spoken.hasPrefix("2 things are keeping your Mac awake"),
            "names de-dup: Chrome + Xcode = 2 — got: \(summary.spoken)")
    }

    // MARK: KeepAwakePreset

    func testKeepAwakePresetMinutes() {
        XCTAssertEqual(KeepAwakePreset.fifteen.minutes, 15)
        XCTAssertEqual(KeepAwakePreset.thirty.minutes, 30)
        XCTAssertEqual(KeepAwakePreset.sixty.minutes, 60)
        XCTAssertEqual(KeepAwakePreset.oneTwenty.minutes, 120)
    }

    // MARK: AutomationURL.parse

    private func parse(_ string: String) -> AutomationURL.Action? {
        AutomationURL.parse(URL(string: string)!)
    }

    func testAutomationURLSleepNow() {
        XCTAssertEqual(parse("decaffeinate://sleep-now"), .sleepNow)
    }

    func testAutomationURLStopAwake() {
        XCTAssertEqual(parse("decaffeinate://stop-awake"), .stopAwake)
    }

    func testAutomationURLKeepAwakeWithMinutes() {
        XCTAssertEqual(parse("decaffeinate://keep-awake?minutes=45"), .keepAwake(minutes: 45))
    }

    func testAutomationURLKeepAwakeDefaultsTo30() {
        XCTAssertEqual(parse("decaffeinate://keep-awake"), .keepAwake(minutes: 30))
    }

    func testAutomationURLKeepAwakeClampsRange() {
        XCTAssertEqual(parse("decaffeinate://keep-awake?minutes=0"), .keepAwake(minutes: 1))
        XCTAssertEqual(parse("decaffeinate://keep-awake?minutes=99999"), .keepAwake(minutes: 1440))
    }

    func testAutomationURLRejectsUnknownVerbAndWrongScheme() {
        XCTAssertNil(parse("decaffeinate://frobnicate"))
        XCTAssertNil(parse("https://sleep-now"))
    }
}
