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
    private(set) var notifications: [(app: String, reason: String)] = []
    func requestAuthorizationIfNeeded() {}
    func notifyNewBlocker(appName: String, reason: String) {
        notifications.append((appName, reason))
    }
}

/// Reports a fixed, idle (zero-CPU) subtree forever — drives AgentWatcher to
/// "completed" after its quiet window.
@MainActor private final class QuietSampler: ProcessSampling {
    let pids: Set<pid_t>
    init(pids: Set<pid_t>) { self.pids = pids }
    func sample(_ target: WatchTarget, now: Date) -> ProcessSample {
        ProcessSample(pids: pids, cpuNanoseconds: 0, at: now)
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

    private func makeHarness(
        watcher: AgentWatcher = AgentWatcher(),
        _ configure: (inout DecaffeinateSettings) -> Void = { _ in }
    ) -> Harness {
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
            history: SleepHistoryStore(defaults: defaults),
            telemetry: scanner,
            idleMonitor: idle,
            powerReader: power,
            caffeine: caffeine,
            notifier: notifier,
            sleepController: sleeper,
            thermalProvider: { thermal.state },
            agentWatcher: watcher,
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

    func testMenuBarCountdownFollowsSettingAndState() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 10; $0.showMenuBarCountdown = true
        }
        defer { h.cleanup() }
        h.idle.seconds = 60  // counting down, away
        h.state.tick()
        XCTAssertNotNil(h.state.secondsUntilForcedSleep)
        XCTAssertNotNil(h.state.menuBarCountdownText, "shown when enabled and counting")

        h.settings.settings.showMenuBarCountdown = false
        XCTAssertNil(h.state.menuBarCountdownText, "hidden when the setting is off")
    }

    func testMenuBarCountdownHiddenWhenNotCounting() {
        let h = makeHarness { $0.showMenuBarCountdown = true }; defer { h.cleanup() }
        h.state.tick()  // free to sleep — nothing counting
        XCTAssertNil(h.state.menuBarCountdownText)
    }

    // MARK: Force sleep

