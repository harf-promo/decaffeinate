import XCTest

@testable import Decaffeinate

final class RestartAdvisorTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testFreshUnderWindow() {
        XCTAssertEqual(RestartAdvisor.advice(uptime: 3 * day, recommendAfterDays: 7), .fresh)
    }

    func testConsiderAtAndPastWindow() {
        XCTAssertEqual(RestartAdvisor.advice(uptime: 7 * day, recommendAfterDays: 7), .consider)
        XCTAssertEqual(RestartAdvisor.advice(uptime: 8 * day, recommendAfterDays: 7), .consider)
    }

    func testOverdueAtDoubleWindow() {
        XCTAssertEqual(RestartAdvisor.advice(uptime: 14 * day, recommendAfterDays: 7), .overdue)
    }

    func testUrgentApproachingCliff() {
        XCTAssertEqual(RestartAdvisor.advice(uptime: 46 * day, recommendAfterDays: 7), .urgent)
    }

    func testUrgentBeatsWindowMath() {
        // Even a long custom window can't suppress the ~49-day networking cliff.
        XCTAssertEqual(RestartAdvisor.advice(uptime: 47 * day, recommendAfterDays: 30), .urgent)
    }

    func testShortWindowForLowRAM() {
        XCTAssertEqual(RestartAdvisor.advice(uptime: 4 * day, recommendAfterDays: 3), .consider)
    }

    func testUptimeLabel() {
        XCTAssertEqual(RestartAdvisor.uptimeLabel(9 * day), "9 days")
        XCTAssertEqual(RestartAdvisor.uptimeLabel(day), "1 day")
        XCTAssertEqual(RestartAdvisor.uptimeLabel(3 * 3_600), "3 hours")
        XCTAssertEqual(RestartAdvisor.uptimeLabel(90), "1 min")
    }

    func testDaysSinceBoot() {
        XCTAssertEqual(RestartAdvisor.daysSinceBoot(9 * day + 3_600), 9)
    }

    func testMessageAndReasonNonEmptyForEachLevel() {
        for advice in RestartAdvice.allCases {
            XCTAssertFalse(RestartAdvisor.message(advice, uptimeLabel: "9 days").isEmpty)
            XCTAssertFalse(RestartAdvisor.reason(advice).isEmpty)
        }
    }
}
