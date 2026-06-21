import XCTest

@testable import Decaffeinate

final class TriggerEngineTests: XCTestCase {

    private func signals(
        apps: [String] = [], onAC: Bool = false, cpu: Double = 0
    ) -> TriggerSignals {
        TriggerSignals(
            runningAppNames: Set(apps.map { $0.lowercased() }), onACPower: onAC, cpuPercent: cpu)
    }

    func testNoRulesNeverActive() {
        XCTAssertNil(TriggerEngine.activeReason(rules: [], signals: signals(onAC: true)))
    }

    func testAppRunningMatchesCaseInsensitiveSubstring() {
        let rules = [TriggerRule(condition: .appRunning("Zoom"))]
        XCTAssertNotNil(
            TriggerEngine.activeReason(rules: rules, signals: signals(apps: ["zoom.us"])))
        XCTAssertNil(
            TriggerEngine.activeReason(rules: rules, signals: signals(apps: ["safari"])))
    }

    func testOnACPower() {
        let rules = [TriggerRule(condition: .onACPower)]
        XCTAssertEqual(
            TriggerEngine.activeReason(rules: rules, signals: signals(onAC: true)), "On AC power")
        XCTAssertNil(TriggerEngine.activeReason(rules: rules, signals: signals(onAC: false)))
    }

    func testCpuAboveThreshold() {
        let rules = [TriggerRule(condition: .cpuAbove(50))]
        XCTAssertNotNil(TriggerEngine.activeReason(rules: rules, signals: signals(cpu: 73)))
        XCTAssertNil(TriggerEngine.activeReason(rules: rules, signals: signals(cpu: 20)))
        // Exactly at the threshold is active (>=).
        XCTAssertNotNil(TriggerEngine.activeReason(rules: rules, signals: signals(cpu: 50)))
    }

    func testDisabledRuleIsIgnored() {
        let rules = [TriggerRule(condition: .onACPower, enabled: false)]
        XCTAssertNil(TriggerEngine.activeReason(rules: rules, signals: signals(onAC: true)))
    }

    func testEmptyAppNameNeverMatches() {
        let rules = [TriggerRule(condition: .appRunning(""))]
        XCTAssertNil(
            TriggerEngine.activeReason(rules: rules, signals: signals(apps: ["anything"])))
    }

    func testFirstSatisfiedRuleWins() {
        let rules = [
            TriggerRule(condition: .appRunning("nope")),
            TriggerRule(condition: .onACPower),
        ]
        XCTAssertEqual(
            TriggerEngine.activeReason(rules: rules, signals: signals(onAC: true)), "On AC power")
    }

    func testRuleCodableRoundTrip() throws {
        let rules = [
            TriggerRule(condition: .appRunning("Final Cut Pro")),
            TriggerRule(condition: .onACPower, enabled: false),
            TriggerRule(condition: .cpuAbove(80)),
        ]
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([TriggerRule].self, from: data)
        XCTAssertEqual(decoded, rules)
    }
}
