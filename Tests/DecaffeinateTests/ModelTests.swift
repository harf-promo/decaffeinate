import XCTest

@testable import Decaffeinate

final class ModelTests: XCTestCase {

    // MARK: Settings migration (resilient decode)

    func testSettingsDecodeKeepsDefaultsForMissingKeys() throws {
        // Simulate JSON persisted by an older version that lacks the newer keys.
        let oldJSON = #"{"caffeinateEnabled":true,"batteryFloorPercent":5}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(DecaffeinateSettings.self, from: oldJSON)
        // Present keys are honored…
        XCTAssertTrue(s.caffeinateEnabled)
        XCTAssertEqual(s.batteryFloorPercent, 5)
        // …and every absent key keeps its default (no wipe).
        XCTAssertTrue(s.decaffeinateEnabled)
        XCTAssertEqual(s.idleThresholdMinutes, 10, accuracy: 0.001)
        XCTAssertFalse(s.autoSleepWhenAgentFinishes)
        XCTAssertFalse(s.hasSeenAwakeExplainer)
        XCTAssertEqual(s.restartRecommendationDays, 7)
    }

    func testSettingsRoundTrip() throws {
        var s = DecaffeinateSettings()
        s.autoSleepWhenAgentFinishes = true
        s.idleThresholdMinutes = 25
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(DecaffeinateSettings.self, from: data), s)
    }

    // MARK: Rule.matches

    func testBundleScopedRuleRequiresBundleMatch() {
        let rule = Rule(
            bundleIdentifier: "com.example.App",
            processName: "App",
            displayName: "App",
            policy: .allow)
        // Same process name but no bundle id (a daemon) must NOT match.
        XCTAssertFalse(rule.matches(Fixtures.assertion(process: "App", bundle: nil)))
        // Matching bundle id (even with a different process name) matches.
        XCTAssertTrue(
            rule.matches(Fixtures.assertion(process: "Helper", bundle: "com.example.App")))
        // Different bundle id does not.
        XCTAssertFalse(rule.matches(Fixtures.assertion(process: "App", bundle: "com.other.App")))
    }

    func testRuleMatchesAttributedRealOwner() {
        // A rule keyed on the real app (Safari) should match a hold whose direct
        // owner is a shared daemon but whose realOwner is Safari.
        let rule = Rule(
            bundleIdentifier: "com.apple.Safari", processName: "Safari",
            displayName: "Safari", policy: .allow)
        let daemonHold = Fixtures.assertion(
            process: "runningboardd", bundle: nil,
            realOwner: AssertionOwner(name: "Safari", bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(rule.matches(daemonHold))

        // And it should NOT match an unrelated daemon hold.
        let other = Fixtures.assertion(
            process: "runningboardd", bundle: nil,
            realOwner: AssertionOwner(name: "Music", bundleIdentifier: "com.apple.Music"))
        XCTAssertFalse(rule.matches(other))
    }

    func testBundlelessRuleMatchesByProcessName() {
        let rule = Rule(
            bundleIdentifier: nil,
            processName: "node",
            displayName: "node",
            policy: .ignore)
        XCTAssertTrue(rule.matches(Fixtures.assertion(process: "NODE", bundle: nil)))
        XCTAssertFalse(rule.matches(Fixtures.assertion(process: "python", bundle: nil)))
    }

    // MARK: Resilient decoding — decode-survival for added / renamed fields

    func testSleepEventOldSchemaDecodesSurvives() throws {
        // JSON written by v1.9.0: no `sleptSeconds` field.
        let json =
            #"[{"id":"A0000000-0000-0000-0000-000000000001","date":978307200,"reason":"idle","onBattery":false}]"#
            .data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let events = try decoder.decode([SleepEvent].self, from: json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].reason, "idle")
        XCTAssertNil(
            events[0].sleptSeconds,
            "absent sleptSeconds must decode to nil, not crash the whole array")
    }

    func testRuleOldSchemaDefaultsToPolicyIgnore() throws {
        // Old JSON missing the policy field — must never silently grant .allow.
        let json =
            #"{"id":"A0000000-0000-0000-0000-000000000002","bundleIdentifier":"com.example.App","processName":"App","displayName":"My App"}"#
            .data(using: .utf8)!
        let rule = try JSONDecoder().decode(Rule.self, from: json)
        XCTAssertEqual(rule.policy, .ignore, "absent policy must default to .ignore — never .allow")
    }

    func testRestEventOldSchemaDecodesSurvives() throws {
        // Old JSON without uptimeSeconds (added alongside the Rest & Restart pillar).
        let json =
            #"{"id":"A0000000-0000-0000-0000-000000000003","date":978307200,"kind":"systemSleep","onBattery":false}"#
            .data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let event = try decoder.decode(RestEvent.self, from: json)
        XCTAssertEqual(event.kind, .systemSleep)
        XCTAssertNil(event.uptimeSeconds, "absent uptimeSeconds must decode to nil, not a crash")
    }

    func testRestEventUnknownKindDegradesToSystemSleep() throws {
        // A future `kind` string that this binary doesn't know about must not crash
        // the entire rest-history array.
        let json =
            #"{"id":"A0000000-0000-0000-0000-000000000004","date":978307200,"kind":"futureKindXYZ","onBattery":true}"#
            .data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let event = try decoder.decode(RestEvent.self, from: json)
        XCTAssertEqual(
            event.kind, .systemSleep, "unknown kind string must degrade to .systemSleep")
    }

    // MARK: Settings clamp

    func testIdleThresholdClampedToAtLeastOneMinute() {
        var s = DecaffeinateSettings()
        s.idleThresholdMinutes = 0
        XCTAssertEqual(s.effectiveIdleSeconds(onBattery: false), 60, accuracy: 0.001)

        s.idleThresholdMinutes = -5
        XCTAssertEqual(s.effectiveIdleSeconds(onBattery: false), 60, accuracy: 0.001)

        s.idleThresholdMinutes = 10
        XCTAssertEqual(s.effectiveIdleSeconds(onBattery: false), 600, accuracy: 0.001)
    }

    // MARK: RulePolicy

    func testAllowDurationExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AllowDuration.thirtyMinutes.expiry(from: now), now.addingTimeInterval(1800))
        XCTAssertEqual(AllowDuration.oneHour.expiry(from: now), now.addingTimeInterval(3600))
        XCTAssertEqual(AllowDuration.fourHours.expiry(from: now), now.addingTimeInterval(14_400))
        // Until tomorrow is strictly later than now.
        XCTAssertGreaterThan(AllowDuration.untilTomorrow.expiry(from: now), now)
        XCTAssertEqual(AllowDuration.allCases.count, 4)
    }

    func testRulePolicyAllowanceSemantics() {
        XCTAssertTrue(RulePolicy.allow.isCurrentlyAllowing)
        XCTAssertFalse(RulePolicy.ignore.isCurrentlyAllowing)
        XCTAssertTrue(RulePolicy.allowUntil(Date().addingTimeInterval(60)).isCurrentlyAllowing)
        XCTAssertFalse(RulePolicy.allowUntil(Date().addingTimeInterval(-60)).isCurrentlyAllowing)
    }
}