    func testForcesSleepAfterIdleThreshold() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)
        XCTAssertNotNil(h.state.lastSleepAt)
        XCTAssertEqual(h.state.history.events.count, 1, "forced sleep is logged to history")
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

    func testAgentCompletionSleepIsOneShot() {
        let watcher = AgentWatcher(sampler: QuietSampler(pids: [500]))
        watcher.requiredQuietSeconds = 2
        let h = makeHarness(watcher: watcher) { $0.idleThresholdMinutes = 10 }
        defer { h.cleanup() }

        // Drive the watcher to "completed" (quiet CPU past its window).
        h.idle.seconds = 0
        h.state.setWatchTarget(.processName("node"))
        for _ in 0..<5 {
            h.state.tick()
            h.clock.advance(1)
        }

        // Now finished: the collapsed 60s grace fires once when the user is away.
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)

        // After waking + cooldown, it must NOT keep force-sleeping every 60s —
        // the watch is cleared, so the normal 10-min threshold applies again.
        h.clock.advance(120)
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "agent-completion sleep must be one-shot")
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
        h.scanner.assertions = [
            systemBlocker("Zoom", bundle: "us.zoom.xos")  // default name "Test assertion"
        ]

        h.state.tick()
        XCTAssertEqual(h.state.pendingClassification.count, 1)
        XCTAssertEqual(h.notifier.notifications.count, 1)
        // The notification reason must be a classified label, never the raw,
        // app-controlled assertion name (which can leak to the lock screen).
        XCTAssertFalse(h.notifier.notifications.first!.reason.contains("Test assertion"))

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

    // MARK: Schedules & quiet windows

    func testQuietWindowHoldsAwakeAndSuppressesForceSleep() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.stayAwake(forMinutes: 30)  // ticks internally
        XCTAssertEqual(h.sleeper.callCount, 0, "no force-sleep inside a quiet window")
        XCTAssertTrue(h.caffeine.holdingSystem, "the Mac is actively held awake")
        XCTAssertEqual(h.state.mug, .caffeinated)
        XCTAssertTrue(h.state.headline.hasPrefix("Awake until"))
        XCTAssertTrue(h.state.isQuietWindowActive)
    }

    func testQuietWindowExpiresAndForceSleepResumes() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.state.stayAwake(forMinutes: 1)
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "held awake during the window")

        h.clock.advance(61)  // past the one-minute window
        h.state.tick()
        XCTAssertFalse(h.state.isQuietWindowActive, "the window auto-expires")
        XCTAssertEqual(h.sleeper.callCount, 1, "force-sleep resumes once the window elapses")
    }

    func testCancelQuietWindowResumesSleep() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.stayAwake(forMinutes: 30)
        XCTAssertEqual(h.sleeper.callCount, 0)
        h.state.clearQuietWindow()  // ticks internally
        XCTAssertFalse(h.state.isQuietWindowActive)
        XCTAssertEqual(h.sleeper.callCount, 1, "cancelling the window lets idle sleep fire")
    }

    func testStayAwakeUntilHourPicksFutureTime() {
        let h = makeHarness(); defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.state.stayAwake(untilHour: (hour + 2) % 24)
        let until = try? XCTUnwrap(h.state.quietUntil)
        XCTAssertNotNil(until)
        XCTAssertGreaterThan(until!, h.clock.date)
    }

    func testScheduleStandsDownDuringActiveHours() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1; $0.scheduleEnabled = true
        }
        defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.settings.settings.activeHoursStart = hour
        h.settings.settings.activeHoursEnd = (hour + 1) % 24
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "no force-sleep during active hours")
        XCTAssertFalse(h.state.decision.canForceSleep)
        XCTAssertTrue(
            h.state.decision.holdForceSleepReasons.contains { $0.contains("active hours") })
    }

    func testScheduleAllowsSleepOutsideActiveHours() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1; $0.scheduleEnabled = true
        }
        defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.settings.settings.activeHoursStart = (hour + 2) % 24
        h.settings.settings.activeHoursEnd = (hour + 3) % 24
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "outside active hours, idle force-sleep still fires")
    }

    // MARK: Safety-rail precedence (audit fixes)

    /// The "neither sleeps nor stays awake" hole: a quiet window under the battery
    /// floor must resolve to the battery floor winning — force-sleep, not limbo.
    func testQuietWindowUnderBatteryFloorForcesSleep() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        // 10% is below the default 20% battery floor.
        h.power.snap = PowerSnapshot(onBattery: true, charge: 0.10, isCharging: false)
        h.idle.seconds = 120
        h.state.stayAwake(forMinutes: 30)  // ticks internally
        XCTAssertEqual(h.sleeper.callCount, 1, "battery floor wins over a quiet window")
        XCTAssertFalse(h.caffeine.holdingSystem, "the quiet window is not holding the Mac awake")
        XCTAssertFalse(h.state.quietWindowHoldingAwake)
    }

    /// The active-hours stand-down must yield to the battery floor so the floor
    /// can still protect the battery during work hours.
    func testScheduleYieldsToBatteryFloor() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1; $0.scheduleEnabled = true
        }
        defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.settings.settings.activeHoursStart = hour
        h.settings.settings.activeHoursEnd = (hour + 1) % 24
        h.power.snap = PowerSnapshot(onBattery: true, charge: 0.10, isCharging: false)
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "battery floor overrides the active-hours hold")
    }

    /// The overheating / critical-battery guard must not be muzzled by an
    /// unrelated idle sleep's 60s cooldown.
    func testImmediateGuardNotMuzzledByIdleCooldown() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.tick()  // idle force-sleep → arms the 60s idle cooldown
        XCTAssertEqual(h.sleeper.callCount, 1)

        // Same clock (well within the idle cooldown): wake into a hot bag.
        h.idle.seconds = 0
        h.thermal.state = .critical
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 2, "backpack guard fires despite the idle cooldown")
    }

    // MARK: UX honesty (audit fixes)

    /// During active hours with nothing blocking, don't claim "Free to sleep" /
    /// "Sleeps ~N min after you step away" — say auto-sleep is paused, and why.
    func testSchedulePausedShowsHonestHeadline() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1; $0.scheduleEnabled = true
        }
        defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.settings.settings.activeHoursStart = hour
        h.settings.settings.activeHoursEnd = (hour + 1) % 24
        h.idle.seconds = 120  // away, but the schedule holds
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0)
        XCTAssertEqual(h.state.headline, "Auto-sleep paused")
        XCTAssertTrue(h.state.detail.contains("active hours"))
    }

    /// A finished watched task uses a short 60s grace, so the countdown should
    /// appear immediately rather than waiting for the usual 30s-idle reveal.
    func testAgentFinishedShowsCountdownBeforeThirtySecondsIdle() {
        let watcher = AgentWatcher(sampler: QuietSampler(pids: [500]))
        watcher.requiredQuietSeconds = 2
        let h = makeHarness(watcher: watcher) { $0.idleThresholdMinutes = 10 }
        defer { h.cleanup() }
        h.idle.seconds = 0
        h.state.setWatchTarget(.processName("node"))
        for _ in 0..<5 {
            h.state.tick()
            h.clock.advance(1)
        }
        h.idle.seconds = 10  // below the normal 30s reveal, inside the 60s grace
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "10s < 60s grace — not yet asleep")
        XCTAssertEqual(h.state.mug, .counting)
        XCTAssertNotNil(h.state.secondsUntilForcedSleep)
    }
}
