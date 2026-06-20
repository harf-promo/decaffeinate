import XCTest

@testable import Decaffeinate

// MARK: - Test doubles

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

private final class ThermalBox: @unchecked Sendable {
    var state: ProcessInfo.ThermalState = .nominal
}

@MainActor private final class FakeScanner: PowerAssertionScanning {
    var assertions: [PowerAssertion] = []
    func scan() -> [PowerAssertion] { assertions }
}

@MainActor private final class FakeIdle: IdleReading {
    var seconds: TimeInterval = 0
    func secondsSinceLastInput() -> TimeInterval { seconds }
}

@MainActor private final class FakePower: PowerReading {
    var snap: PowerSnapshot = .unknown
    func snapshot() -> PowerSnapshot { snap }
}

@MainActor private final class FakeSleeper: SystemSleeping {
    var result: Result<Void, SleepController.SleepError> = .success(())
    private(set) var callCount = 0
    func sleepNow() -> Result<Void, SleepController.SleepError> {
        callCount += 1
        return result
    }
}

@MainActor private final class FakeCaffeine: KeepAwakeControlling {
    private(set) var holdingSystem = false
    private(set) var holdingDisplay = false
    var isActive: Bool { holdingSystem || holdingDisplay }
    func update(keepSystemAwake: Bool, keepDisplayAwake: Bool, reason: String) {
        holdingSystem = keepSystemAwake
        holdingDisplay = keepDisplayAwake
    }
    func releaseAll() { holdingSystem = false; holdingDisplay = false }
}

@MainActor private final class FakeNotifier: BlockerNotifying {
    private(set) var notifications: [(app: String, name: String)] = []
    func requestAuthorizationIfNeeded() {}
    func notifyNewBlocker(appName: String, assertionName: String) {
        notifications.append((appName, assertionName))
    }
}

// MARK: - Tests

@MainActor
final class AppStateTests: XCTestCase {

    private struct Harness {
        let state: AppState
        let scanner: FakeScanner
        let idle: FakeIdle
        let power: FakePower
        let sleeper: FakeSleeper
        let caffeine: FakeCaffeine
        let notifier: FakeNotifier
        let settings: SettingsStore
        let rules: RulesEngine
        let clock: TestClock
        let thermal: ThermalBox
        let cleanup: () -> Void
    }

    private func makeHarness(_ configure: (inout DecaffeinateSettings) -> Void = { _ in })
        -> Harness
    {
        let suite = "decaf.appstate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        configure(&settings.settings)
        let rules = RulesEngine(defaults: defaults)
        let scanner = FakeScanner()
        let idle = FakeIdle()
        let power = FakePower()
        let sleeper = FakeSleeper()
        let caffeine = FakeCaffeine()
        let notifier = FakeNotifier()
        let clock = TestClock()
        let thermal = ThermalBox()
        let state = AppState(
            settingsStore: settings,
            rulesEngine: rules,
            telemetry: scanner,
            idleMonitor: idle,
            powerReader: power,
            caffeine: caffeine,
            notifier: notifier,
            sleepController: sleeper,
            thermalProvider: { thermal.state },
            now: { clock.date }
        )
        return Harness(
            state: state, scanner: scanner, idle: idle, power: power,
            sleeper: sleeper, caffeine: caffeine, notifier: notifier,
            settings: settings, rules: rules, clock: clock, thermal: thermal,
            cleanup: { defaults.removePersistentDomain(forName: suite) })
    }

    private func systemBlocker(
        _ name: String = "Chrome",
        bundle: String? = "com.google.Chrome"
    ) -> PowerAssertion {
        Fixtures.assertion(
            process: name, bundle: bundle,
            type: AssertionType.preventUserIdleSystemSleep)
    }

    // MARK: Mug / state machine

    func testFreeWhenNothingHoldsAwake() {
        let h = makeHarness(); defer { h.cleanup() }
        h.state.tick()
        XCTAssertEqual(h.state.mug, .free)
        XCTAssertEqual(h.state.headline, "Free to sleep")
    }

    func testCountingDownWhenIdleAndAway() throws {
        let h = makeHarness { $0.idleThresholdMinutes = 10 }; defer { h.cleanup() }
        h.idle.seconds = 60  // away > 30s, remaining 9:00
        h.state.tick()
        XCTAssertEqual(h.state.mug, .counting)
        let remaining = try XCTUnwrap(h.state.secondsUntilForcedSleep)
        XCTAssertEqual(remaining, 540, accuracy: 1)
        XCTAssertTrue(h.state.headline.hasPrefix("Sleeping in"))
    }

    func testBlockedWhenAppHoldsAwakeAndUserActive() {
        let h = makeHarness { $0.idleThresholdMinutes = 10 }; defer { h.cleanup() }
        h.scanner.assertions = [systemBlocker("Chrome")]
        h.idle.seconds = 2  // user active → not counting
        h.state.tick()
        XCTAssertEqual(h.state.mug, .blocked)
        XCTAssertEqual(h.state.secondsUntilForcedSleep, nil)
        XCTAssertTrue(h.state.headline.contains("keeping your Mac awake"))
    }

    func testCaffeinatedState() {
        let h = makeHarness { $0.caffeinateEnabled = true }; defer { h.cleanup() }
        h.state.tick()
        XCTAssertTrue(h.caffeine.holdingSystem)
        XCTAssertEqual(h.state.mug, .caffeinated)
    }

    // MARK: Force sleep

