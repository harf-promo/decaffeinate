import XCTest

@testable import Decaffeinate

/// The single verdict model. Pure over `SleepOutlookInputs`, so no `AppState`.
final class SleepOutlookTests: XCTestCase {

    private func inputs(
        decaffeinateEnabled: Bool = true,
        caffeinateActive: Bool = false,
        caffeinateKeepsDisplayAwake: Bool = false,
        decision: SafetyDecision = SafetyDecision(),
        isQuietWindowActive: Bool = false,
        quietWindowHoldingAwake: Bool = false,
        quietUntil: Date? = nil,
        triggerReason: String? = nil,
        idleMinutes: Int = 10,
        batteryNote: Bool = false,
        idleSeconds: TimeInterval = 0,
        agentFinished: Bool = false,
        remainingSeconds: TimeInterval? = nil,
        activeHoldingCount: Int = 0
    ) -> SleepOutlookInputs {
        SleepOutlookInputs(
            decaffeinateEnabled: decaffeinateEnabled, caffeinateActive: caffeinateActive,
            caffeinateKeepsDisplayAwake: caffeinateKeepsDisplayAwake, decision: decision,
            isQuietWindowActive: isQuietWindowActive,
            quietWindowHoldingAwake: quietWindowHoldingAwake,
            quietUntil: quietUntil, triggerReason: triggerReason, idleMinutes: idleMinutes,
            batteryNote: batteryNote, idleSeconds: idleSeconds, agentFinished: agentFinished,
            remainingSeconds: remainingSeconds, activeHoldingCount: activeHoldingCount)
    }

    // MARK: The six primary states

    func testFreeToSleep() {
        let o = SleepOutlook.classify(inputs())
        XCTAssertEqual(o, .freeToSleep(idleMinutes: 10, batteryNote: false))
        XCTAssertEqual(o.headline, "Free to sleep")
        XCTAssertTrue(o.subline.contains("~10 min"))
        XCTAssertEqual(o.severity, .calm)
        XCTAssertEqual(o.mug, .free)
        XCTAssertNil(o.banner(hasHolds: false, anyIndefinite: false))
    }

    func testWillSleepAfterIdle_theReframe() {
        let o = SleepOutlook.classify(inputs(activeHoldingCount: 2))
        guard case .willSleepAfterIdle = o else { return XCTFail("got \(o)") }
        XCTAssertTrue(o.headline.hasPrefix("Your Mac will sleep"), o.headline)
        XCTAssertFalse(o.headline.lowercased().contains("keeping your mac awake"))
        XCTAssertEqual(o.severity, .calm)
        XCTAssertEqual(o.mug, .free, "must NOT be .blocked — the engine overrides")
        // Even a stubbornly-indefinite hold reads calm here (the crux fix).
        XCTAssertEqual(o.banner(hasHolds: true, anyIndefinite: true)?.tone, .calm)
        let rv = o.rowVerdict(for: .indefinite)
        XCTAssertEqual(rv.tone, .calm)
        XCTAssertEqual(rv.text, "Will sleep after you step away")
    }

    func testSleepingSoon() {
        let o = SleepOutlook.classify(
            inputs(idleSeconds: 60, remainingSeconds: 252, activeHoldingCount: 1))
        guard case .sleepingSoon(let s, let overriding) = o else { return XCTFail("got \(o)") }
        XCTAssertEqual(s, 252, accuracy: 0.1)
        XCTAssertEqual(overriding, 1)
        XCTAssertTrue(o.headline.hasPrefix("Sleeping in"))
        XCTAssertEqual(o.mug, .counting)
        XCTAssertEqual(o.severity, .positive)
        XCTAssertEqual(o.countdownSeconds, 252)
    }

    func testSleepingSoonViaAgentFinishedGraceBelow30sIdle() {
        let o = SleepOutlook.classify(
            inputs(idleSeconds: 5, agentFinished: true, remainingSeconds: 30))
        guard case .sleepingSoon = o else { return XCTFail("got \(o)") }
    }

    func testHeldByBlocker_perReasonMapping() {
        let cases: [(String, SleepBlocker)] = [
            ("Allowed app keeping awake: Zoom, Chrome", .allowedApps("Zoom, Chrome")),
            ("Microphone is in use (likely a call)", .call),
            ("Media or a call appears active", .media),
            ("Time Machine backup in progress", .timeMachine),
            ("macOS update or install in progress", .systemUpdate),
            ("Within your active hours (9 AM-5 PM)", .activeHours("9 AM-5 PM")),
        ]
        for (reason, expected) in cases {
            XCTAssertEqual(SleepBlocker.classify(reason), expected, reason)
            let o = SleepOutlook.classify(
                inputs(decision: SafetyDecision(holdForceSleepReasons: [reason])))
            guard case .heldByBlocker(let b) = o else { return XCTFail("got \(o) for \(reason)") }
            XCTAssertEqual(b, expected)
            XCTAssertEqual(o.severity, .warning)
            XCTAssertEqual(o.mug, .blocked)
            XCTAssertFalse(o.headline.isEmpty)
            XCTAssertFalse(o.subline.isEmpty)
        }
    }

