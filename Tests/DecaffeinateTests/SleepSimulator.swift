import Foundation

@testable import Decaffeinate

// MARK: - Sleep-simulation harness
//
// Drives a real `AppState` through scripted time: power assertions appear and
// vanish, the user walks away and comes back, the kernel sleeps and wakes —
// without ever sleeping this Mac. Every system source is a fake:
//
//   * assertions  → `SimAssertions`  (PowerAssertionScanning)
//   * HID idle    → `SimIdle`        (IdleReading, advances with the clock)
//   * power       → `SimPower`       (PowerReading)
//   * pmset       → `SimKernel`      (SystemSleeping — records each request and,
//                                     like the real kernel, sleeps unless a
//                                     PreventSystemSleep hold aborts it)
//   * NSWorkspace → `SimPowerEvents` (SystemPowerEventSource)
//
// The firewall's decisions are then read off `pmsetRequests`, the notifier
// fake, and the sleep/rest history stores. See `SleepSimulationTests`.

/// A scripted NSWorkspace sleep/wake stream.
@MainActor
final class SimPowerEvents: SystemPowerEventSource {
    private var handler: (@MainActor (SystemPowerEvent) -> Void)?
    private(set) var startCount = 0

    var isStarted: Bool { handler != nil }

    func start(_ handler: @escaping @MainActor (SystemPowerEvent) -> Void) {
        startCount += 1
        guard self.handler == nil else { return }
        self.handler = handler
    }

    func stop() { handler = nil }

    /// Deliver one event, as NSWorkspace would on the main queue. Dropped (like
    /// a real notification with no observer) when not started.
    func post(_ event: SystemPowerEvent) { handler?(event) }
}

@MainActor
final class SimAssertions: PowerAssertionScanning {
    var live: [PowerAssertion] = []
    func scan() -> [PowerAssertion] { live }
}

@MainActor
final class SimIdle: IdleReading {
    var seconds: TimeInterval = 0
    func secondsSinceLastInput() -> TimeInterval { seconds }
}

@MainActor
final class SimPower: PowerReading {
    var snap: PowerSnapshot = .unknown
    func snapshot() -> PowerSnapshot { snap }
}

/// Stands in for `pmset` + the kernel. Each `sleepNow()` is logged; whether
/// the Mac then actually sleeps is decided by `SleepSimulator`, which consults
/// the live assertions the way the kernel does.
@MainActor
final class SimKernel: SystemSleeping {
    var launchResult: Result<Void, SleepController.SleepError> = .success(())
    /// Set by `sleepNow()`; consumed by the simulator after the current tick.
    var sleepRequested = false
    private(set) var sleepCalls = 0
    private(set) var displayOffCalls = 0

    func sleepNow() -> Result<Void, SleepController.SleepError> {
        sleepCalls += 1
        if case .success = launchResult { sleepRequested = true }
        return launchResult
    }

    func displayOffNow() -> Result<Void, SleepController.SleepError> {
        displayOffCalls += 1
        return launchResult
    }
}

@MainActor
final class SimNotifier: BlockerNotifying {
    private(set) var newBlockers: [String] = []
    private(set) var forcedSleeps: [String] = []
    private(set) var sleepFailures: [String] = []
    func requestAuthorizationIfNeeded() {}
    func notifyNewBlocker(appName: String, reason: String, holderKey: String) {
        newBlockers.append(appName)
    }
    func notifyNewBlockers(count: Int, sample: String) { newBlockers.append(sample) }
    func notifyForcedSleep(reason: String) { forcedSleeps.append(reason) }
    func notifySleepFailed(message: String) { sleepFailures.append(message) }
    func notifyAgentFinished(label: String) {}
    func notifyRestartOverdue(uptimeLabel: String) {}
    func refreshAuthorizationStatus(
        _ completion: @escaping @MainActor (NotificationAuthorization) -> Void
    ) { completion(.authorized) }
}

@MainActor
private final class SimCaffeine: KeepAwakeControlling {
    private(set) var holding = false
    var isActive: Bool { holding }
    func update(keepSystemAwake: Bool, keepDisplayAwake: Bool, reason: String) {
        holding = keepSystemAwake || keepDisplayAwake
    }
    func releaseAll() { holding = false }
}

@MainActor
private final class SimTriggers: TriggerSampling {
    func sample(onACPower: Bool) -> TriggerSignals {
        TriggerSignals(runningAppNames: [], onACPower: onACPower, cpuPercent: 0)
    }
}

@MainActor
private final class SimSubtrees: SubtreeCPUSampling {
    func sampleSubtrees(_ roots: Set<pid_t>, now: Date) -> [pid_t: ProcessSample] { [:] }
}

/// One scripted machine + one real `AppState`.
@MainActor
final class SleepSimulator {
    /// One `pmset sleepnow` the firewall issued, and what the kernel did with it.
    struct PmsetRequest: Equatable {
        let at: Date
        /// False when a PreventSystemSleep hold aborted the transition.
        let slept: Bool
    }

