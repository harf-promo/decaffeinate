import AppKit
import Combine
import Foundation

/// Visual state of the menu-bar icon, mapped to the PRD's mug metaphor.
enum MugState: Equatable {
    /// Nothing is holding the Mac awake; it is free to sleep. (Empty mug.)
    case free
    /// The decaffeinate idle timer is armed and counting down. (Filling mug.)
    case counting
    /// Something is holding the Mac awake right now. (Warning mug.)
    case blocked
    /// Keep-awake is intentionally engaged. (Bolt.)
    case caffeinated

    // The glyph for each state is drawn by `MugIcon` (custom template mugs).

    var accessibilityLabel: String {
        switch self {
        case .free: return "Decaffeinate — free to sleep"
        case .counting: return "Decaffeinate — sleeping soon"
        case .blocked: return "Decaffeinate — Mac is being kept awake"
        case .caffeinated: return "Decaffeinate — keeping awake"
        }
    }
}

/// The single source of truth for the UI. Polls the system once a second,
/// evaluates the rules + safety rails, reconciles keep-awake holds, and — the
/// whole point — forces the Mac to sleep when it has been left running idle.
@MainActor
final class AppState: ObservableObject {

    // Dependencies (injectable seams; default to the real engines in production)
    let settingsStore: SettingsStore
    let rulesEngine: RulesEngine
    private let telemetry: any PowerAssertionScanning
    private let idleMonitor: any IdleReading
    private let powerReader: any PowerReading
    private let caffeine: any KeepAwakeControlling
    private let notifier: any BlockerNotifying
    private let sleepController: any SystemSleeping
    private let thermalProvider: () -> ProcessInfo.ThermalState
    private let agentWatcher: AgentWatcher

    /// Once a watched agent/build finishes, sleep this many seconds after the
    /// user is idle (a short grace instead of the full idle threshold).
    private let completionGraceSeconds: TimeInterval = 60

    // Live, published system state
    @Published private(set) var assertions: [PowerAssertion] = []
    @Published private(set) var idleSeconds: TimeInterval = 0
    @Published private(set) var power: PowerSnapshot = .unknown
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var decision = SafetyDecision()

    // Derived UI state
    @Published private(set) var mug: MugState = .free
    @Published private(set) var headline: String = "Monitoring sleep"
    @Published private(set) var detail: String = ""
    @Published private(set) var secondsUntilForcedSleep: TimeInterval?
    @Published private(set) var lastSleepAt: Date?
    @Published private(set) var lastSleepReason: String?
    @Published private(set) var lastError: String?

    /// Newly-seen, still-unclassified apps holding the Mac awake — the firewall's
    /// "decide what to do" queue, surfaced in the menu.
    @Published private(set) var pendingClassification: [PowerAssertion] = []

    /// Status of the "sleep when my agent/build finishes" watcher.
    @Published private(set) var watchStatus: AgentWatcher.Status = .idle

    private var timer: Timer?
    private var notifiedBlockers: Set<String> = []
    private var suppressForceSleepUntil: Date?

    /// Clock seam for tests.
    private let now: () -> Date

