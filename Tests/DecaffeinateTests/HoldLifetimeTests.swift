import XCTest

@testable import Decaffeinate

final class HoldLifetimeTests: XCTestCase {

    func testBadgeLabels() {
        XCTAssertEqual(HoldLifetime.untilProcess("npm").badgeLabel, "until done")
        XCTAssertEqual(HoldLifetime.untilWatchedFinishes.badgeLabel, "until done")
        XCTAssertEqual(HoldLifetime.timed(reArms: true).badgeLabel, "timed")
        XCTAssertEqual(HoldLifetime.timed(reArms: false).badgeLabel, "timed")
        XCTAssertEqual(HoldLifetime.indefinite.badgeLabel, "indefinite")
    }

    func testDetailLabels() {
        XCTAssertEqual(
            HoldLifetime.untilProcess("npm run build").detailLabel, "When npm run build finishes")
        XCTAssertEqual(
            HoldLifetime.untilWatchedFinishes.detailLabel, "When the watched task finishes")
        XCTAssertEqual(
            HoldLifetime.timed(reArms: true).detailLabel, "On a timer (re-arms automatically)")
        XCTAssertEqual(HoldLifetime.timed(reArms: false).detailLabel, "On a timer")
        XCTAssertEqual(HoldLifetime.indefinite.detailLabel, "No timeout — held until released")
    }

    func testIsBounded() {
        XCTAssertTrue(HoldLifetime.untilProcess("x").isBounded)
        XCTAssertTrue(HoldLifetime.untilWatchedFinishes.isBounded)
        XCTAssertTrue(HoldLifetime.timed(reArms: false).isBounded)
        XCTAssertFalse(HoldLifetime.indefinite.isBounded)
    }

    // Row verdicts moved to SleepOutlookTests (they now depend on the outlook, so a
    // hold reads differently when the engine will vs won't override it).
}