    let state: AppState
    let assertions = SimAssertions()
    let idle = SimIdle()
    let power = SimPower()
    let kernel = SimKernel()
    let notifier = SimNotifier()
    let events = SimPowerEvents()
    let rules: RulesEngine
    let settings: SettingsStore
    let restHistory: RestHistoryStore
    let clock = MutableClock()

    /// Whether the simulated Mac is currently asleep.
    private(set) var isAsleep = false
    private(set) var pmsetRequests: [PmsetRequest] = []
    private let defaults: UserDefaults
    private let suite: String
    private var nextPID: pid_t = 5000

    init(_ configure: (inout DecaffeinateSettings) -> Void = { _ in }) {
        suite = "decaf.sleepsim.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults)
        configure(&settings.settings)
        rules = RulesEngine(defaults: defaults)
        restHistory = RestHistoryStore(defaults: defaults)
        let clock = self.clock
        state = AppState(
            settingsStore: settings,
            rulesEngine: rules,
            history: SleepHistoryStore(defaults: defaults),
            restHistory: restHistory,
            awakeTime: AwakeTimeStore(defaults: defaults),
            telemetry: assertions,
            idleMonitor: idle,
            powerReader: power,
            caffeine: SimCaffeine(),
            notifier: notifier,
            sleepController: kernel,
            thermalProvider: { .nominal },
            triggerSampler: SimTriggers(),
            provenanceResolver: FakeProvenanceResolver(),
            audioResolver: FakeAudioDeviceResolver(),
            systemState: FakeSystemStateReader(),
            wakeReasonReader: FakeWakeReasonReader(),
            subtreeSampler: SimSubtrees(),
            powerEvents: events,
            now: { clock.date }
        )
        // Attach the scripted event stream the way `start()` does, minus the
        // live Timer — the simulator is the clock.
        state.registerRestObservers()
    }

    /// Drop the per-simulation defaults suite. Call from `defer`.
    func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: World

    /// An app takes a power assertion. Returns it so a test can set a rule on it.
    @discardableResult
    func hold(
        _ app: String, type: String = AssertionType.preventUserIdleSystemSleep,
        name: String = "Busy"
    ) -> PowerAssertion {
        nextPID += 1
        let assertion = Fixtures.assertion(
            pid: nextPID, process: app, bundle: "com.example.\(app)", type: type, name: name)
        assertions.live.append(assertion)
        return assertion
    }

    /// Every assertion `app` holds is released.
    func release(_ app: String) {
        assertions.live.removeAll { $0.processName == app }
    }

    /// The user touches the keyboard/trackpad.
    func userInput() { idle.seconds = 0 }

    // MARK: Time

    /// Let `seconds` of wall-clock time pass while awake, ticking `AppState`
    /// once a second like its real 1 Hz timer, with HID idle growing alongside.
    /// After each tick, a pmset request is resolved the way the kernel would:
    /// sleep (willSleep → asleep) unless a PreventSystemSleep hold aborts it.
    /// Stops early if the Mac falls asleep; returns the seconds actually run.
    @discardableResult
    func run(for seconds: Int) -> Int {
        precondition(!isAsleep, "the Mac is asleep — call wake(after:) first")
        for elapsed in 1...max(seconds, 1) {
            clock.date += 1
            idle.seconds += 1
            state.tick()
            resolvePmset()
            if isAsleep { return elapsed }
        }
        return seconds
    }

    /// The kernel puts the Mac to sleep on its own (lid close, Apple menu → Sleep,
    /// macOS idle) — not a Decaffeinate request.
    func naturalSleep() {
        precondition(!isAsleep)
        events.post(.screensDidSleep)
        events.post(.willSleep)
        isAsleep = true
    }

    /// The Mac stays asleep for `seconds`, then wakes. HID idle keeps counting
    /// across sleep (as the real `CGEventSource` does), so a wake with no fresh
    /// input reads as long-idle — the case the post-wake grace exists for.
    func wake(after seconds: TimeInterval, userTouches: Bool = false) {
        precondition(isAsleep, "the Mac is already awake")
        clock.date += seconds
        idle.seconds += seconds
        isAsleep = false
        events.post(.didWake)
        events.post(.screensDidWake)
        if userTouches { userInput() }
    }

    private func resolvePmset() {
        guard kernel.sleepRequested else { return }
        kernel.sleepRequested = false
        let aborted = assertions.live.contains {
            $0.assertionType == AssertionType.preventSystemSleep
        }
        pmsetRequests.append(PmsetRequest(at: clock.date, slept: !aborted))
        guard !aborted else { return }
        events.post(.screensDidSleep)
        events.post(.willSleep)
        isAsleep = true
    }

    // MARK: Read-outs

    var forcedSleeps: [SleepEvent] { state.history.events }
    /// The rest timeline, oldest first (the store keeps newest first).
    var restKinds: [RestEvent.Kind] { restHistory.events.reversed().map(\.kind) }
}