    func testForcesSleepAfterIdleThreshold() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)
        XCTAssertNotNil(h.state.lastSleepAt)
    }

    func testDoesNotForceSleepWhileCaffeinated() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1
            $0.caffeinateEnabled = true
        }; defer { h.cleanup() }
        h.idle.seconds = 600
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0)
    }

    func testCooldownPreventsRepeatedSleep() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120

        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)

        h.state.tick()  // same clock → suppressed
        XCTAssertEqual(h.sleeper.callCount, 1)

        h.clock.advance(61)
        h.state.tick()  // cooldown elapsed → fires again
        XCTAssertEqual(h.sleeper.callCount, 2)
    }

    func testImmediateThermalGuardIsIdempotentUnderCooldown() {
        let h = makeHarness(); defer { h.cleanup() }
        h.thermal.state = .critical
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "overheating triggers an immediate sleep")
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "must not spawn pmset every tick while still hot")
    }

    func testFailedSleepDoesNotClaimSleptAndRetriesAfterShortCooldown() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.sleeper.result = .failure(.nonZeroExit(1))
        h.idle.seconds = 120

        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)
        XCTAssertNil(h.state.lastSleepAt, "a failed sleep must not report success")
        XCTAssertNotNil(h.state.lastError)

        h.clock.advance(11)  // short failure cooldown
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 2)
    }

    func testManualSleepNowBypassesCooldown() {
        let h = makeHarness(); defer { h.cleanup() }
        h.state.sleepNow()
        h.state.sleepNow()
        XCTAssertEqual(h.sleeper.callCount, 2)
    }

    func testMediaHoldPreventsForcedSleep() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.scanner.assertions = [
            Fixtures.assertion(type: AssertionType.preventUserIdleDisplaySleep)
        ]
        h.idle.seconds = 300
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0)
    }

    func testIdleThresholdClampPreventsConstantSleep() {
        let h = makeHarness { $0.idleThresholdMinutes = 0 }; defer { h.cleanup() }
        h.idle.seconds = 30  // below the clamped 60s floor
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0)
    }

    // MARK: Keep-awake reconciliation

    func testBatteryFloorDropsKeepAwake() {
        let h = makeHarness {
            $0.caffeinateEnabled = true
            $0.batteryFloorPercent = 20
        }; defer { h.cleanup() }
        h.power.snap = PowerSnapshot(onBattery: true, charge: 0.10, isCharging: false)
        h.state.tick()
        XCTAssertFalse(h.caffeine.holdingSystem, "keep-awake is dropped below the battery floor")
    }

    // MARK: Firewall queue

    func testFirewallSurfacesNewBlockerAndNotifiesOnce() {
        let h = makeHarness(); defer { h.cleanup() }
        h.scanner.assertions = [systemBlocker("Zoom", bundle: "us.zoom.xos")]

        h.state.tick()
        XCTAssertEqual(h.state.pendingClassification.count, 1)
        XCTAssertEqual(h.notifier.notifications.count, 1)

        h.state.tick()  // already notified → no duplicate
        XCTAssertEqual(h.notifier.notifications.count, 1)
    }

    func testDecidedBlockerLeavesQueue() {
        let h = makeHarness(); defer { h.cleanup() }
        let blocker = systemBlocker("Zoom", bundle: "us.zoom.xos")
        h.scanner.assertions = [blocker]
        h.state.tick()
        XCTAssertEqual(h.state.pendingClassification.count, 1)

        h.state.setPolicy(.allow, for: blocker)
        XCTAssertTrue(h.state.pendingClassification.isEmpty)

        h.state.tick()
        XCTAssertTrue(h.state.pendingClassification.isEmpty, "an allowed app should not re-prompt")
    }

    func testActiveAllowUntilDoesNotRePrompt() {
        let h = makeHarness(); defer { h.cleanup() }
        let blocker = systemBlocker("Zoom", bundle: "us.zoom.xos")
        h.scanner.assertions = [blocker]
        h.state.tick()

        h.state.setPolicy(.allowUntil(Date().addingTimeInterval(3600)), for: blocker)
        h.state.tick()
        XCTAssertTrue(h.state.pendingClassification.isEmpty, "a live allowance is settled")
    }

    func testLapsedAllowUntilRePromptsAndClearsStaleRule() {
        let h = makeHarness(); defer { h.cleanup() }
        let blocker = systemBlocker("Zoom", bundle: "us.zoom.xos")
        h.scanner.assertions = [blocker]
        h.state.tick()

        // A "1 hour" allowance that has already lapsed (RulesEngine uses the
        // real wall clock for expiry, so use a real past date here).
        h.state.setPolicy(.allowUntil(Date().addingTimeInterval(-3600)), for: blocker)
        XCTAssertEqual(h.state.pendingClassification.count, 1, "a lapsed allowance re-prompts")
        XCTAssertNil(h.rules.policy(for: blocker), "the stale rule is cleared")
    }

    func testClearRuleAllowsReNotification() {
        let h = makeHarness(); defer { h.cleanup() }
        let blocker = systemBlocker("Zoom", bundle: "us.zoom.xos")
        h.scanner.assertions = [blocker]
        h.state.tick()
        h.state.setPolicy(.ignore, for: blocker)
        XCTAssertEqual(h.notifier.notifications.count, 1)

        h.state.clearRule(for: blocker)
        h.state.tick()
        XCTAssertEqual(h.notifier.notifications.count, 2, "clearing a rule re-arms the prompt")
    }
}
