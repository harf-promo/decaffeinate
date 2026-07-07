import XCTest

@testable import Decaffeinate

final class WakeReasonParserTests: XCTestCase {

    func testFriendlyMapsCommonCauses() {
        XCTAssertEqual(WakeReasonParser.friendly("EC.LidOpen/Lid Open"), "You opened the lid")
        XCTAssertEqual(WakeReasonParser.friendly("EC.PowerButton/Power Button"), "Power button")
        XCTAssertEqual(WakeReasonParser.friendly("RTC Alarm"), "Scheduled wake")
        XCTAssertEqual(WakeReasonParser.friendly("HID Activity"), "Keyboard or trackpad")
        XCTAssertEqual(
            WakeReasonParser.friendly("WoW: Magic Packet"), "Network (Wake on LAN)")
    }

    func testExtractsDueToCauseAndTrimsPowerNote() {
        let line =
            "2026-07-06 23:41:02 -0500 Wake                   \tWake from Standby [CDNVA] : due to EC.LidOpen/HID Activity Using AC (Charge:82%)"
        XCTAssertEqual(WakeReasonParser.dueToCause(line), "EC.LidOpen/HID Activity")
    }

    func testLatestWakeReasonPicksTheMostRecentWakeLine() {
        let log = """
            2026-07-05 22:00:01 -0500 Sleep                  \tEntering Sleep state due to 'Idle Sleep'
            2026-07-06 03:00:00 -0500 Wake                   \tWake from Normal Sleep [CDNVA] : due to RTC Alarm Using Batt
            2026-07-06 08:15:33 -0500 Wake                   \tWake [CDNVA] : due to EC.LidOpen/Lid Open Using AC
            """
        // The most recent wake is the lid-open one.
        XCTAssertEqual(WakeReasonParser.latestWakeReason(from: log), "You opened the lid")
    }

    func testNoWakeLineReturnsNil() {
        let log = """
            2026-07-05 22:00:01 -0500 Sleep                  \tEntering Sleep state due to 'Idle Sleep'
            2026-07-05 22:00:02 -0500 Assertions             \tPID 42 created assertion
            """
        XCTAssertNil(WakeReasonParser.latestWakeReason(from: log))
    }

    func testEmptyInputIsSafe() {
        XCTAssertNil(WakeReasonParser.latestWakeReason(from: ""))
        XCTAssertNil(WakeReasonParser.dueToCause("Wake with no cause here"))
    }
}