    func testAutoSleepOff_withHolds() {
        let o = SleepOutlook.classify(inputs(decaffeinateEnabled: false, activeHoldingCount: 1))
        guard case .autoSleepOff = o else { return XCTFail("got \(o)") }
        XCTAssertEqual(o.headline, "Auto-sleep is off")
        XCTAssertTrue(o.offersEnableAutoSleep)
        XCTAssertEqual(o.severity, .warning)
        XCTAssertEqual(o.mug, .blocked)
    }

    func testAutoSleepOff_calmWhenNoHolds() {
        let o = SleepOutlook.classify(inputs(decaffeinateEnabled: false, activeHoldingCount: 0))
        XCTAssertEqual(o.severity, .calm)
        XCTAssertEqual(o.mug, .free)
    }

    func testKeepingAwake_manual() {
        let o = SleepOutlook.classify(
            inputs(caffeinateActive: true, caffeinateKeepsDisplayAwake: true))
        XCTAssertEqual(o, .keepingAwake(.manual(displayStaysOn: true)))
        XCTAssertEqual(o.headline, "Keeping your Mac awake")
        XCTAssertEqual(o.subline, "Display stays on too")
        XCTAssertEqual(o.severity, .positive)
        XCTAssertEqual(o.mug, .caffeinated)
    }

    func testKeepingAwake_quietWindow() {
        let until = Date(timeIntervalSince1970: 2_000_000)
        let o = SleepOutlook.classify(
            inputs(isQuietWindowActive: true, quietWindowHoldingAwake: true, quietUntil: until))
        guard case .keepingAwake(.quietWindow) = o else { return XCTFail("got \(o)") }
        XCTAssertTrue(o.headline.hasPrefix("Awake until"))
    }

    func testKeepingAwake_trigger() {
        let o = SleepOutlook.classify(inputs(triggerReason: "Zoom is running"))
        XCTAssertEqual(o, .keepingAwake(.trigger("Zoom is running")))
    }

    // MARK: Edge states

    func testKeepAwakePaused_willStillSleep() {
        let o = SleepOutlook.classify(
            inputs(
                decision: SafetyDecision(dropKeepAwakeReasons: ["Battery below 20% floor"]),
                isQuietWindowActive: true, quietWindowHoldingAwake: false))
        XCTAssertEqual(o, .keepAwakePaused(reason: "Battery below 20% floor"))
        XCTAssertEqual(o.severity, .calm, "the rail dropped the hold — the Mac WILL sleep")
        XCTAssertEqual(o.mug, .free)
    }

    func testProtectiveSleep() {
        let o = SleepOutlook.classify(
            inputs(
                decision: SafetyDecision(
                    immediateSleepReasons: ["Mac is overheating (backpack guard)"])))
        guard case .protectiveSleep = o else { return XCTFail("got \(o)") }
        XCTAssertEqual(o.mug, .counting)
        XCTAssertEqual(o.severity, .positive)
    }

    func testStrictTakeoverFlowsToWillSleep() {
        // Strict takeover makes the caffeine engine active but caffeinateActive is
        // gated on the SETTING — so it flows to "will sleep", the strongest control.
        let o = SleepOutlook.classify(inputs(caffeinateActive: false, activeHoldingCount: 1))
        guard case .willSleepAfterIdle = o else { return XCTFail("got \(o)") }
    }

    // MARK: The invariants that guarantee no contradiction

    func testBannerAmberIffRowAmber() {
        let states: [SleepOutlook] = [
            .freeToSleep(idleMinutes: 10, batteryNote: false),
            .willSleepAfterIdle(idleMinutes: 10, batteryNote: false, holdCount: 1),
            .sleepingSoon(seconds: 100, overriding: 1),
            .heldByBlocker(.call),
            .autoSleepOff(holdCount: 1),
            .keepingAwake(.manual(displayStaysOn: false)),
            .keepAwakePaused(reason: "x"),
        ]
        for o in states {
            let bannerAmber = o.banner(hasHolds: true, anyIndefinite: true)?.tone == .warning
            let rowAmber = o.rowVerdict(for: .indefinite).tone == .warning
            XCTAssertEqual(bannerAmber, rowAmber, "banner/row tone must agree for \(o)")
        }
    }

    func testBoundedRowsAreAlwaysCalm() {
        // A hold that ends itself is teal regardless of the engine state.
        for o: SleepOutlook in [.heldByBlocker(.call), .autoSleepOff(holdCount: 1)] {
            XCTAssertEqual(o.rowVerdict(for: .timed(reArms: true)).tone, .calm)
            XCTAssertEqual(o.rowVerdict(for: .untilProcess("npm")).tone, .calm)
        }
    }

    func testEverySafetyReasonClassifies() {
        // Every string SafetyRails / ScheduleEngine can emit must map to a specific
        // blocker (never `.other`), so the copy is always concrete.
        let reasons = [
            "Allowed app keeping awake: Zoom",
            "Microphone is in use (likely a call)",
            "Media or a call appears active",
            "Time Machine backup in progress",
            "macOS update or install in progress",
            "Within your active hours (9 AM\u{2013}5 PM)",
            "Battery below 20% floor",
            "Thermal pressure is high",
            "Mac is overheating (backpack guard)",
            "Battery critically low (3%)",
        ]
        for r in reasons {
            if case .other = SleepBlocker.classify(r) {
                XCTFail("unclassified safety reason: \(r)")
            }
        }
    }
}
