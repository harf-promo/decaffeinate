import XCTest
@testable import Decaffeinate

final class ModelTests: XCTestCase {

    // MARK: Rule.matches

    func testBundleScopedRuleRequiresBundleMatch() {
        let rule = Rule(bundleIdentifier: "com.example.App",
                        processName: "App",
                        displayName: "App",
                        policy: .allow)
        // Same process name but no bundle id (a daemon) must NOT match.
        XCTAssertFalse(rule.matches(Fixtures.assertion(process: "App", bundle: nil)))
        // Matching bundle id (even with a different process name) matches.
        XCTAssertTrue(rule.matches(Fixtures.assertion(process: "Helper", bundle: "com.example.App")))
        // Different bundle id does not.
        XCTAssertFalse(rule.matches(Fixtures.assertion(process: "App", bundle: "com.other.App")))
    }

    func testBundlelessRuleMatchesByProcessName() {
        let rule = Rule(bundleIdentifier: nil,
                        processName: "node",
                        displayName: "node",
                        policy: .ignore)
        XCTAssertTrue(rule.matches(Fixtures.assertion(process: "NODE", bundle: nil)))
        XCTAssertFalse(rule.matches(Fixtures.assertion(process: "python", bundle: nil)))
    }

    // MARK: Settings clamp

    func testIdleThresholdClampedToAtLeastOneMinute() {
        var s = DecaffeinateSettings()
        s.idleThresholdMinutes = 0
        XCTAssertEqual(s.idleThresholdSeconds, 60, accuracy: 0.001)

        s.idleThresholdMinutes = -5
        XCTAssertEqual(s.idleThresholdSeconds, 60, accuracy: 0.001)

        s.idleThresholdMinutes = 10
        XCTAssertEqual(s.idleThresholdSeconds, 600, accuracy: 0.001)
    }

    // MARK: RulePolicy

    func testRulePolicyAllowanceSemantics() {
        XCTAssertTrue(RulePolicy.allow.isCurrentlyAllowing)
        XCTAssertFalse(RulePolicy.ignore.isCurrentlyAllowing)
        XCTAssertTrue(RulePolicy.allowUntil(Date().addingTimeInterval(60)).isCurrentlyAllowing)
        XCTAssertFalse(RulePolicy.allowUntil(Date().addingTimeInterval(-60)).isCurrentlyAllowing)
    }
}
