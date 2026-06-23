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

    // MARK: rowVerdict

    func testRowVerdictUntilProcess() {
        let v = HoldLifetime.untilProcess("npm run build").rowVerdict
        XCTAssertEqual(v.glyph, "checkmark")
        XCTAssertEqual(v.text, "Will sleep when npm run build finishes")
        XCTAssertTrue(v.bounded)
    }

    func testRowVerdictUntilWatchedFinishes() {
        let v = HoldLifetime.untilWatchedFinishes.rowVerdict
        XCTAssertEqual(v.glyph, "checkmark")
        XCTAssertEqual(v.text, "Will sleep when the watched task finishes")
        XCTAssertTrue(v.bounded)
    }

    func testRowVerdictTimedReArmsTrue_agentCase() {
        let v = HoldLifetime.timed(reArms: true).rowVerdict
        XCTAssertEqual(v.glyph, "checkmark")
        // The owner's explicit acceptance: AI agent row must answer "will sleep".
        XCTAssertTrue(
            v.text.contains("agent"),
            "Expected agent-specific copy; got: \(v.text)"
        )
        XCTAssertTrue(v.bounded)
    }

    func testRowVerdictTimedReArmsFalse() {
        let v = HoldLifetime.timed(reArms: false).rowVerdict
        XCTAssertEqual(v.glyph, "checkmark")
        XCTAssertTrue(v.bounded)
        XCTAssertFalse(
            v.text.contains("agent"),
            "Non-agent timed verdict should not mention agent; got: \(v.text)"
        )
    }

    func testRowVerdictIndefinite() {
        let v = HoldLifetime.indefinite.rowVerdict
        XCTAssertEqual(v.glyph, "exclamationmark.triangle")
        XCTAssertFalse(v.bounded)
        let textLower = v.text.lowercased()
        XCTAssertTrue(
            textLower.contains("won\u{2019}t sleep") || textLower.contains("won't sleep"),
            "Indefinite verdict should indicate no automatic sleep; got: \(v.text)"
        )
    }
}
