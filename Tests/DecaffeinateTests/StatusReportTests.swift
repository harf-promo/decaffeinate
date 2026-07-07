import XCTest

@testable import Decaffeinate

final class StatusReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testExcludesOwnPidAndCountsSystemHolds() {
        let mine = Fixtures.assertion(pid: 999, process: "Decaffeinate")
        let chrome = Fixtures.assertion(
            pid: 100, process: "Chrome", type: AssertionType.preventUserIdleSystemSleep)
        let report = StatusReport.from(
            version: "1.17.0", now: now, ownPID: 999,
            assertions: [mine, chrome],
            power: PowerSnapshot(onBattery: true, charge: 0.5, isCharging: false),
            thermal: .nominal, idleSeconds: 42, uptimeSeconds: 86_400)

        XCTAssertEqual(report.blockers.count, 1, "own-pid hold is excluded")
        XCTAssertEqual(report.blockers.first?.app, "Chrome")
        XCTAssertEqual(report.holdingSystemSleep, 1)
        XCTAssertEqual(report.batteryPercent, 50)
        XCTAssertEqual(report.idleSeconds, 42)
    }

    func testJSONIsStableAndParsable() {
        let report = StatusReport.from(
            version: "1.17.0", now: now, ownPID: -1,
            assertions: [], power: .unknown, thermal: .nominal, idleSeconds: 0, uptimeSeconds: nil)
        let json = report.jsonString()
        // Round-trips through Codable → the shape is stable for consumers.
        let decoded = try! JSONDecoder().decode(
            StatusReport.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, report)
        XCTAssertTrue(json.contains("\"holdingSystemSleep\" : 0"))
    }

    func testFreeToSleepWhenNothingHolds() {
        let report = StatusReport.from(
            version: "1.17.0", now: now, ownPID: -1,
            assertions: [], power: .unknown, thermal: .nominal, idleSeconds: 0, uptimeSeconds: nil)
        XCTAssertEqual(report.holdingSystemSleep, 0)
        XCTAssertTrue(report.blockers.isEmpty)
    }
}
