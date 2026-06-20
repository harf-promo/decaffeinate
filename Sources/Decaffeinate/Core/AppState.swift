import Foundation
import Combine
import AppKit

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

    var systemImage: String {
        switch self {
        case .free: return "cup.and.saucer"
        case .counting: return "cup.and.saucer.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .caffeinated: return "bolt.fill"
        }
    }

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

    // Dependencies
    let settingsStore: SettingsStore
    let rulesEngine: RulesEngine
    private let telemetry = TelemetryEngine()
    private let idleMonitor = IdleMonitor()
    private let powerReader = PowerSourceReader()
    private let caffeine = CaffeineEngine()
    private let notifier = Notifier()
    private var sleepController = SleepController()

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

    private var timer: Timer?
    private var notifiedBlockers: Set<String> = []
    private var suppressForceSleepUntil: Date?

    /// Override hook for tests.
    var now: () -> Date = { Date() }

    init(settingsStore: SettingsStore = SettingsStore(),
         rulesEngine: RulesEngine = RulesEngine()) {
        self.settingsStore = settingsStore
        self.rulesEngine = rulesEngine
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

    func toggleCaffeinate() {
        settingsStore.settings.caffeinateEnabled.toggle()
        tick()
    }

    func setDecaffeinate(_ enabled: Bool) {
        settingsStore.settings.decaffeinateEnabled = enabled
        tick()
    }

    // MARK: The tick

    func tick() {
        let s = settings
        assertions = telemetry.scan()
        idleSeconds = idleMonitor.secondsSinceLastInput()
        power = powerReader.snapshot()
        thermalState = ProcessInfo.processInfo.thermalState

        let systemBlockers = assertions.filter(\.blocksSystemSleep)
        let whitelistedAwake = systemBlockers
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
        let wantsAwake = (s.caffeinateEnabled || s.strictTakeoverMode) && !decision.shouldDropKeepAwake
        let wantsDisplayAwake = s.caffeinateEnabled
            && s.caffeinateKeepsDisplayAwake
            && !decision.shouldDropKeepAwake
        caffeine.update(
            keepSystemAwake: wantsAwake,
            keepDisplayAwake: wantsDisplayAwake,
            reason: "Decaffeinate keep-awake"
        )

        // 2) Firewall: surface newly-seen, unclassified blockers.
        updateFirewallQueue(systemBlockers, enabled: s.notifyOnNewBlocker)

        // 3) Immediate-sleep guards (overheating / critically low battery).
        //    Respects the cooldown so a persistent condition can't spawn pmset
        //    every second or thrash sleep→wake→sleep.
        if decision.mustSleepNow {
            if forceSleep(reason: decision.immediateSleepReasons.first ?? "Safety guard",
                          bypassCooldown: false) {
                return
            }
        }

        // 4) The headline feature: force sleep when left idle.
        //    Suppressed while the user is intentionally caffeinating.
        var remaining: TimeInterval?
        if s.decaffeinateEnabled, !s.caffeinateEnabled {
            let r = s.idleThresholdSeconds - idleSeconds
            remaining = r
            if decision.canForceSleep, r <= 0 {
                if forceSleep(reason: "Idle \(Int(s.idleThresholdMinutes)) min — putting Mac to sleep",
                              bypassCooldown: false) {
                    return
                }
            }
        }

        updateDerivedState(systemBlockers: systemBlockers,
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
            // Skip only apps with a *currently effective* decision; an expired
            // "allow for 1 hour" should surface again, not stay silently blocked.
            guard !rulesEngine.hasEffectiveDecision(for: blocker) else { continue }
            guard !notifiedBlockers.contains(k) else { continue }
            notifiedBlockers.insert(k)
            if !pendingClassification.contains(where: { key($0) == k }) {
                pendingClassification.append(blocker)
            }
            notifier.notifyNewBlocker(appName: blocker.displayName, assertionName: blocker.name)
        }
    }

    private func key(_ assertion: PowerAssertion) -> String {
        assertion.bundleIdentifier?.lowercased() ?? assertion.processName.lowercased()
    }

    // MARK: Derived UI state

    private func updateDerivedState(systemBlockers: [PowerAssertion],
                                    decision: SafetyDecision,
                                    remaining: TimeInterval?) {
        let s = settings
        let nonWhitelistedBlockers = systemBlockers.filter { !rulesEngine.isActivelyAllowed($0) }

        if s.caffeinateEnabled, caffeine.isActive {
            mug = .caffeinated
            headline = "Keeping your Mac awake"
            detail = s.caffeinateKeepsDisplayAwake ? "Display stays on too" : "Display can still sleep"
            secondsUntilForcedSleep = nil
            return
        }

        // Counting down to a forced sleep — only surfaced once the user has
        // actually stepped away (so we don't show "Sleeping in 9:59" mid-type).
        if s.decaffeinateEnabled, !s.caffeinateEnabled, decision.canForceSleep,
           let remaining, idleSeconds >= 30 {
            secondsUntilForcedSleep = max(0, remaining)
            mug = .counting
            headline = "Sleeping in \(Format.countdown(remaining))"
            detail = nonWhitelistedBlockers.isEmpty
                ? "You stepped away — winding down"
                : "Overriding \(nonWhitelistedBlockers.count) sleep block\(nonWhitelistedBlockers.count == 1 ? "" : "s")"
            return
        }
        secondsUntilForcedSleep = nil

        // Something is keeping the Mac awake and we are not forcing sleep.
        if !nonWhitelistedBlockers.isEmpty {
            mug = .blocked
            let names = nonWhitelistedBlockers.map(\.displayName).removingDuplicates()
            headline = names.count == 1
                ? "\(names[0]) is keeping your Mac awake"
                : "\(names.count) apps are keeping your Mac awake"
            if !decision.canForceSleep, let reason = decision.holdForceSleepReasons.first {
                detail = reason
            } else if !s.decaffeinateEnabled {
                detail = "Decaffeinate engine is off"
            } else {
                detail = names.prefix(3).joined(separator: ", ")
            }
            return
        }

        // Nothing holding the Mac awake.
        mug = .free
        if !s.decaffeinateEnabled {
            headline = "Free to sleep"
            detail = "Monitoring only"
        } else {
            headline = "Free to sleep"
            detail = "Nothing is blocking sleep"
        }
        secondsUntilForcedSleep = nil
    }

    // MARK: Convenience for the UI

    var systemBlockerCount: Int { assertions.filter(\.blocksSystemSleep).count }
    var displayBlockerCount: Int { assertions.filter { $0.kind == .displaySleep }.count }

    /// "for 12m" since the assertion was created, if known.
    func heldDuration(_ assertion: PowerAssertion) -> String? {
        guard let created = assertion.createdAt else { return nil }
        return "for " + Format.duration(now().timeIntervalSince(created))
    }
}
