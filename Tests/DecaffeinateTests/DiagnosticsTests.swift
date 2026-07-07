import XCTest

@testable import Decaffeinate

final class DiagnosticsTests: XCTestCase {

    private func snapshot(
        settings: DecaffeinateSettings = DecaffeinateSettings(),
        rules: [Rule] = [],
        blockers: [PowerAssertion] = []
    ) -> Diagnostics.Snapshot {
        Diagnostics.Snapshot(
            version: "1.16.0",
            macOSVersion: "Version 15.0",
            model: "MacTest1,1",
            generatedAt: Date(timeIntervalSince1970: 1_000_000),
            settings: settings,
            rules: rules,
            power: PowerSnapshot(onBattery: true, charge: 0.42, isCharging: false),
            thermal: .nominal,
            idleSeconds: 90,
            uptimeSeconds: 3 * 86_400,
            stateHeadline: "Free to sleep",
            stateDetail: "Sleeps ~10 min after you step away",
            systemBlockers: blockers,
            otherAssertions: [])
    }

    func testReportCapturesTheSettingsCombination() {
        var s = DecaffeinateSettings()
        s.caffeinateEnabled = true
        s.strictTakeoverMode = true
        s.batteryFloorPercent = 25
        let report = Diagnostics.report(snapshot(settings: s))

        // The header + state.
        XCTAssertTrue(report.contains("# Decaffeinate diagnostics"))
        XCTAssertTrue(report.contains("Version: 1.16.0"))
        XCTAssertTrue(report.contains("MacTest1,1"))
        XCTAssertTrue(report.contains("battery 42%"))
        // The settings *combination* that a bare --scan can't show.
        XCTAssertTrue(report.contains("keep-awake (caffeinateEnabled): true"), report)
        XCTAssertTrue(report.contains("strict takeover: true"), report)
        XCTAssertTrue(report.contains("battery floor: 25%"), report)
    }

    func testReportListsRulesAndBlockers() {
        let rule = Rule(
            bundleIdentifier: "us.zoom.xos", processName: "zoom.us", displayName: "Zoom",
            policy: .allow)
        let blocker = Fixtures.assertion(process: "Zoom", bundle: "us.zoom.xos")
        let report = Diagnostics.report(snapshot(rules: [rule], blockers: [blocker]))
        XCTAssertTrue(report.contains("App sleep rules (1)"), report)
        XCTAssertTrue(report.contains("Zoom"), report)
        XCTAssertTrue(report.contains("Holding system sleep (1)"), report)
    }

    func testReportSanitizesFreeText() {
        // A malicious assertion name with an ANSI escape must not survive into the
        // report (it's shared/pasted). displayName falls back to process name here.
        let evil = Fixtures.assertion(
            process: "Ann\u{1B}[31moying", bundle: nil, name: "x")
        let report = Diagnostics.report(snapshot(blockers: [evil]))
        XCTAssertFalse(report.contains("\u{1B}"), "escape sequences must be stripped")
    }
}
