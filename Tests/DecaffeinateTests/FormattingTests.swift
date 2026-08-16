import XCTest

@testable import Decaffeinate

final class FormattingTests: XCTestCase {

    func testCountdown() {
        XCTAssertEqual(Format.countdown(0), "0:00")
        XCTAssertEqual(Format.countdown(5), "0:05")
        XCTAssertEqual(Format.countdown(65), "1:05")
        XCTAssertEqual(Format.countdown(600), "10:00")
        XCTAssertEqual(Format.countdown(-30), "0:00")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(5), "5s")
        XCTAssertEqual(Format.duration(65), "1m")
        XCTAssertEqual(Format.duration(3700), "1h 1m")
    }

    func testRelative() {
        let now = Date()
        XCTAssertEqual(
            Format.relative(since: now.addingTimeInterval(-3), now: now),
            L10n.localized("just now"))
        XCTAssertEqual(
            Format.relative(since: now.addingTimeInterval(-30), now: now),
            L10n.localized("%ds ago", 30))
        XCTAssertEqual(
            Format.relative(since: now.addingTimeInterval(-120), now: now),
            L10n.localized("%dm ago", 2))
        XCTAssertEqual(
            Format.relative(since: now.addingTimeInterval(-7200), now: now),
            L10n.localized("%dh ago", 2))
        XCTAssertEqual(
            Format.relative(since: now.addingTimeInterval(-172_800), now: now),
            L10n.localized("%dd ago", 2))
        XCTAssertEqual(
            Format.relative(since: now.addingTimeInterval(-1_209_600), now: now),
            L10n.localized("%dwk ago", 2))
    }

    func testRemovingDuplicates() {
        XCTAssertEqual([1, 1, 2, 3, 2, 1].removingDuplicates(), [1, 2, 3])
        XCTAssertEqual(["a", "b", "a"].removingDuplicates(), ["a", "b"])
    }

    func testAssertionClassification() {
        XCTAssertEqual(AssertionType.classify("PreventUserIdleSystemSleep"), .systemSleep)
        XCTAssertEqual(AssertionType.classify("PreventSystemSleep"), .systemSleep)
        XCTAssertEqual(AssertionType.classify("PreventUserIdleDisplaySleep"), .displaySleep)
        XCTAssertEqual(AssertionType.classify("NetworkClientActive"), .other)
    }

    func testBlocksSystemSleepFlag() {
        XCTAssertTrue(Fixtures.assertion(type: "PreventUserIdleSystemSleep").blocksSystemSleep)
        XCTAssertFalse(Fixtures.assertion(type: "PreventUserIdleDisplaySleep").blocksSystemSleep)
    }
}