    init(
        settingsStore: SettingsStore = SettingsStore(),
        rulesEngine: RulesEngine = RulesEngine(),
        telemetry: any PowerAssertionScanning = TelemetryEngine(),
        idleMonitor: any IdleReading = IdleMonitor(),
        powerReader: any PowerReading = PowerSourceReader(),
        caffeine: any KeepAwakeControlling = CaffeineEngine(),
        notifier: any BlockerNotifying = Notifier(),
        sleepController: any SystemSleeping = SleepController(),
        thermalProvider: @escaping () -> ProcessInfo.ThermalState = {
            ProcessInfo.processInfo.thermalState
        },
        agentWatcher: AgentWatcher = AgentWatcher(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.settingsStore = settingsStore
        self.rulesEngine = rulesEngine
        self.telemetry = telemetry
        self.idleMonitor = idleMonitor
        self.powerReader = powerReader
        self.caffeine = caffeine
        self.notifier = notifier
        self.sleepController = sleepController
        self.thermalProvider = thermalProvider
        self.agentWatcher = agentWatcher
        self.now = now
    }

    var settings: DecaffeinateSettings { settingsStore.settings }

    // MARK: Lifecycle

    func start() {
        timer?.invalidate()
        notifier.requestAuthorizationIfNeeded()
        tick()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.25
        // Pin to the main run loop in common modes so the engine keeps ticking
        // while the menu/popover is open, and so the block is guaranteed to fire
        // on the main actor (making the assumeIsolated above safe by construction).
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func shutDown() {
        timer?.invalidate()
        timer = nil
        caffeine.releaseAll()
    }

    // MARK: User actions

    /// Sleep the Mac right now, from the menu's primary button. Always fires,
    /// bypassing the post-sleep cooldown.
    func sleepNow() {
        forceSleep(reason: "Sleep Now pressed", bypassCooldown: true)
    }

    /// Clear a firewall rule and allow this app to be re-surfaced as a new
    /// blocker again later.
    func clearRule(for assertion: PowerAssertion) {
        if let rule = rulesEngine.rule(for: assertion) { rulesEngine.remove(rule) }
        notifiedBlockers.remove(key(assertion))
        tick()
    }

    func setPolicy(_ policy: RulePolicy, for assertion: PowerAssertion) {
        rulesEngine.setPolicy(policy, for: assertion)
        dismissPending(assertion)
        tick()
    }

    func dismissPending(_ assertion: PowerAssertion) {
        pendingClassification.removeAll { $0.id == assertion.id }
    }

    // MARK: Agent watcher

    /// Watch a process (tree) and let the Mac sleep once it finishes. Pass `nil`
    /// to stop watching.
    func setWatchTarget(_ target: WatchTarget?) {
        agentWatcher.setTarget(target)
        watchStatus = agentWatcher.status
        tick()
    }

    /// Processes currently holding the Mac awake — the best "sleep when this
    /// finishes" picks because they're real and running right now.
    var runningWatchCandidates: [String] {
        assertions.filter(\.blocksSystemSleep).map(\.processName).removingDuplicates()
    }

    /// Common long-running dev/agent tools to watch even if not (yet) running.
    var commonWatchCandidates: [String] {
        ["claude", "node", "python3", "xcodebuild", "cargo", "make", "swift", "docker"]
            .filter { !runningWatchCandidates.contains($0) }
    }

    // MARK: The tick

    func tick() {
        let s = settings
        assertions = telemetry.scan()
        idleSeconds = idleMonitor.secondsSinceLastInput()
        power = powerReader.snapshot()
        thermalState = thermalProvider()

        let systemBlockers = assertions.filter(\.blocksSystemSleep)
        let whitelistedAwake =
            systemBlockers
            .filter { rulesEngine.isActivelyAllowed($0) }
            .map(\.displayName)
            .removingDuplicates()

        let decision = SafetyRails.evaluate(
            assertions: assertions,
            power: power,
            thermalState: thermalState,
            whitelistedAwakeAppNames: whitelistedAwake,
            settings: s
        )
        self.decision = decision

        // 1) Reconcile keep-awake holds (caffeine + strict takeover).
        let wantsAwake =
            (s.caffeinateEnabled || s.strictTakeoverMode) && !decision.shouldDropKeepAwake
        let wantsDisplayAwake =
            s.caffeinateEnabled
            && s.caffeinateKeepsDisplayAwake
            && !decision.shouldDropKeepAwake
        caffeine.update(
            keepSystemAwake: wantsAwake,
            keepDisplayAwake: wantsDisplayAwake,
            reason: "Decaffeinate keep-awake"
        )

        // 2) Firewall: surface newly-seen, unclassified blockers.
        updateFirewallQueue(systemBlockers, enabled: s.notifyOnNewBlocker)

        // 2.5) Agent watcher: detect when a watched build/agent has finished.
        agentWatcher.tick(now: now(), systemBlockingPIDs: Set(systemBlockers.map(\.pid)))
        watchStatus = agentWatcher.status
        let agentFinished = agentWatcher.hasCompleted

        // 3) Immediate-sleep guards (overheating / critically low battery).
        //    Respects the cooldown so a persistent condition can't spawn pmset
        //    every second or thrash sleep→wake→sleep.
        if decision.mustSleepNow {
            if forceSleep(
                reason: decision.immediateSleepReasons.first ?? "Safety guard",
                bypassCooldown: false)
            {
                return
            }
        }

        // 4) The headline feature: force sleep when left idle. Once a watched
        //    agent/build has finished, collapse the idle requirement to a short
        //    grace so the Mac sleeps soon after you've stepped away.
        //    Suppressed while the user is intentionally caffeinating.
        var remaining: TimeInterval?
        if s.decaffeinateEnabled, !s.caffeinateEnabled {
            let base = s.effectiveIdleSeconds(onBattery: power.onBattery)
            let threshold = agentFinished ? min(base, completionGraceSeconds) : base
            let r = threshold - idleSeconds
            remaining = r
            if decision.canForceSleep, r <= 0 {
                let reason =
                    agentFinished
                    ? "Watched work finished — putting Mac to sleep"
                    : "Idle \(Int(threshold / 60)) min — putting Mac to sleep"
                if forceSleep(reason: reason, bypassCooldown: false) {
                    // The agent-completion sleep is one-shot: clear the watch so
                    // it doesn't turn into a permanent 60s-idle aggressive-sleep
                    // mode after the user wakes the Mac.
                    if agentFinished {
                        agentWatcher.setTarget(nil)
                        watchStatus = agentWatcher.status
                    }
                    return
                }
            }
        }

        updateDerivedState(
            systemBlockers: systemBlockers,
            decision: decision,
            remaining: remaining)
    }

    // MARK: Force sleep

    private var isForceSleepSuppressed: Bool {
        guard let until = suppressForceSleepUntil else { return false }
        return now() < until
    }

    /// Attempts to sleep the Mac. Returns `true` only if `pmset sleepnow`
    /// succeeded (so the caller can stop processing this tick). State is updated
    /// to reflect what actually happened:
    /// - success → record the sleep + a 60s cooldown (avoids re-sleep on wake).
    /// - failure → record the error + a short cooldown (avoids a per-second
    ///   pmset spawn storm) but do *not* claim a sleep occurred.
    /// - cooldown active (and not bypassed) → no-op.
    @discardableResult
    private func forceSleep(reason: String, bypassCooldown: Bool) -> Bool {
        if !bypassCooldown, isForceSleepSuppressed { return false }

        switch sleepController.sleepNow() {
        case .success:
            lastSleepAt = now()
            lastSleepReason = reason
            lastError = nil
            suppressForceSleepUntil = now().addingTimeInterval(60)
            return true
        case .failure(let error):
            lastError = error.description
            suppressForceSleepUntil = now().addingTimeInterval(10)
            return false
        }
    }

    // MARK: Firewall queue

    private func updateFirewallQueue(_ systemBlockers: [PowerAssertion], enabled: Bool) {
        // Prune resolved entries.
        let liveKeys = Set(systemBlockers.map(key))
        pendingClassification.removeAll { !liveKeys.contains(key($0)) }
        notifiedBlockers.formIntersection(liveKeys)

        guard enabled else { return }

        for blocker in systemBlockers {
            let k = key(blocker)
            // Apps with a currently-effective decision (Allow / Block / live
            // "allow 1h") are settled — leave them alone.
            if rulesEngine.hasEffectiveDecision(for: blocker) { continue }
            // A rule that exists but is no longer effective is a *lapsed*
            // "allow for 1 hour": drop the stale rule and clear the notification
            // suppression so the firewall re-prompts once. (A blocker the user
            // merely dismissed has no rule, so it stays dismissed — `notifiedBlockers`
            // keeps it out of the queue until it goes away on its own.)
            if let lapsed = rulesEngine.rule(for: blocker) {
                rulesEngine.remove(lapsed)
                notifiedBlockers.remove(k)
            }
            guard !notifiedBlockers.contains(k) else { continue }
            notifiedBlockers.insert(k)
            if !pendingClassification.contains(where: { key($0) == k }) {
                pendingClassification.append(blocker)
            }
            notifier.notifyNewBlocker(appName: blocker.displayName, assertionName: blocker.name)
        }
    }

    private func key(_ assertion: PowerAssertion) -> String {
        // Key on the attributed real owner when present, so the firewall queue
        // dedups and notifies per real app rather than per shared daemon.
        if let owner = assertion.realOwner {
            return (owner.bundleIdentifier ?? owner.name).lowercased()
        }
        return assertion.bundleIdentifier?.lowercased() ?? assertion.processName.lowercased()
    }

    // MARK: Derived UI state

    private func updateDerivedState(
        systemBlockers: [PowerAssertion],
        decision: SafetyDecision,
        remaining: TimeInterval?
    ) {
        let s = settings
        let nonWhitelistedBlockers = systemBlockers.filter { !rulesEngine.isActivelyAllowed($0) }

        if s.caffeinateEnabled, caffeine.isActive {
            mug = .caffeinated
            headline = "Keeping your Mac awake"
            detail =
                s.caffeinateKeepsDisplayAwake ? "Display stays on too" : "Display can still sleep"
            secondsUntilForcedSleep = nil
            return
        }

        // Counting down to a forced sleep — only surfaced once the user has
        // actually stepped away (so we don't show "Sleeping in 9:59" mid-type).
        if s.decaffeinateEnabled, !s.caffeinateEnabled, decision.canForceSleep,
            let remaining, idleSeconds >= 30
        {
            secondsUntilForcedSleep = max(0, remaining)
            mug = .counting
            headline = "Sleeping in \(Format.countdown(remaining))"
            detail =
                nonWhitelistedBlockers.isEmpty
                ? "You stepped away — winding down"
                : "Overriding \(nonWhitelistedBlockers.count) sleep block\(nonWhitelistedBlockers.count == 1 ? "" : "s")"
            return
        }
        secondsUntilForcedSleep = nil

        // Something is keeping the Mac awake and we are not forcing sleep.
        if !nonWhitelistedBlockers.isEmpty {
            mug = .blocked
            let names = nonWhitelistedBlockers.map(\.displayName).removingDuplicates()
            headline = smartHeadline(for: nonWhitelistedBlockers, names: names)
            if !decision.canForceSleep, let reason = decision.holdForceSleepReasons.first {
                detail = reason
            } else if !s.decaffeinateEnabled {
                detail = "Decaffeinate engine is off"
            } else if names.count == 1 {
                detail = "Keeping your Mac awake"
            } else {
                detail = names.prefix(3).joined(separator: ", ")
            }
            return
        }

        // Nothing holding the Mac awake.
        mug = .free
        if !s.decaffeinateEnabled {
            headline = "Monitoring only"
            detail = "Auto-sleep is off — turn it on to force sleep when idle"
        } else {
            headline = "Free to sleep"
            detail = idleHint(for: s)
        }
        secondsUntilForcedSleep = nil
    }

    /// Fold the *reason* into the headline when one app dominates, e.g.
    /// "Safari is playing media" / "Your microphone is in use".
    private func smartHeadline(for blockers: [PowerAssertion], names: [String]) -> String {
        if names.count == 1, let blocker = blockers.first {
            let reason = blocker.reason
            switch reason.category {
            case .microphone:
                return "Your microphone is in use"
            case .unknown:
                return "\(names[0]) is keeping your Mac awake"
            default:
                return "\(names[0]) is \(lowercasedFirst(reason.explanation))"
            }
        }
        return "\(names.count) apps are keeping your Mac awake"
    }

    private func lowercasedFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.lowercased() + string.dropFirst()
    }

    // MARK: Convenience for the UI

    var systemBlockerCount: Int { assertions.filter(\.blocksSystemSleep).count }

    /// A glanceable, always-true promise (shown when no live countdown is up):
    /// how long after you step away the Mac will sleep.
    var idleSleepHint: String {
        let minutes = Int(settings.effectiveIdleSeconds(onBattery: power.onBattery) / 60)
        let onBatteryNote =
            (power.onBattery && settings.sleepSoonerOnBattery
                && settings.batteryIdleThresholdMinutes < settings.idleThresholdMinutes)
            ? " (on battery)" : ""
        return "Sleeps ~\(minutes) min after you step away\(onBatteryNote)"
    }

    private func idleHint(for settings: DecaffeinateSettings) -> String { idleSleepHint }

    /// "for 12m" since the assertion was created, if known.
    func heldDuration(_ assertion: PowerAssertion) -> String? {
        guard let created = assertion.createdAt else { return nil }
        return "for " + Format.duration(now().timeIntervalSince(created))
    }
}
