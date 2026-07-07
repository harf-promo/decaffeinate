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
    private(set) var displayOffCount = 0
    func sleepNow() -> Result<Void, SleepController.SleepError> {
        callCount += 1
        return result
    }
    func displayOffNow() -> Result<Void, SleepController.SleepError> {
        displayOffCount += 1
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
    private(set) var forcedSleeps: [String] = []
    private(set) var agentFinishes: [String] = []
    private(set) var restartOverdues: [String] = []
    func requestAuthorizationIfNeeded() {}
    func notifyNewBlocker(appName: String, reason: String) {
        notifications.append((appName, reason))
    }
    func notifyForcedSleep(reason: String) { forcedSleeps.append(reason) }
    func notifyAgentFinished(label: String) { agentFinishes.append(label) }
    func notifyRestartOverdue(uptimeLabel: String) { restartOverdues.append(uptimeLabel) }
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

@MainActor private final class FakeTriggerSampler: TriggerSampling {
    var apps: Set<String> = []
    var cpu: Double = 0
    func sample(onACPower: Bool) -> TriggerSignals {
        TriggerSignals(runningAppNames: apps, onACPower: onACPower, cpuPercent: cpu)
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
        let triggers: FakeTriggerSampler
        let provenance: FakeProvenanceResolver
        let audio: FakeAudioDeviceResolver
        let system: FakeSystemStateReader
        let restHistory: RestHistoryStore
        let cleanup: () -> Void

        /// Simulate the kernel beginning a real sleep transition
        /// (NSWorkspace.willSleep) — in production what confirms a forced sleep
        /// truly took. Drives AppState.systemWillSleep() directly, bypassing the
        /// NSWorkspace observer wiring that only exists under start().
        @MainActor func confirmKernelSleep() { state.systemWillSleep() }
    }

    private func makeHarness(
        watcher: AgentWatcher = AgentWatcher(),
        provenance: FakeProvenanceResolver = FakeProvenanceResolver(),
        audio: FakeAudioDeviceResolver = FakeAudioDeviceResolver(),
        system: FakeSystemStateReader = FakeSystemStateReader(),
        _ configure: (inout DecaffeinateSettings) -> Void = { _ in }
    ) -> Harness {
        let suite = "decaf.appstate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        configure(&settings.settings)
        let rules = RulesEngine(defaults: defaults)
        let restHistory = RestHistoryStore(defaults: defaults)
        let scanner = FakeScanner()
        let idle = FakeIdle()
        let power = FakePower()
        let sleeper = FakeSleeper()
        let caffeine = FakeCaffeine()
        let notifier = FakeNotifier()
        let clock = TestClock()
        let thermal = ThermalBox()
        let triggers = FakeTriggerSampler()
        let state = AppState(
            settingsStore: settings,
            rulesEngine: rules,
            history: SleepHistoryStore(defaults: defaults),
            restHistory: restHistory,
            telemetry: scanner,
            idleMonitor: idle,
            powerReader: power,
            caffeine: caffeine,
            notifier: notifier,
            sleepController: sleeper,
            thermalProvider: { thermal.state },
            agentWatcher: watcher,
            triggerSampler: triggers,
            provenanceResolver: provenance,
            audioResolver: audio,
            systemState: system,
            now: { clock.date }
        )
        return Harness(
            state: state, scanner: scanner, idle: idle, power: power,
            sleeper: sleeper, caffeine: caffeine, notifier: notifier,
            settings: settings, rules: rules, clock: clock, thermal: thermal,
            triggers: triggers, provenance: provenance, audio: audio,
            system: system, restHistory: restHistory,
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

    func testWillSleepAfterIdleWhenAppHoldsAwakeAndUserActive() {
        let h = makeHarness { $0.idleThresholdMinutes = 10 }; defer { h.cleanup() }
        h.scanner.assertions = [systemBlocker("Chrome")]
        h.idle.seconds = 2  // user active → not counting yet
        h.state.tick()
        // The confident reframe: the engine WILL override this hold after idle, so
        // the app speaks from control — not the old passive "blocked" framing.
        XCTAssertEqual(h.state.mug, .free)
        XCTAssertEqual(h.state.secondsUntilForcedSleep, nil)
        XCTAssertTrue(
            h.state.headline.hasPrefix("Your Mac will sleep"),
            "confident framing; got: \(h.state.headline)")
        XCTAssertFalse(
            h.state.headline.lowercased().contains("keeping your mac awake"),
            "must not frame the app as passive; got: \(h.state.headline)")
        if case .willSleepAfterIdle = h.state.outlook {
        } else {
            XCTFail("expected .willSleepAfterIdle; got \(h.state.outlook)")
        }
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

    func testMenuBarAccessibilityLabelFoldsInCountdown() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 10; $0.showMenuBarCountdown = true
        }
        defer { h.cleanup() }
        h.idle.seconds = 60  // counting down
        h.state.tick()
        XCTAssertTrue(
            h.state.menuBarAccessibilityLabel.contains("sleeping in"),
            "VoiceOver must announce the countdown the user opted into")

        h.settings.settings.showMenuBarCountdown = false
        XCTAssertEqual(h.state.menuBarAccessibilityLabel, h.state.mug.accessibilityLabel)
    }

    // MARK: Force sleep

    func testForcesSleepAfterIdleThreshold() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)
        // pmset launched but the kernel hasn't confirmed sleep yet — nothing recorded.
        XCTAssertNil(h.state.lastSleepAt, "sleep not recorded until kernel confirms it")
        XCTAssertTrue(h.state.history.events.isEmpty, "history not written until willSleep fires")
        // Kernel confirms the transition → now we record it.
        h.confirmKernelSleep()
        XCTAssertNotNil(h.state.lastSleepAt)
        XCTAssertNotNil(h.state.lastSleepReason)
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

    func testDisplayOffInvokesTheController() {
        let h = makeHarness(); defer { h.cleanup() }
        h.state.displayOff()
        XCTAssertEqual(h.sleeper.displayOffCount, 1)
        XCTAssertNil(h.state.lastError, "no error on a successful display-off")
    }

    func testDisplayOffSurfacesFailure() {
        let h = makeHarness(); defer { h.cleanup() }
        h.sleeper.result = .failure(.launchFailed("boom"))
        h.state.displayOff()
        XCTAssertNotNil(h.state.lastError, "a failed display-off surfaces an error")
    }

    func testWatchTargetLabelNamesTheWatchedTarget() {
        let h = makeHarness(); defer { h.cleanup() }
        XCTAssertNil(h.state.watchTargetLabel, "no label while idle")
        h.state.setWatchTarget(.processName("xcodebuild"))
        XCTAssertEqual(
            h.state.watchTargetLabel, "xcodebuild",
            "the menu must be able to name what it's watching")
        h.state.setWatchTarget(nil)
        XCTAssertNil(h.state.watchTargetLabel, "cleared when watching stops")
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

    func testWakeGracePreventsInstantResleep() {
        // HID idle survives a sleep as wall-clock time: after a lid-open or
        // scheduled wake with no fresh input yet, the first tick reads hours of
        // idle. The post-wake grace must hold pmset off; after it lapses (still
        // no input), the idle engine re-engages.
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 8 * 3600
        h.state.systemDidWake()
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "no pmset inside the post-wake grace")
        h.clock.advance(61)
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "idle engine re-engages after the grace")
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

    func testBatteryFloorDropReEngagesForceSleepWhileCaffeinated() {
        // Keep-awake ON + battery below the user's floor: the rail drops the
        // hold, and force-sleep must re-engage — exactly like a rail-paused
        // quiet window — instead of leaving the Mac awake and draining until
        // the 3%-critical emergency guard.
        let h = makeHarness {
            $0.idleThresholdMinutes = 1
            $0.caffeinateEnabled = true
            $0.batteryFloorPercent = 30
        }; defer { h.cleanup() }
        h.power.snap = PowerSnapshot(onBattery: true, charge: 0.20, isCharging: false)
        h.idle.seconds = 600  // stepped away, well past the threshold
        h.state.tick()
        XCTAssertFalse(h.caffeine.holdingSystem, "rail must drop the keep-awake hold")
        XCTAssertEqual(h.sleeper.callCount, 1, "force-sleep re-engages once the hold is dropped")
    }

    func testStrictTakeoverIsInertWhileMasterSwitchOff() {
        // Strict takeover with the master switch off must not hold an assertion:
        // that combination would block macOS's own idle sleep while the idle
        // engine (gated on the master switch) never sleeps the Mac either.
        let h = makeHarness {
            $0.strictTakeoverMode = true
            $0.decaffeinateEnabled = false
        }; defer { h.cleanup() }
        h.state.tick()
        XCTAssertFalse(h.caffeine.holdingSystem, "no takeover hold while auto-sleep is off")

        h.settings.settings.decaffeinateEnabled = true
        h.state.tick()
        XCTAssertTrue(h.caffeine.holdingSystem, "takeover holds again with the master switch on")
    }

    // MARK: Firewall queue

    func testOwnAssertionIsInvisibleToTheFirewall() {
        // Decaffeinate's own keep-awake hold must never be scanned back in as a
        // third-party blocker — no self-notification, no phantom holding count.
        let h = makeHarness(); defer { h.cleanup() }
        h.scanner.assertions = [
            Fixtures.assertion(
                pid: ProcessInfo.processInfo.processIdentifier,
                process: "Decaffeinate", bundle: "com.harfpromo.Decaffeinate",
                name: "Decaffeinate keep-awake"),
            systemBlocker("Chrome"),
        ]
        h.state.tick()
        XCTAssertEqual(h.state.assertions.count, 1, "own-pid assertion is filtered out")
        XCTAssertEqual(h.state.assertions.first?.processName, "Chrome")
        XCTAssertEqual(h.state.activeHoldingCount, 1)
        XCTAssertFalse(
            h.notifier.notifications.contains { $0.app == "Decaffeinate" },
            "the firewall must never notify about the app itself")
    }

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

    func testIsPendingDecisionMatchesByKeyNotID() {
        let h = makeHarness(); defer { h.cleanup() }
        let zoom = systemBlocker("Zoom", bundle: "us.zoom.xos")
        h.scanner.assertions = [zoom]
        h.state.tick()  // Zoom enters the pending queue
        XCTAssertTrue(h.state.isPendingDecision(zoom))

        // A sibling hold from the same app — same firewall key, different id —
        // must still read as pending (so its approval buttons render).
        let sibling = Fixtures.assertion(
            pid: 9999, process: "Zoom", bundle: "us.zoom.xos",
            type: AssertionType.preventUserIdleSystemSleep, name: "another hold")
        XCTAssertNotEqual(sibling.id, zoom.id)
        XCTAssertTrue(
            h.state.isPendingDecision(sibling), "same-key sibling is pending too")

        // An unrelated app is not pending.
        XCTAssertFalse(
            h.state.isPendingDecision(systemBlocker("Safari", bundle: "com.apple.Safari")))
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

        // Expiry is now evaluated against the tick's injected clock, so anchor
        // the allowance to the test clock rather than the real wall clock.
        h.state.setPolicy(.allowUntil(h.clock.date.addingTimeInterval(3600)), for: blocker)
        h.state.tick()
        XCTAssertTrue(h.state.pendingClassification.isEmpty, "a live allowance is settled")
    }

    func testLapsedAllowUntilRePromptsAndClearsStaleRule() {
        let h = makeHarness(); defer { h.cleanup() }
        let blocker = systemBlocker("Zoom", bundle: "us.zoom.xos")
        h.scanner.assertions = [blocker]
        h.state.tick()

        // A "1 hour" allowance that lapsed relative to the tick's clock.
        h.state.setPolicy(.allowUntil(h.clock.date.addingTimeInterval(-3600)), for: blocker)
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

    func testStayAwakeUntilPastHourWrapsToTomorrow() {
        let h = makeHarness(); defer { h.cleanup() }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let nowHour = cal.component(.hour, from: h.clock.date)
        // Requesting the current hour is "already passed today" → roll to tomorrow.
        h.state.stayAwake(untilHour: nowHour, calendar: cal)
        let delta = h.state.quietUntil!.timeIntervalSince(h.clock.date)
        XCTAssertGreaterThan(delta, 23 * 3600, "wrapped to ~tomorrow, not the past")
        XCTAssertLessThanOrEqual(delta, 24 * 3600 + 1)
    }

    func testStayAwakeUntilHourSurvivesDSTGap() {
        let h = makeHarness(); defer { h.cleanup() }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        // 01:30 just before the 2→3 AM spring-forward; 2 AM doesn't exist.
        h.clock.date = cal.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        h.state.stayAwake(untilHour: 2, calendar: cal)
        XCTAssertNotNil(h.state.quietUntil, "a skipped wall-clock hour must not return nil")
        XCTAssertGreaterThan(h.state.quietUntil!, h.clock.date)
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

    // MARK: Schedule / quiet-window / watcher interactions

    func testScheduleStillHoldsAfterQuietWindowExpires() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1; $0.scheduleEnabled = true
        }
        defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.settings.settings.activeHoursStart = hour
        h.settings.settings.activeHoursEnd = (hour + 1) % 24
        h.state.stayAwake(forMinutes: 1)
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "held by the quiet window")

        h.clock.advance(61)  // window lapses, but still inside active hours
        h.state.tick()
        XCTAssertFalse(h.state.isQuietWindowActive)
        XCTAssertEqual(h.sleeper.callCount, 0, "the schedule still holds after the window expires")
        XCTAssertFalse(h.state.decision.canForceSleep)
    }

    func testAgentCompletionRespectsSchedule() {
        let watcher = AgentWatcher(sampler: QuietSampler(pids: [500]))
        watcher.requiredQuietSeconds = 2
        let h = makeHarness(watcher: watcher) {
            $0.idleThresholdMinutes = 10
            $0.scheduleEnabled = true
        }
        defer { h.cleanup() }
        let hour = Calendar.current.component(.hour, from: h.clock.date)
        h.settings.settings.activeHoursStart = hour
        h.settings.settings.activeHoursEnd = (hour + 1) % 24
        h.idle.seconds = 0
        h.state.setWatchTarget(.processName("node"))
        for _ in 0..<5 {
            h.state.tick()
            h.clock.advance(1)
        }
        h.idle.seconds = 120  // finished + away, but it's active hours
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "the schedule overrides the agent-completion grace")
    }

    // MARK: Triggers (conditional keep-awake)

    func testTriggerHoldsAwakeAndSuppressesForceSleep() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1
            $0.triggers = [TriggerRule(condition: .appRunning("zoom"))]
        }
        defer { h.cleanup() }
        h.triggers.apps = ["zoom.us"]
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "a satisfied trigger holds the Mac awake")
        XCTAssertTrue(h.caffeine.holdingSystem)
        XCTAssertNotNil(h.state.activeTriggerReason)
        XCTAssertEqual(h.state.mug, .caffeinated)
    }

    func testTriggerNotSatisfiedAllowsForceSleep() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1
            $0.triggers = [TriggerRule(condition: .appRunning("zoom"))]
        }
        defer { h.cleanup() }
        h.triggers.apps = ["safari"]  // zoom not running
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertNil(h.state.activeTriggerReason)
        XCTAssertEqual(h.sleeper.callCount, 1, "no trigger → idle force-sleep still fires")
    }

    func testTriggerYieldsToBatteryFloor() {
        let h = makeHarness {
            $0.idleThresholdMinutes = 1
            $0.triggers = [TriggerRule(condition: .appRunning("zoom"))]
        }
        defer { h.cleanup() }
        h.triggers.apps = ["zoom.us"]
        h.power.snap = PowerSnapshot(onBattery: true, charge: 0.10, isCharging: false)
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertNil(h.state.activeTriggerReason, "triggers are dropped below the battery floor")
        XCTAssertFalse(h.caffeine.holdingSystem)
        XCTAssertEqual(h.sleeper.callCount, 1, "the floor wins and force-sleep fires")
    }

    // MARK: Agentic integration

    /// Build a caffeinate holder + provenance whose `-w` target is a real, live pid
    /// (the test process itself), so the liveness check is deterministic.
    private func agenticCaffeinate(_ h: Harness) -> PowerAssertion {
        let me = getpid()
        h.provenance.byPid[500] = ProcessProvenance(
            holderPid: 500, holderName: "caffeinate",
            holderArgv: ["caffeinate", "-i", "-w", "\(me)"],
            parentChain: [ProcessLink(pid: 480, name: "2.1.183")],
            originApp: nil, originKind: .agentHost, ttyName: "ttys003",
            cwd: "/tmp/repo", originCommand: ["claude", "--model", "opusplan"],
            sessionLabel: "started by Claude Code · in repo")
        return Fixtures.assertion(
            pid: 500, process: "caffeinate", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep)
    }

    func testAgentWaitTargetAndDisplayReason() {
        let h = makeHarness(); defer { h.cleanup() }
        let caff = agenticCaffeinate(h)
        h.scanner.assertions = [caff]
        h.state.tick()

        let target = h.state.agentWaitTarget(for: caff)
        XCTAssertEqual(target?.pid, getpid())
        XCTAssertTrue(h.state.isAgentSession(caff))
        XCTAssertTrue(
            h.state.displayReason(for: caff).contains("Keeping the system awake until"),
            h.state.displayReason(for: caff))
    }

    func testAutoArmOnlyWhenSettingOn() {
        let off = makeHarness(); defer { off.cleanup() }
        off.scanner.assertions = [agenticCaffeinate(off)]
        off.state.tick()
        XCTAssertEqual(off.state.watchStatus, .idle, "no auto-arm when the setting is off")

        let on = makeHarness { $0.autoSleepWhenAgentFinishes = true }; defer { on.cleanup() }
        on.scanner.assertions = [agenticCaffeinate(on)]
        on.state.tick()
        XCTAssertNotEqual(on.state.watchStatus, .idle, "auto-arm fires for a recognized agent")
    }

    // MARK: Session coalescing (ephemeral caffeinate churn)

    /// An agent caffeinate with explicit pid / cwd / tty / createdAt so tests can
    /// simulate respawns (new pid, same session) and concurrent sessions.
    private func agentCaff(
        _ h: Harness, pid: pid_t, cwd: String, tty: String, created: Date,
        agent: String = "Claude Code"
    ) -> PowerAssertion {
        h.provenance.byPid[pid] = ProcessProvenance(
            holderPid: pid, holderName: "caffeinate",
            holderArgv: ["caffeinate", "-i", "-t", "300"],
            parentChain: [ProcessLink(pid: pid - 1, name: "2.1.183")],
            originApp: nil, originKind: .agentHost, ttyName: tty,
            cwd: cwd, originCommand: ["claude"], sessionLabel: nil)
        return Fixtures.assertion(
            pid: pid, process: "caffeinate", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, created: created)
    }

    func testCaffeinateRespawnsCoalesceToOneGroup() {
        let h = makeHarness(); defer { h.cleanup() }
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repo", tty: "ttys003", created: h.clock.date)
        ]
        h.state.tick()
        XCTAssertEqual(h.state.groupedSystemBlockers.count, 1)

        h.clock.advance(300)
        let respawn = agentCaff(
            h, pid: 777, cwd: "/tmp/repo", tty: "ttys003", created: h.clock.date)
        h.scanner.assertions = [respawn]
        h.state.tick()
        XCTAssertEqual(
            h.state.groupedSystemBlockers.count, 1, "a respawn is the same session")
    }

    func testSessionHeldDurationSurvivesRespawn() throws {
        let h = makeHarness(); defer { h.cleanup() }
        let t0 = h.clock.date
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repo", tty: "ttys003", created: t0)
        ]
        h.state.tick()  // first seen, anchored to createdAt == t0

        h.clock.advance(300)  // the -t hold's lifetime, then a respawn (new pid)
        let a1 = agentCaff(h, pid: 777, cwd: "/tmp/repo", tty: "ttys003", created: h.clock.date)
        h.scanner.assertions = [a1]
        h.state.tick()

        let secs = try XCTUnwrap(h.state.sessionHeldSeconds(for: a1))
        XCTAssertEqual(secs, 300, accuracy: 1, "anchored to first-seen, not the new createdAt")
    }

    func testSessionAnchorSurvivesSubGraceGap() throws {
        let h = makeHarness(); defer { h.cleanup() }
        let t0 = h.clock.date
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repo", tty: "ttys003", created: t0)
        ]
        h.state.tick()

        h.clock.advance(30)  // session briefly absent for 30s (< 90s grace)
        h.scanner.assertions = []
        h.state.tick()
        h.clock.advance(5)
        let a1 = agentCaff(h, pid: 777, cwd: "/tmp/repo", tty: "ttys003", created: h.clock.date)
        h.scanner.assertions = [a1]
        h.state.tick()

        let secs = try XCTUnwrap(h.state.sessionHeldSeconds(for: a1))
        XCTAssertEqual(secs, 35, accuracy: 1, "anchor survives an absence shorter than the grace")
    }

    func testSessionAnchorResetsPastGracePeriod() {
        let h = makeHarness(); defer { h.cleanup() }
        let t0 = h.clock.date
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repo", tty: "ttys003", created: t0)
        ]
        h.state.tick()

        h.scanner.assertions = []
        h.clock.advance(200)  // > 90s grace with nothing live → anchor forgotten
        h.state.tick()
        let a1 = agentCaff(h, pid: 777, cwd: "/tmp/repo", tty: "ttys003", created: h.clock.date)
        h.scanner.assertions = [a1]
        h.state.tick()
        let secs = h.state.sessionHeldSeconds(for: a1) ?? -1
        XCTAssertEqual(secs, 0, accuracy: 1, "past grace, the session is treated as new")
    }

    func testTwoProjectsAreTwoSessionsAndTwoHoldingCount() {
        let h = makeHarness(); defer { h.cleanup() }
        let now = h.clock.date
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repoA", tty: "ttys003", created: now),
            agentCaff(h, pid: 600, cwd: "/tmp/repoB", tty: "ttys004", created: now),
        ]
        h.state.tick()
        XCTAssertEqual(h.state.groupedSystemBlockers.count, 2)
        XCTAssertEqual(h.state.activeHoldingCount, 2, "Claude in two repos counts as two")
    }

    func testSameFolderDifferentTerminalsAreTwoSessions() {
        let h = makeHarness(); defer { h.cleanup() }
        let now = h.clock.date
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repo", tty: "ttys003", created: now),
            agentCaff(h, pid: 600, cwd: "/tmp/repo", tty: "ttys004", created: now),
        ]
        h.state.tick()
        XCTAssertEqual(h.state.groupedSystemBlockers.count, 2, "different terminals split")
    }

    func testConcurrentCaffeinatesInOneSessionAreOneGroupWithCount() {
        let h = makeHarness(); defer { h.cleanup() }
        let now = h.clock.date
        h.scanner.assertions = [
            agentCaff(h, pid: 500, cwd: "/tmp/repo", tty: "ttys003", created: now),
            agentCaff(
                h, pid: 777, cwd: "/tmp/repo", tty: "ttys003", created: now.addingTimeInterval(5)),
        ]
        h.state.tick()
        let groups = h.state.groupedSystemBlockers
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.liveCount, 2)
        XCTAssertEqual(groups.first?.representative.pid, 500, "oldest member is the representative")
    }

    func testNonAgentBlockerStaysSingletonRow() {
        let h = makeHarness(); defer { h.cleanup() }
        h.scanner.assertions = [systemBlocker("Chrome", bundle: "com.google.Chrome")]
        h.state.tick()
        let groups = h.state.groupedSystemBlockers
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(groups[0].isAgentSession)
        XCTAssertEqual(groups[0].liveCount, 1)
    }

    // MARK: Stable alphabetic ordering (v1.8.0)

    func testGroupedBlockersAreStableAlphabeticAcrossRespawn() {
        let h = makeHarness(); defer { h.cleanup() }
        let now = h.clock.date
        // Titles sort apple < banana < cherry; fed in cherry, apple, banana order.
        let c = agentCaff(h, pid: 30, cwd: "/x/cherry", tty: "ttys003", created: now)
        let a = agentCaff(h, pid: 31, cwd: "/x/apple", tty: "ttys004", created: now)
        let b = agentCaff(h, pid: 32, cwd: "/x/banana", tty: "ttys005", created: now)
        h.scanner.assertions = [c, a, b]
        h.state.tick()
        let titles = h.state.groupedSystemBlockers.map { h.state.groupTitle(for: $0) }
        XCTAssertEqual(
            titles, titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })

        // Respawn the middle one with a new pid in a different scan position.
        let bRespawn = agentCaff(h, pid: 99, cwd: "/x/banana", tty: "ttys005", created: now)
        h.scanner.assertions = [bRespawn, c, a]
        h.state.tick()
        XCTAssertEqual(
            h.state.groupedSystemBlockers.map { h.state.groupTitle(for: $0) }, titles,
            "order is identical after a respawn — no churn")
    }

    // MARK: Audio device label

    func testAudioDeviceLabelForAudioHold() {
        let h = makeHarness(); defer { h.cleanup() }
        h.audio.byToken = ["AirPodsUID": "AirPods Pro"]
        let mic = Fixtures.assertion(
            pid: 700, process: "coreaudiod", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, resources: ["audio-in", "AirPodsUID"])
        let chrome = systemBlocker("Chrome", bundle: "com.google.Chrome")
        h.scanner.assertions = [mic, chrome]
        h.state.tick()
        XCTAssertEqual(h.state.audioDeviceLabel(for: mic), "AirPods Pro")
        XCTAssertNil(h.state.audioDeviceLabel(for: chrome), "no audio resource → no device")
        // An unattributed audio hold is titled by its device.
        XCTAssertEqual(h.state.rowTitle(for: mic), "AirPods Pro")
    }

    // MARK: Lifetime classification + summary

    func testHoldLifetimeClassification() {
        let h = makeHarness(); defer { h.cleanup() }
        // -w live target → untilProcess.
        let waitHold = agenticCaffeinate(h)  // argv has -w <getpid()>
        h.scanner.assertions = [waitHold]
        h.state.tick()
        if case .untilProcess = h.state.holdLifetime(for: waitHold) {
        } else {
            XCTFail("caffeinate -w with a live target should be .untilProcess")
        }
        // -t agent → timed(reArms: true).
        let timedHold = agentCaff(
            h, pid: 800, cwd: "/x/repo", tty: "ttys003", created: h.clock.date)
        h.scanner.assertions = [timedHold]
        h.state.tick()
        XCTAssertEqual(h.state.holdLifetime(for: timedHold), .timed(reArms: true))
        // Plain blocker, no timeout → indefinite.
        let plain = systemBlocker("Chrome", bundle: "com.google.Chrome")
        h.scanner.assertions = [plain]
        h.state.tick()
        XCTAssertEqual(h.state.holdLifetime(for: plain), .indefinite)
    }

    // (Former `testAwakeSummary` removed — `awakeSummary` folded into SleepOutlook;
    //  its behavior is covered by SleepOutlookTests + the sleepBanner tests below.)

    // MARK: Rest & restart (v1.9.0)

    func testUptimeAndAdviceFromFakeBootTime() {
        let h = makeHarness(system: FakeSystemStateReader()); defer { h.cleanup() }
        h.system.boot = h.clock.date.addingTimeInterval(-9 * 86_400)  // up 9 days
        h.state.readBootTimeAndInferRestart()
        XCTAssertEqual(h.state.uptime ?? 0, 9 * 86_400, accuracy: 1)
        XCTAssertEqual(h.state.restartAdvice, .consider)
        XCTAssertEqual(h.state.restartHint, "Up 9 days — a restart would freshen things up.")
    }

    func testFreshUptimeProducesNoHeaderHint() {
        let h = makeHarness(); defer { h.cleanup() }
        h.system.boot = h.clock.date.addingTimeInterval(-1 * 86_400)  // up 1 day
        h.state.readBootTimeAndInferRestart()
        XCTAssertEqual(h.state.restartAdvice, .fresh)
        XCTAssertNil(h.state.restartHint)
    }

    func testUrgentUptimeViaClockSeam() {
        let h = makeHarness(); defer { h.cleanup() }
        h.system.boot = h.clock.date.addingTimeInterval(-47 * 86_400)  // near the ~49-day cliff
        h.state.readBootTimeAndInferRestart()
        XCTAssertEqual(h.state.restartAdvice, .urgent)
    }

    func testForcedSleepAlsoRecordsRestEvent() {
        let h = makeHarness { $0.idleThresholdMinutes = 10 }; defer { h.cleanup() }
        h.idle.seconds = 700  // well past threshold → force sleep
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)
        // No .forcedSleep recorded yet — waiting for kernel confirmation.
        XCTAssertFalse(
            h.restHistory.events.contains { $0.kind == .forcedSleep },
            "forcedSleep not recorded until willSleep fires")
        // Kernel confirms → .forcedSleep is now recorded.
        h.confirmKernelSleep()
        XCTAssertEqual(h.restHistory.events.last?.kind, .forcedSleep)
    }

    // MARK: Honesty: deferred forced-sleep recording

    func testForcedSleepNotRecordedWhenKernelNeverSleeps() {
        // A PreventSystemSleep hold can abort the pmset transition. In that case
        // the Mac stays awake and we must record nothing — no false "Slept N ago".
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1, "pmset was attempted")
        // No willSleep fires — a hold aborted the transition.
        XCTAssertNil(h.state.lastSleepAt, "must not claim a sleep that never happened")
        XCTAssertTrue(h.state.history.events.isEmpty, "history must stay empty")
        XCTAssertFalse(
            h.restHistory.events.contains { $0.kind == .forcedSleep },
            "restHistory must not show a forced sleep")
        // After the cooldown the engine retries — it's not wedged.
        h.clock.advance(61)
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 2, "retried after cooldown")
    }

    func testNaturalSleepRecordedWhenNoForcedSleepPending() {
        // Lid-close or Apple menu → Sleep while Decaffeinate isn't in forced-sleep
        // mode → recorded as .systemSleep (natural), not .forcedSleep.
        let h = makeHarness { $0.caffeinateEnabled = true }; defer { h.cleanup() }
        // Caffeinated → no forced sleep attempted.
        h.idle.seconds = 999
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 0, "caffeinated, no forced sleep")
        h.confirmKernelSleep()
        XCTAssertEqual(
            h.restHistory.events.last?.kind, .systemSleep,
            "a willSleep with no pending forced sleep is a natural sleep")
        XCTAssertNil(h.state.lastSleepAt, "lastSleepAt only set for forced sleeps")
        XCTAssertTrue(h.state.history.events.isEmpty, "force-sleep history stays empty")
    }

    func testForcedSleepConfirmationWindowLapsesToNatural() {
        // If the willSleep fires more than 30 s after the pmset launch, we treat
        // it as an unrelated natural sleep (e.g. user closed the lid long after the
        // forced-sleep attempt was already forgotten).
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.sleeper.callCount, 1)
        // Advance past the confirmation window (>30 s) before confirming.
        h.clock.advance(31)
        h.confirmKernelSleep()
        XCTAssertEqual(
            h.restHistory.events.last?.kind, .systemSleep,
            "lapsed pending → treated as natural sleep")
        XCTAssertNil(
            h.state.lastSleepAt,
            "lastSleepAt not set for a lapsed confirmation")
        XCTAssertTrue(
            h.state.history.events.isEmpty,
            "force-sleep history stays empty for lapsed confirmation")
    }

    func testRestartInferredOnBootTimeAdvance() {
        let h = makeHarness(); defer { h.cleanup() }
        // A previous, earlier boot is on record → a later boot means it restarted.
        h.settings.defaults.set(
            h.clock.date.addingTimeInterval(-20 * 86_400), forKey: "DecaffeinateLastBootTime.v1")
        h.system.boot = h.clock.date.addingTimeInterval(-1 * 86_400)
        h.state.readBootTimeAndInferRestart()
        XCTAssertTrue(h.restHistory.events.contains { $0.kind == .restart })
    }

    func testNoRestartWhenBootTimeUnchanged() {
        let h = makeHarness(); defer { h.cleanup() }
        let boot = h.clock.date.addingTimeInterval(-5 * 86_400)
        h.settings.defaults.set(boot, forKey: "DecaffeinateLastBootTime.v1")
        h.system.boot = boot
        h.state.readBootTimeAndInferRestart()
        XCTAssertFalse(h.restHistory.events.contains { $0.kind == .restart })
    }

    // MARK: Notifications — forced sleep

    func testForcedSleepNotificationFiresOnKernelConfirmation() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        h.settings.settings.notifyOnForcedSleep = true
        h.idle.seconds = 120
        h.state.tick()
        // pmset launched but the kernel hasn't fired willSleep yet — no notification.
        XCTAssertTrue(
            h.notifier.forcedSleeps.isEmpty,
            "notification must not fire until the kernel confirms the sleep")
        // Kernel confirms → notification fires.
        h.confirmKernelSleep()
        XCTAssertEqual(h.notifier.forcedSleeps.count, 1)
    }

    func testForcedSleepNotificationRespectsOptOut() {
        let h = makeHarness { $0.idleThresholdMinutes = 1 }; defer { h.cleanup() }
        // Default: notifyOnForcedSleep = false.
        h.idle.seconds = 120
        h.state.tick()
        h.confirmKernelSleep()
        XCTAssertTrue(
            h.notifier.forcedSleeps.isEmpty,
            "notifyOnForcedSleep is off by default — must not fire")
    }

    // MARK: Notifications — agent finished

    func testAgentFinishedNotificationFiresOnceAtSleepTrigger() {
        let watcher = AgentWatcher(sampler: QuietSampler(pids: [500]))
        watcher.requiredQuietSeconds = 2
        let h = makeHarness(watcher: watcher) {
            $0.idleThresholdMinutes = 10
            $0.notifyOnAgentFinished = true
        }
        defer { h.cleanup() }
        h.idle.seconds = 0
        h.state.setWatchTarget(.processName("node"))
        // Drive the watcher to completed.
        for _ in 0..<5 {
            h.state.tick()
            h.clock.advance(1)
        }
        // Agent finished — fires the notification exactly when the sleep is triggered.
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(h.notifier.agentFinishes.count, 1)
        // Watcher is cleared after the one-shot sleep; further ticks must not re-fire.
        h.clock.advance(120)
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertEqual(
            h.notifier.agentFinishes.count, 1,
            "agent-finished notification is one-shot — must not re-fire after the watcher clears")
    }

    func testAgentFinishedNotificationRespectsOptOut() {
        let watcher = AgentWatcher(sampler: QuietSampler(pids: [500]))
        watcher.requiredQuietSeconds = 2
        let h = makeHarness(watcher: watcher) { $0.idleThresholdMinutes = 10 }
        defer { h.cleanup() }
        // Explicitly opt out (overrides the true default set in the configure block above).
        h.settings.settings.notifyOnAgentFinished = false
        h.idle.seconds = 0
        h.state.setWatchTarget(.processName("node"))
        for _ in 0..<5 {
            h.state.tick()
            h.clock.advance(1)
        }
        h.idle.seconds = 120
        h.state.tick()
        XCTAssertTrue(h.notifier.agentFinishes.isEmpty, "opt-out must suppress the notification")
    }

    // MARK: Notifications — restart overdue

    func testRestartOverdueNotificationFiresOnFirstCrossing() {
        let h = makeHarness(); defer { h.cleanup() }
        h.settings.settings.notifyOnRestartOverdue = true
        // 9 days → .consider (below the 7×2 = 14-day overdue threshold).
        h.system.boot = h.clock.date.addingTimeInterval(-9 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()
        XCTAssertTrue(
            h.notifier.restartOverdues.isEmpty,
            ".consider is not overdue — must not fire a notification")

        // 15 days → .overdue (≥ 14-day threshold with default 7-day recommendation).
        h.system.boot = h.clock.date.addingTimeInterval(-15 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()
        XCTAssertEqual(h.notifier.restartOverdues.count, 1, "first crossing must fire exactly once")

        // Subsequent ticks while still overdue must NOT re-fire.
        h.state.tick()
        h.state.tick()
        XCTAssertEqual(
            h.notifier.restartOverdues.count, 1,
            "must not spam repeated notifications within the same overdue band")
    }

    func testRestartAdviceDeDupPersistsToInjectedDefaults() {
        let h = makeHarness(); defer { h.cleanup() }
        h.settings.settings.notifyOnRestartOverdue = true
        // Cross into .overdue so the de-dup band is recorded.
        h.system.boot = h.clock.date.addingTimeInterval(-15 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()
        XCTAssertEqual(h.notifier.restartOverdues.count, 1)

        // The de-dup blob must land in the *injected* suite (test isolation) — pre-fix
        // it went to UserDefaults.standard, so this suite would read nil.
        let persisted = h.settings.defaults.dictionary(
            forKey: "Decaffeinate.lastNotifiedAdvice.v1")
        XCTAssertNotNil(persisted, "advice de-dup state must persist to the injected defaults")
        XCTAssertEqual(persisted?["advice"] as? String, "overdue")
    }

    func testRestartOverdueNotificationRespectsOptOut() {
        let h = makeHarness(); defer { h.cleanup() }
        // Default: notifyOnRestartOverdue = false.
        h.system.boot = h.clock.date.addingTimeInterval(-15 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()
        XCTAssertTrue(
            h.notifier.restartOverdues.isEmpty, "notifyOnRestartOverdue is off by default")
    }

    func testRestartOverdueNotificationReArmsAfterRestartDropsToFresh() {
        let h = makeHarness(); defer { h.cleanup() }
        h.settings.settings.notifyOnRestartOverdue = true
        // First run: cross into .overdue → fires once.
        h.system.boot = h.clock.date.addingTimeInterval(-15 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()
        XCTAssertEqual(h.notifier.restartOverdues.count, 1)

        // Simulate a restart: uptime drops to .fresh (1 day).
        h.system.boot = h.clock.date.addingTimeInterval(-1 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()  // advice → .fresh → lastNotifiedRestartAdvice resets

        // Second long run: cross into .overdue again → must fire again.
        h.system.boot = h.clock.date.addingTimeInterval(-15 * 86_400)
        h.state.readBootTimeAndInferRestart()
        h.state.tick()
        XCTAssertEqual(
            h.notifier.restartOverdues.count, 2,
            "notification must re-arm after a restart that resets advice to .fresh")
    }

    // MARK: sleepBanner (v1.13.0 — outlook-aware, never contradicts the header)

    func testSleepBannerNilWhenNoBlockers() {
        let h = makeHarness(); defer { h.cleanup() }
        h.scanner.assertions = []
        h.state.tick()
        XCTAssertNil(
            h.state.sleepBanner,
            "No blockers → nil (empty state handles 'free to sleep')"
        )
    }

    func testSleepBannerCalmWhenEngineWillOverride() {
        let h = makeHarness(); defer { h.cleanup() }
        // A caffeinate -t agent hold (timed) — the engine overrides after idle.
        h.scanner.assertions = [
            agentCaff(h, pid: 800, cwd: "/x/repo", tty: "ttys003", created: h.clock.date)
        ]
        h.state.tick()
        let banner = h.state.sleepBanner
        XCTAssertNotNil(banner, "Hold present → non-nil banner")
        XCTAssertEqual(banner?.tone, .calm)
        XCTAssertEqual(banner?.glyph, "checkmark")
    }

    func testSleepBannerCalmForIndefiniteHoldWhenAutoSleepOn() {
        let h = makeHarness(); defer { h.cleanup() }
        // The core bug fix: an INDEFINITE hold used to force an amber "held
        // indefinitely" banner. With auto-sleep on and nothing holding off the
        // engine, the app WILL override it — so the banner is calm, not amber.
        h.scanner.assertions = [
            Fixtures.assertion(
                pid: 100, process: "Zoom", bundle: "us.zoom.xos",
                type: AssertionType.preventUserIdleSystemSleep)
        ]
        h.state.tick()
        let banner = h.state.sleepBanner
        XCTAssertNotNil(banner)
        XCTAssertEqual(
            banner?.tone, .calm,
            "auto-sleep will override the indefinite hold → calm, not amber")
        XCTAssertNotEqual(banner?.glyph, "exclamationmark.triangle")
    }

    func testSleepBannerAmberOnlyWhenGenuinelyHeldOff() {
        // A whitelisted app genuinely holds off force-sleep (canForceSleep=false)
        // → the amber warning is now correct and scoped to the real reason.
        let h = makeHarness { $0.respectWhitelist = true }; defer { h.cleanup() }
        let zoom = Fixtures.assertion(
            pid: 100, process: "Zoom", bundle: "us.zoom.xos",
            type: AssertionType.preventUserIdleSystemSleep)
        h.scanner.assertions = [zoom]
        h.rules.setPolicy(.allow, for: zoom)
        h.state.tick()
        guard case .heldByBlocker = h.state.outlook else {
            return XCTFail("expected .heldByBlocker; got \(h.state.outlook)")
        }
        XCTAssertEqual(h.state.sleepBanner?.tone, .warning)
    }

    // MARK: Sleep Now feedback (v1.13.0)

    func testSleepNowThatNeverSleepsSurfacesFeedback() {
        let h = makeHarness(); defer { h.cleanup() }
        h.state.sleepNow()  // pmset "launches" but no willSleep confirmation arrives
        XCTAssertNil(h.state.lastError, "no error immediately after launch")
        h.clock.advance(11)  // past userSleepFeedbackSeconds
        h.state.tick()
        XCTAssertNotNil(
            h.state.lastError,
            "a Sleep Now that never actually slept must be surfaced, not silent")
    }

    func testConfirmedSleepNowShowsNoError() {
        let h = makeHarness(); defer { h.cleanup() }
        h.state.sleepNow()
        h.confirmKernelSleep()  // willSleep fired → confirmed, pending cleared
        h.clock.advance(11)
        h.state.tick()
        XCTAssertNil(h.state.lastError)
        XCTAssertNotNil(h.state.lastSleepAt, "a confirmed sleep is recorded")
    }

    func testTransientErrorClearsAfterVisibilityWindow() {
        let h = makeHarness(); defer { h.cleanup() }
        h.sleeper.result = .failure(.launchFailed("boom"))
        h.state.sleepNow()
        XCTAssertNotNil(h.state.lastError)
        h.sleeper.result = .success(())  // stop failing
        h.clock.advance(31)  // past errorVisibilitySeconds
        h.state.tick()
        XCTAssertNil(h.state.lastError, "a one-off error clears itself")
    }
}
