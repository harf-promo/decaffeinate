import XCTest

@testable import Decaffeinate

final class ScheduleEngineTests: XCTestCase {

    /// A calendar/date pinned to a specific hour so the tests are deterministic.
    private func date(hour: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(
            from: DateComponents(year: 2026, month: 6, day: 21, hour: hour, minute: 30))!
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testWithinDaytimeWindow() {
        XCTAssertTrue(
            ScheduleEngine.isWithinActiveHours(date(hour: 10), start: 9, end: 17, calendar: utc))
        XCTAssertFalse(
            ScheduleEngine.isWithinActiveHours(date(hour: 18), start: 9, end: 17, calendar: utc))
        // End is exclusive.
        XCTAssertTrue(
            ScheduleEngine.isWithinActiveHours(date(hour: 16), start: 9, end: 17, calendar: utc))
    }

    func testOvernightWindowWraps() {
        // 22 → 6 covers late night and early morning, not the afternoon.
        XCTAssertTrue(
            ScheduleEngine.isWithinActiveHours(date(hour: 23), start: 22, end: 6, calendar: utc))
        XCTAssertTrue(
            ScheduleEngine.isWithinActiveHours(date(hour: 2), start: 22, end: 6, calendar: utc))
        XCTAssertFalse(
            ScheduleEngine.isWithinActiveHours(date(hour: 12), start: 22, end: 6, calendar: utc))
    }

    func testDegenerateWindowMatchesNothing() {
        XCTAssertFalse(
            ScheduleEngine.isWithinActiveHours(date(hour: 9), start: 9, end: 9, calendar: utc))
    }

    func testOvernightWindowBoundaries() {
        // 22 → 6, half-open: start hour inside, end hour exclusive even when wrapped.
        XCTAssertTrue(
            ScheduleEngine.isWithinActiveHours(date(hour: 22), start: 22, end: 6, calendar: utc),
            "start hour is inside")
        XCTAssertTrue(
            ScheduleEngine.isWithinActiveHours(date(hour: 5), start: 22, end: 6, calendar: utc),
            "the last hour before end is inside")
        XCTAssertFalse(
            ScheduleEngine.isWithinActiveHours(date(hour: 6), start: 22, end: 6, calendar: utc),
            "end hour is exclusive on the wrapped side")
        XCTAssertFalse(
            ScheduleEngine.isWithinActiveHours(date(hour: 21), start: 22, end: 6, calendar: utc),
            "the hour before start is outside")
    }

    func testHoldReasonOnlyWhenEnabledAndInside() {
        var settings = DecaffeinateSettings()
        settings.activeHoursStart = 9
        settings.activeHoursEnd = 17

        settings.scheduleEnabled = false
        XCTAssertNil(
            ScheduleEngine.activeHoursHoldReason(
                now: date(hour: 10), settings: settings, calendar: utc))

        settings.scheduleEnabled = true
        XCTAssertNotNil(
            ScheduleEngine.activeHoursHoldReason(
                now: date(hour: 10), settings: settings, calendar: utc))
        XCTAssertNil(
            ScheduleEngine.activeHoursHoldReason(
                now: date(hour: 20), settings: settings, calendar: utc))
    }

    func testHourLabel() {
        XCTAssertEqual(ScheduleEngine.hourLabel(0), "12 AM")
        XCTAssertEqual(ScheduleEngine.hourLabel(9), "9 AM")
        XCTAssertEqual(ScheduleEngine.hourLabel(12), "12 PM")
        XCTAssertEqual(ScheduleEngine.hourLabel(17), "5 PM")
        XCTAssertEqual(ScheduleEngine.hourLabel(23), "11 PM")
    }
}
