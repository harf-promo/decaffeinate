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
    let history: SleepHistoryStore
    let restHistory: RestHistoryStore
    private let telemetry: any PowerAssertionScanning
    private let idleMonitor: any IdleReading
    private let powerReader: any PowerReading
    private let caffeine: any KeepAwakeControlling
    private let notifier: any BlockerNotifying
    private let sleepController: any SystemSleeping
    private let thermalProvider: () -> ProcessInfo.ThermalState
    private let agentWatcher: AgentWatcher
    private let triggerSampler: any TriggerSampling
    private let provenanceResolver: any ProcessProvenanceResolving
    private let audioResolver: any AudioDeviceResolving
    private let systemState: any SystemStateReading
    private let wakeReasonReader: any WakeReasonReading
    private let subtreeSampler: any SubtreeCPUSampling
    private var staleDetector: StaleHolderDetector

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
    /// The single source of truth for "will my Mac sleep?" — the header, banner,
    /// every row verdict, and the mug all project from this so they never disagree.
    @Published private(set) var outlook: SleepOutlook = .freeToSleep(
        idleMinutes: 10, batteryNote: false)
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

    /// System-blocking holds grouped into stable rows: one group per agent session
    /// (coalesced across the `caffeinate -t` respawns), singletons for everything
    /// else. The menu renders these so rows don't churn as pids cycle. Snapshotted
    /// in `tick()` so the order/first-seen stay consistent within a frame.
    @Published private(set) var groupedSystemBlockers: [HoldGroup] = []

    /// Status of the "sleep when my agent/build finishes" watcher.
    @Published private(set) var watchStatus: AgentWatcher.Status = .idle

    /// CPU evidence per system-sleep holder pid: a holder that has been ~0% CPU for
    /// a sustained window while still asserting is "likely stale". Keyed by the
    /// hold's effective owner pid (`onBehalfOfPID ?? pid`). Read by the row subtitle
    /// and the stale-aware `rowVerdict`. Evidence only — never forces sleep.
    @Published private(set) var staleEvidence: [pid_t: StaleEvidence] = [:]

    /// One-shot "stay awake until …" quiet window from the menu. While set and in
    /// the future, Decaffeinate actively holds the Mac awake and never forces
    /// sleep. Cleared automatically once it elapses. Persisted so a window set via
    /// a Shortcut / App Intent / URL scheme survives a background relaunch.
    @Published private(set) var quietUntil: Date? {
        didSet { persistQuietUntil() }
    }

    /// Why a keep-awake trigger is currently holding the Mac awake (an app is
    /// running, on AC, CPU busy), or `nil`.
    @Published private(set) var activeTriggerReason: String?

    /// When the Mac last booted (read once at `start()`); `uptime` derives from it.
    @Published private(set) var bootTime: Date?

    private var timer: Timer?
    private var restObserverTokens: [NSObjectProtocol] = []
    /// This process's pid — its own assertions are filtered out of every scan.
    private static let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    private static let lastBootKey = "DecaffeinateLastBootTime.v1"
    /// Persisted restart-advice state — keyed by boot time so it auto-resets after
    /// a real restart. Stores { "bootSecs": Double, "advice": String }.
    private static let lastNotifiedAdviceKey = "Decaffeinate.lastNotifiedAdvice.v1"
    /// Persisted keep-awake window end, so an intent/URL-scheme "keep awake" hold
    /// survives a background relaunch (see `start()` restore, `persistQuietUntil`).
    private static let quietUntilKey = "Decaffeinate.quietUntil.v1"
    private var notifiedBlockers: Set<String> = []

    /// First time each live session key was observed — the anchor for a stable
    /// "held since" that survives `caffeinate -t` respawns. Pruned with a grace
    /// period so the brief gap between an expiring `-t` hold and its respawn
    /// doesn't reset the timer.
    private var sessionFirstSeen: [String: Date] = [:]
    /// Last tick each session key was seen live — drives the grace-period prune.
    private var sessionLastSeen: [String: Date] = [:]
    /// How long a vanished session key keeps its anchor before we forget it —
    /// covers the gap while one `caffeinate -t 300` exits and the agent respawns.
    private let sessionGracePeriod: TimeInterval = 90

    private var suppressForceSleepUntil: Date?
    /// Separate, short cooldown for the immediate-safety guards so an unrelated
    /// idle sleep's 60s cooldown can never muzzle the overheating / critical-
    /// battery backpack guard.
    private var suppressImmediateUntil: Date?

    /// The last restart-advice level we fired a notification for. Seeded in
    /// `start()` so the app never nags on launch just because the Mac is already
    /// overdue when Decaffeinate opens. Re-arms after the advice drops back to
    /// `.fresh` (e.g. after a restart).
    private var lastNotifiedRestartAdvice: RestartAdvice?

    /// A forced sleep we asked for via pmset but haven't confirmed the kernel
    /// performed. Recorded only when a willSleep notification confirms it; left to
    /// lapse (recording nothing) if a PreventSystemSleep hold aborts the transition.
    private var pendingForcedSleep:
        (reason: String, requestedAt: Date, onBattery: Bool, userInitiated: Bool)?
    /// How long after launching `pmset sleepnow` a willSleep still counts as
    /// confirmation of *that* forced sleep. Generous enough to cover a slow sleep
    /// transition, bounded so an unrelated natural sleep minutes later isn't
    /// misattributed.
    private let forcedSleepConfirmationWindow: TimeInterval = 30
    /// When a user's **Sleep Now** launches `pmset` but the Mac never actually
    /// sleeps within this window (an app holds a `PreventSystemSleep` assertion),
    /// tell the user instead of failing silently.
    private let userSleepFeedbackSeconds: TimeInterval = 10
    /// Named force-sleep cooldowns (avoid a per-second `pmset` spawn storm).
    private let idleCooldownSeconds: TimeInterval = 60
    private let immediateCooldownSeconds: TimeInterval = 15
    private let failureCooldownSeconds: TimeInterval = 10
    /// A transient error auto-clears after this long so a one-off can't linger.
    private var lastErrorAt: Date?
    private let errorVisibilitySeconds: TimeInterval = 30

    /// Clock seam for tests.
    private let now: () -> Date

    init(
        settingsStore: SettingsStore = SettingsStore(),
        rulesEngine: RulesEngine = RulesEngine(),
        history: SleepHistoryStore = SleepHistoryStore(),
        restHistory: RestHistoryStore = RestHistoryStore(),
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
        triggerSampler: any TriggerSampling = LiveTriggerSampler(),
        provenanceResolver: any ProcessProvenanceResolving = ProcessProvenanceResolver(),
        audioResolver: any AudioDeviceResolving = AudioDeviceResolver(),
        systemState: any SystemStateReading = SystemStateReader(),
        wakeReasonReader: any WakeReasonReading = LiveWakeReasonReader(),
        subtreeSampler: any SubtreeCPUSampling = SubtreeSampler(),
        staleDetector: StaleHolderDetector = StaleHolderDetector(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.settingsStore = settingsStore
        self.rulesEngine = rulesEngine
        self.history = history
        self.restHistory = restHistory
        self.telemetry = telemetry
        self.idleMonitor = idleMonitor
        self.powerReader = powerReader
        self.caffeine = caffeine
        self.notifier = notifier
        self.sleepController = sleepController
        self.thermalProvider = thermalProvider
        self.agentWatcher = agentWatcher
        self.triggerSampler = triggerSampler
        self.provenanceResolver = provenanceResolver
        self.audioResolver = audioResolver
        self.systemState = systemState
        self.wakeReasonReader = wakeReasonReader
        self.subtreeSampler = subtreeSampler
        self.staleDetector = staleDetector
        self.now = now
    }

    // MARK: Insight (v1.16)

    /// A one-line "while you were away" recap of the recent rest timeline, or nil
    /// when nothing noteworthy happened. Shown in Rest & Restart.
    var restDigest: String? {
        RestDigest.summary(rest: restHistory.events, now: now())
    }

    /// The friendly reason the Mac last woke ("You opened the lid", "Scheduled
    /// wake"…), resolved off the main actor from `pmset -g log` (best-effort;
    /// nil when unavailable). The mirror of the app's "what's keeping it awake".
    func latestWakeReason() async -> String? {
        let reader = wakeReasonReader
        return await Task.detached { reader.latestWakeReason() }.value
    }

    /// Copy the live diagnostics report to the clipboard (the About-pane action).
    func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsReport(), forType: .string)
    }

    /// Build a copy-pasteable diagnostics report of the live state — the artifact
    /// a bug report needs (effective settings + rules + the current scan).
    func diagnosticsReport() -> String {
        let all = telemetry.scan().filter { $0.pid != Self.ownPID }
        let snapshot = Diagnostics.Snapshot(
            version: AppInfo.version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: SystemProfile.modelIdentifier(),
            generatedAt: now(),
            settings: settings,
            rules: rulesEngine.rules,
            power: power,
            thermal: thermalState,
            idleSeconds: idleSeconds,
            uptimeSeconds: uptime,
            stateHeadline: headline,
            stateDetail: detail,
            systemBlockers: all.filter(\.blocksSystemSleep),
            otherAssertions: all.filter { !$0.blocksSystemSleep })
        return Diagnostics.report(snapshot)
    }

    /// Friendly device name(s) behind an audio hold ("AirPods Pro", "Built-in
    /// Microphone"), resolved lazily on render. Empty when unknown.
    func audioDevices(for assertion: PowerAssertion) -> [String] {
        ReasonEngine.deviceTokens(assertion.resources)
            .compactMap { audioResolver.friendlyName(forToken: $0) }
            .removingDuplicates()
    }

    /// The single best device string to append to an audio row, or nil.
    func audioDeviceLabel(for assertion: PowerAssertion) -> String? {
        switch assertion.reason.category {
        case .microphone, .audioPlayback, .mediaPlayback:
            return audioDevices(for: assertion).first
        default:
            return nil
        }
    }

    /// An SF Symbol for an audio hold's resolved device (AirPods / headphones /
    /// built-in), falling back to the category's icon.
    func audioDeviceSymbol(for assertion: PowerAssertion) -> String? {
        let tokens = ReasonEngine.deviceTokens(assertion.resources)
        for token in tokens {
            let name = (audioResolver.friendlyName(forToken: token) ?? token).lowercased()
            if name.contains("airpod") { return "airpodspro" }
            if name.contains("headphone") || name.contains("beats") { return "headphones" }
            if name.contains("built-in speaker") || name.contains("macbook") {
                return assertion.reason.category == .microphone ? "mic.fill" : "speaker.wave.2.fill"
            }
            if let device = audioResolver.device(forToken: token) {
                return device.hasInput && !device.hasOutput ? "mic.fill" : "speaker.wave.2.fill"
            }
        }
        return nil
    }

    /// Where a holder pid came from (terminal / agent / project), resolved lazily
    /// and cached by the resolver. Used by the detail view and row enrichment.
    func provenance(for pid: pid_t) -> ProcessProvenance? {
        provenanceResolver.provenance(for: pid)
    }

    var settings: DecaffeinateSettings { settingsStore.settings }

    /// The compact countdown to draw beside the menu-bar icon, or `nil` when the
    /// setting is off or no forced sleep is imminent.
    var menuBarCountdownText: String? {
        guard settings.showMenuBarCountdown, let seconds = secondsUntilForcedSleep else {
            return nil
        }
        return Format.countdown(seconds)
    }

    /// VoiceOver label for the whole menu-bar item, folding in the countdown the
    /// user opted into (a raw "9:05" beside the icon is otherwise never announced).
    var menuBarAccessibilityLabel: String {
        guard let countdown = menuBarCountdownText else { return mug.accessibilityLabel }
        return "\(mug.accessibilityLabel), sleeping in \(countdown)"
    }

    /// Ask for notification permission. Driven by the onboarding "Get started"
    /// button on first run (so the prompt lands with its explanation), and by
    /// `start()` on every later launch.
    func requestNotificationAuthorization() {
        notifier.requestAuthorizationIfNeeded()
    }

    // MARK: Lifecycle

    func start() {
        timer?.invalidate()
        // On first run, defer the notification prompt to the onboarding flow so it
        // arrives with context instead of cold at launch.
        if settings.hasCompletedOnboarding {
            notifier.requestAuthorizationIfNeeded()
        }
        readBootTimeAndInferRestart()
        // Restore the last-notified restart advice for this boot session so we
        // never nag again in a band we already fired in — even across relaunches.
        // Falls back to the current advice when no persisted state exists for this
        // boot (first run, or a different boot), which prevents a launch-time nag.
        lastNotifiedRestartAdvice = loadPersistedRestartNotificationState() ?? restartAdvice
        // Restore a keep-awake window set via a Shortcut / App Intent / URL scheme
        // before this (possibly background) launch, so it isn't silently dropped.
        // An expired window is cleared by the tick() below.
        if let saved = settingsStore.defaults.object(forKey: Self.quietUntilKey) as? Date,
            saved > now()
        {
            quietUntil = saved
        }
        registerRestObservers()
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
        let center = NSWorkspace.shared.notificationCenter
        restObserverTokens.forEach(center.removeObserver)
        restObserverTokens.removeAll()
        caffeine.releaseAll()
    }

    // MARK: Rest tracking

    /// Read boot time once, and record a `.restart` if the Mac has booted since
    /// the last time we ran (a boot-time jump can't tell restart from shutdown —
    /// we label it "Restarted" honestly). Persists the boot time for next launch.
    func readBootTimeAndInferRestart() {
        let boot = systemState.bootTime()
        bootTime = boot
        guard let boot else { return }
        let key = Self.lastBootKey
        let previous = settingsStore.defaults.object(forKey: key) as? Date
        if previous == nil || boot.timeIntervalSince(previous!) > 1 {
            if previous != nil {
                restHistory.record(
                    RestEvent(date: now(), kind: .restart, uptimeSeconds: uptime))
            }
            restHistory.record(RestEvent(date: now(), kind: .launch, uptimeSeconds: uptime))
        }
        settingsStore.defaults.set(boot, forKey: key)
    }

    /// Observe the system's natural rest rhythm (public NSWorkspace events) and
    /// log it. These are local AppKit callbacks, not user notifications.
    private func registerRestObservers() {
        guard restObserverTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        // willSleep routes to systemWillSleep() so forced-sleep confirmation
        // and natural-sleep recording share one code path.
        let willSleepToken = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systemWillSleep()
            }
        }
        restObserverTokens.append(willSleepToken)
        let pairs: [(Notification.Name, RestEvent.Kind)] = [
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.screensDidSleepNotification, .displayOff),
            (NSWorkspace.screensDidWakeNotification, .displayOn),
        ]
        for (name, kind) in pairs {
            let token = center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let wakeDate = self.now()
                    self.restHistory.record(
                        RestEvent(date: wakeDate, kind: kind, onBattery: self.power.onBattery))
                    // Pair a wake with the most recent unmatched forced sleep so we
                    // can measure how long the Mac actually stayed asleep.
                    if kind == .wake {
                        self.history.recordWakeDuration(at: wakeDate)
                        self.systemDidWake()
                    }
                }
            }
            restObserverTokens.append(token)
        }
    }

    // MARK: User actions

    /// Sleep the Mac right now, from the menu's primary button. Always fires,
    /// bypassing the post-sleep cooldown.
    func sleepNow() {
        forceSleep(reason: "Sleep Now pressed", bypassCooldown: true, userInitiated: true)
    }

    /// Turn the display off now (system keeps running) — the menu's "Turn display
    /// off" action. Surfaces an error if the launch fails, like Sleep Now.
    func displayOff() {
        if case .failure(let error) = sleepController.displayOffNow() {
            setError(error.description)
        }
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

    /// The label of whatever is being watched right now ("xcodebuild", "npm run
    /// build"…), or nil when idle — so the menu can name it instead of a generic
    /// "Stop watching".
    var watchTargetLabel: String? {
        switch watchStatus {
        case .idle: return nil
        case .waiting(let label), .watching(let label, _), .completed(let label, _):
            return label
        }
    }

    /// Watch a process (tree) and let the Mac sleep once it finishes. Pass `nil`
    /// to stop watching.
    func setWatchTarget(_ target: WatchTarget?) {
        agentWatcher.setTarget(target)
        watchStatus = agentWatcher.status
        tick()
    }

    // MARK: Quiet window ("stay awake until …")

    /// True while a future quiet window is in effect.
    var isQuietWindowActive: Bool {
        guard let until = quietUntil else { return false }
        return now() < until
    }

    /// True only while a quiet window is *actually* holding the Mac awake — i.e.
    /// it is active AND the safety rails (battery floor / thermal) haven't forced
    /// the hold to drop. The UI must distinguish "Awake until X" from a window
    /// that's been paused by a safety rail.
    var quietWindowHoldingAwake: Bool {
        isQuietWindowActive && !decision.shouldDropKeepAwake
    }

    /// Hold the Mac awake for the next `minutes` minutes, then auto-release.
    func stayAwake(forMinutes minutes: Int) {
        quietUntil = now().addingTimeInterval(TimeInterval(minutes) * 60)
        tick()
    }

    /// Hold the Mac awake until the next time it hits `hour:00` (today or
    /// tomorrow) — e.g. "until 6 PM" or "end of the work day".
    func stayAwake(untilHour hour: Int, calendar: Calendar = .current) {
        let start = now()
        var comps = calendar.dateComponents([.year, .month, .day], from: start)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        guard var target = calendar.date(from: comps) else { return }
        if target <= start {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
        }
        quietUntil = target
        tick()
    }

    /// Cancel an active quiet window immediately.
    func clearQuietWindow() {
        quietUntil = nil
        tick()
    }

    /// Processes currently holding the Mac awake — the best "sleep when this
    /// finishes" picks because they're real and running right now.
    var runningWatchCandidates: [String] {
        assertions.filter(\.blocksSystemSleep).map(\.processName).removingDuplicates()
    }

    /// Common long-running dev/agent tools to watch even if not (yet) running.
    var commonWatchCandidates: [String] {
        AgentRegistry.commonWatchProcessNames.filter { !runningWatchCandidates.contains($0) }
    }

    // MARK: Agentic / caffeinate enrichment

    /// The parsed `caffeinate` invocation behind a hold, if it is one.
    private func caffeinateInvocation(for assertion: PowerAssertion) -> CaffeinateInvocation? {
        guard let provenance = provenanceResolver.provenance(for: assertion.pid),
            let first = provenance.holderArgv.first,
            (first as NSString).lastPathComponent.lowercased() == "caffeinate"
        else { return nil }
        return CaffeinateArgvParser.parse(provenance.holderArgv)
    }

    /// The reason string shown in the UI — enriched to spell out exactly what a
    /// `caffeinate` hold is doing (e.g. "…until npm run build (PID 8123) finishes").
    func displayReason(for assertion: PowerAssertion) -> String {
        if let invocation = caffeinateInvocation(for: assertion) {
            // Same PID-reuse guard as `agentWaitTarget`: a gone target's pid may
            // already belong to an unrelated live process, so only resolve a
            // name while the original target is alive. A gone target resolves to
            // nil so the explainer uses the cleaner "until process N exits" form.
            let waitName = invocation.waitPID
                .flatMap { isAlive($0) ? processName(forPID: $0) : nil }
                .flatMap { $0.hasPrefix("PID ") ? nil : $0 }
            return CaffeinateExplainer.explain(invocation, waitTargetName: waitName)
        }
        return assertion.reason.explanation
    }

    /// For a `caffeinate -w <pid>` hold whose wait target is still alive, the pid +
    /// a label so the menu can offer one-click "Sleep when it finishes".
    func agentWaitTarget(for assertion: PowerAssertion) -> (pid: pid_t, label: String)? {
        guard let invocation = caffeinateInvocation(for: assertion),
            let pid = invocation.waitPID, isAlive(pid)
        else { return nil }
        return (pid, processName(forPID: pid))
    }

    /// How this hold will end — "until a task finishes" / timed / indefinite.
    func holdLifetime(for assertion: PowerAssertion) -> HoldLifetime {
        if case .watching = watchStatus, isThisHoldWatched(assertion) {
            return .untilWatchedFinishes
        }
        if let target = agentWaitTarget(for: assertion) {
            return .untilProcess(target.label)
        }
        if let invocation = caffeinateInvocation(for: assertion), invocation.timeoutSeconds != nil {
            return .timed(reArms: isAgentSession(assertion))
        }
        if assertion.reason.autoReleaseSeconds != nil {
            return .timed(reArms: isAgentSession(assertion))
        }
        return .indefinite
    }

    private func isThisHoldWatched(_ assertion: PowerAssertion) -> Bool {
        guard let watched = agentWatcher.watchedTargetPID else { return false }
        return agentWaitTarget(for: assertion)?.pid == watched
    }

    // MARK: Row actions (reveal / copy)

    /// The owning app's name when this hold's pid is a regular GUI app we can
    /// bring to the front, else nil (daemon / CLI holds use Activity Monitor).
    func frontableAppName(for assertion: PowerAssertion) -> String? {
        guard let app = NSRunningApplication(processIdentifier: assertion.pid),
            app.activationPolicy == .regular, let name = app.localizedName
        else { return nil }
        return name
    }

    func bringToFront(_ assertion: PowerAssertion) {
        NSRunningApplication(processIdentifier: assertion.pid)?.activate()
    }

    func openActivityMonitor() {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.ActivityMonitor")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copy a plain-text summary of a hold to the clipboard.
    func copyDetails(_ assertion: PowerAssertion) {
        var lines = [rowTitle(for: assertion), "Why: \(displayReason(for: assertion))"]
        if let label = provenanceResolver.provenance(for: assertion.pid)?.sessionLabel {
            lines.append("Origin: \(label)")
        }
        if let device = audioDeviceLabel(for: assertion) { lines.append("Device: \(device)") }
        lines.append("Ends: \(holdLifetime(for: assertion).detailLabel)")
        lines.append("Process: \(assertion.processName) (pid \(assertion.pid))")
        lines.append("Type: \(assertion.assertionType)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: Rest & restart (uptime + recommendation)

    /// Seconds since the Mac last booted, or nil if boot time couldn't be read.
    var uptime: TimeInterval? { bootTime.map { now().timeIntervalSince($0) } }

    /// "9 days" / "3 hours" — the headline uptime label.
    var uptimeLabel: String? { uptime.map(RestartAdvisor.uptimeLabel) }

    /// How fresh the system is, by uptime vs the user's recommendation window.
    var restartAdvice: RestartAdvice {
        guard let uptime else { return .fresh }
        return RestartAdvisor.advice(
            uptime: uptime, recommendAfterDays: settings.restartRecommendationDays)
    }

    /// The calm header line — only when a restart is at least worth considering.
    var restartHint: String? {
        guard let label = uptimeLabel, restartAdvice != .fresh else { return nil }
        return RestartAdvisor.message(restartAdvice, uptimeLabel: label)
    }

    /// The list banner — a projection of `outlook`, so it can never contradict the
    /// header. Nil when there are no system-sleep blockers (use the empty state).
    var sleepBanner: SleepVerdict? {
        outlook.banner(hasHolds: !groupedSystemBlockers.isEmpty, anyIndefinite: anyIndefiniteHold)
    }

    /// CPU evidence for this hold's row, keyed to the real owner behind a
    /// daemon-mediated hold. Nil for holds whose category is inherently low-CPU
    /// (media/call/backup/…), where a ~0% reading is not evidence of staleness.
    func staleEvidence(for assertion: PowerAssertion) -> StaleEvidence? {
        guard assertion.reason.category.cpuReflectsActivity else { return nil }
        return staleEvidence[assertion.onBehalfOfPID ?? assertion.pid]
    }

    /// The subtitle evidence token when this hold looks stale, else nil.
    func staleLabel(for assertion: PowerAssertion) -> String? {
        staleEvidence(for: assertion)?.isStale == true ? "~0% CPU \u{2014} likely stale" : nil
    }

    /// A per-row verdict, projected from `outlook` + the hold's lifetime — upgraded
    /// from heuristic classification to CPU *evidence* when an indefinite hold has
    /// been demonstrably idle for the stale window AND the app would actually sleep
    /// after you step away. In every other outlook (a real rail holds, auto-sleep is
    /// off, or you're deliberately keeping the Mac awake) the honest base verdict
    /// stands and only the subtitle carries the ~0%-CPU token.
    func rowVerdict(for assertion: PowerAssertion) -> SleepVerdict {
        let lifetime = holdLifetime(for: assertion)
        let base = outlook.rowVerdict(for: lifetime)
        guard lifetime == .indefinite,
            outlook.overridesIndefiniteHoldsAfterIdle,
            let evidence = staleEvidence(for: assertion), evidence.isStale
        else { return base }
        return SleepVerdict(
            glyph: "checkmark",
            text:
                "Idle \(Format.duration(evidence.quietSeconds)) at ~0% CPU \u{2014} likely stale, safe to sleep",
            tone: .calm)
    }

    /// True when any grouped hold is indefinite — decides banner tone.
    private var anyIndefiniteHold: Bool {
        groupedSystemBlockers.contains { holdLifetime(for: $0.representative) == .indefinite }
    }

    /// Whether a hold's provenance traces back to a known AI agent (Claude Code…).
    func isAgentSession(_ assertion: PowerAssertion) -> Bool {
        guard let provenance = provenanceResolver.provenance(for: assertion.pid) else {
            return false
        }
        if provenance.originKind == .agentHost { return true }
        return AgentRegistry.identify(
            originApp: provenance.originDisplayName,
            bundleID: provenance.originApp?.bundleIdentifier,
            processNames: provenance.parentChain.map(\.name))?.isAIAgent == true
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Holder pids whose one-click watch offer the user dismissed (per session).
    @Published private var watchSuggestionDismissed: Set<pid_t> = []

    func dismissWatchSuggestion(forHolder pid: pid_t) { watchSuggestionDismissed.insert(pid) }

    /// Mark the inline "what's keeping it awake?" explainer as seen (so it
    /// auto-opens only the first time).
    func markAwakeExplainerSeen() {
        if !settings.hasSeenAwakeExplainer { settingsStore.settings.hasSeenAwakeExplainer = true }
    }

    /// Whether to show the inline "Sleep when it finishes" offer for an agentic
    /// `caffeinate -w` hold (not dismissed, target alive, nothing watched yet).
    func shouldOfferWatch(for assertion: PowerAssertion) -> Bool {
        guard case .idle = watchStatus, !watchSuggestionDismissed.contains(assertion.pid) else {
            return false
        }
        return agentWaitTarget(for: assertion) != nil
    }

    /// A short origin crumb for the menu row — "Claude Code · ~/myrepo" / "Terminal".
    func originCrumb(for assertion: PowerAssertion) -> String? {
        guard let p = provenanceResolver.provenance(for: assertion.pid) else { return nil }
        switch (p.originDisplayName, p.projectLabel) {
        case (let name?, let project?): return "\(name) · \(project)"
        case (let name?, nil): return name
        case (nil, let project?): return project
        default: return nil
        }
    }

    /// When the auto-sleep-on-agent-finish setting is on and nothing is watched
    /// yet, arm the watcher on a recognized agentic `caffeinate -w <pid>`.
    private func autoArmAgentWatchIfNeeded() {
        guard settings.autoSleepWhenAgentFinishes, case .idle = watchStatus else { return }
        for assertion in assertions where assertion.blocksSystemSleep {
            guard let target = agentWaitTarget(for: assertion), isAgentSession(assertion) else {
                continue
            }
            agentWatcher.setTarget(.pid(target.pid))
            watchStatus = agentWatcher.status
            return
        }
    }

    // MARK: The tick

    func tick() {
        let s = settings
        // Never treat our own keep-awake assertion as a third-party blocker: the
        // blocker rows, counts, firewall queue, and SafetyRails media detection
        // must only ever see *other* processes' holds. (`--scan` still lists it,
        // tagged, for honesty — a separate `--keep-awake` process is a real hold
        // and intentionally stays visible.)
        assertions = telemetry.scan().filter { $0.pid != Self.ownPID }
        idleSeconds = idleMonitor.secondsSinceLastInput()
        power = powerReader.snapshot()
        thermalState = thermalProvider()

        let systemBlockers = assertions.filter(\.blocksSystemSleep)
        let whitelistedAwake =
            systemBlockers
            .filter { rulesEngine.isActivelyAllowed($0, now: now()) }
            .map(\.displayName)
            .removingDuplicates()

        // Expire a lapsed quiet window so the UI and logic see it as over.
        if let until = quietUntil, now() >= until { quietUntil = nil }
        let quietWindowActive = quietUntil != nil

        var decision = SafetyRails.evaluate(
            assertions: assertions,
            power: power,
            thermalState: thermalState,
            idleSeconds: idleSeconds,
            whitelistedAwakeAppNames: whitelistedAwake,
            settings: s
        )
        // Schedules: stand down from forcing sleep during the user's active
        // hours — but NOT when a safety rail (battery floor / thermal) wants to
        // drop holds, so the floor can still protect the battery during work hours.
        if !decision.shouldDropKeepAwake,
            let scheduleHold = ScheduleEngine.activeHoursHoldReason(now: now(), settings: s)
        {
            decision.holdForceSleepReasons.append(scheduleHold)
        }
        self.decision = decision

        // A quiet window only *holds the Mac awake* while the safety rails permit
        // it. When the battery floor / thermal pressure forces holds to drop, the
        // window stops holding — and force-sleep must re-engage rather than leave
        // the Mac in a "neither sleeps nor stays awake" limbo.
        let quietWindowHoldingAwake = quietWindowActive && !decision.shouldDropKeepAwake

        // Triggers: conditional keep-awake while a rule is satisfied (an app is
        // running / on AC / CPU busy). Sampled only when rules exist, and dropped
        // under a safety rail like every other hold.
        let triggerReason: String? = {
            guard !s.triggers.isEmpty, !decision.shouldDropKeepAwake else { return nil }
            let signals = triggerSampler.sample(onACPower: !power.onBattery)
            return TriggerEngine.activeReason(rules: s.triggers, signals: signals)
        }()
        activeTriggerReason = triggerReason
        let triggerHolding = triggerReason != nil

        // 1) Reconcile keep-awake holds (caffeine + strict takeover + quiet
        //    window + triggers) — all dropped when a safety rail demands it.
        //    Strict takeover only holds while the master switch is on: with the
        //    switch off, nothing would ever sleep the Mac, so the hold would be
        //    a "never sleeps" dead end rather than a takeover.
        let strictTakeoverHolding = s.strictTakeoverMode && s.decaffeinateEnabled
        let wantsAwake =
            (s.caffeinateEnabled || strictTakeoverHolding || quietWindowActive || triggerHolding)
            && !decision.shouldDropKeepAwake
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

        // Track per-session first-seen (with grace) and snapshot the coalesced
        // rows, so the menu shows one stable row per agent session.
        updateSessionTracking(systemBlockers)
        groupedSystemBlockers = computeGroupedSystemBlockers()

        // Close the Sleep-Now feedback loop and expire stale errors.
        reconcilePendingSleepFeedback()

        // 2.5) Agent watcher: optionally auto-arm on a recognized agent task, then
        // detect when a watched build/agent has finished.
        autoArmAgentWatchIfNeeded()
        agentWatcher.tick(now: now(), systemBlockingPIDs: Set(systemBlockers.map(\.pid)))
        watchStatus = agentWatcher.status
        let agentFinished = agentWatcher.hasCompleted

        // 2.6) Stale-holder CPU evidence: sample each system-sleep holder's process
        //       subtree; a holder that keeps asserting but has been ~0% CPU for a
        //       sustained window is likely a leaked/forgotten hold. This LABELS the
        //       row (and, only where the app would actually sleep, its verdict) —
        //       it never forces sleep. Gated to non-empty holders so no libproc runs
        //       when nothing holds the Mac awake. Daemon-mediated holds are keyed to
        //       the real owner (`onBehalfOfPID`), so a broker's idleness isn't read
        //       as the app's. Only holders whose category makes CPU a valid activity
        //       proxy are sampled — media/backup/call holds are low-CPU by nature.
        let evidenceRoots = Set(
            systemBlockers
                .filter { $0.reason.category.cpuReflectsActivity }
                .map { $0.onBehalfOfPID ?? $0.pid })
        let subtreeSamples =
            evidenceRoots.isEmpty ? [:] : subtreeSampler.sampleSubtrees(evidenceRoots, now: now())
        staleEvidence = staleDetector.update(
            samples: subtreeSamples, holding: evidenceRoots, now: now())

        // 3) Immediate-sleep guards (overheating / critically low battery). These
        //    run regardless of `decaffeinateEnabled` — overheating in a bag is a
        //    safety backstop, not an opt-in (the UI says so). They use a separate
        //    short cooldown so a persistent condition can't spawn pmset every
        //    second, without inheriting the idle path's 60s cooldown.
        if decision.mustSleepNow {
            if forceSleep(
                reason: decision.immediateSleepReasons.first ?? "Safety guard",
                bypassCooldown: false, immediate: true)
            {
                return
            }
        }

        // 4) The headline feature: force sleep when left idle. Once a watched
        //    agent/build has finished, collapse the idle requirement to a short
        //    grace so the Mac sleeps soon after you've stepped away.
        //    Suppressed while the user is intentionally caffeinating.
        //    Like the quiet window and triggers, the keep-awake toggle only
        //    counts as holding while the safety rails permit it — once the
        //    battery floor / thermal rail drops the hold, force-sleep must
        //    re-engage rather than leave the Mac awake and draining until the
        //    3%-critical emergency guard.
        let caffeinateHolding = s.caffeinateEnabled && !decision.shouldDropKeepAwake
        var remaining: TimeInterval?
        if s.decaffeinateEnabled, !caffeinateHolding, !quietWindowHoldingAwake, !triggerHolding {
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
                        // Notify before clearing the target so we can still read the label.
                        if settings.notifyOnAgentFinished,
                            case .completed(let label, _) = watchStatus
                        {
                            notifier.notifyAgentFinished(label: label)
                        }
                        agentWatcher.setTarget(nil)
                        watchStatus = agentWatcher.status
                    }
                    return
                }
            }
        }

        updateDerivedState(
            decision: decision,
            remaining: remaining,
            agentFinished: agentFinished)

        evaluateRestartOverdueNotification()
    }

    // MARK: Restart-overdue notification

    /// Fire a notification on the first crossing into `.overdue`, and again when
    /// escalating to `.urgent` (the networking-cliff threshold). Silent on every
    /// other tick. Persisted per boot session so relaunches don't re-nag.
    private func evaluateRestartOverdueNotification() {
        guard settings.notifyOnRestartOverdue, let label = uptimeLabel else { return }
        let advice = restartAdvice
        let prevIsOverdueOrHigher =
            lastNotifiedRestartAdvice.map { $0 == .overdue || $0 == .urgent } ?? false
        let isOverdueOrHigher = advice == .overdue || advice == .urgent
        // Re-fire when escalating from .overdue → .urgent — that's the serious
        // networking-cliff threshold and deserves its own nudge.
        let isEscalatingToUrgent = lastNotifiedRestartAdvice == .overdue && advice == .urgent
        if isOverdueOrHigher, !prevIsOverdueOrHigher || isEscalatingToUrgent {
            notifier.notifyRestartOverdue(uptimeLabel: label)
        }
        updateLastNotifiedRestartAdvice(advice)
    }

    // MARK: Restart-advice persistence (survives relaunches, resets on real restart)

    private func loadPersistedRestartNotificationState() -> RestartAdvice? {
        guard
            let dict = settingsStore.defaults.dictionary(forKey: Self.lastNotifiedAdviceKey),
            let storedBootSecs = dict["bootSecs"] as? Double,
            let rawAdvice = dict["advice"] as? String,
            let storedAdvice = RestartAdvice(rawValue: rawAdvice),
            let currentBoot = bootTime,
            abs(currentBoot.timeIntervalSince1970 - storedBootSecs) < 60
        else { return nil }
        return storedAdvice
    }

    private func updateLastNotifiedRestartAdvice(_ newAdvice: RestartAdvice) {
        guard newAdvice != lastNotifiedRestartAdvice else { return }
        lastNotifiedRestartAdvice = newAdvice
        guard let currentBoot = bootTime else { return }
        settingsStore.defaults.set(
            ["bootSecs": currentBoot.timeIntervalSince1970, "advice": newAdvice.rawValue],
            forKey: Self.lastNotifiedAdviceKey)
    }

    /// Mirror the keep-awake window to the injected defaults (called from
    /// `quietUntil.didSet`) so an intent/URL-scheme hold survives a relaunch.
    private func persistQuietUntil() {
        if let quietUntil {
            settingsStore.defaults.set(quietUntil, forKey: Self.quietUntilKey)
        } else {
            settingsStore.defaults.removeObject(forKey: Self.quietUntilKey)
        }
    }

    // MARK: Force sleep

    private var isForceSleepSuppressed: Bool {
        guard let until = suppressForceSleepUntil else { return false }
        return now() < until
    }

    private var isImmediateSuppressed: Bool {
        guard let until = suppressImmediateUntil else { return false }
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
    private func forceSleep(
        reason: String, bypassCooldown: Bool, immediate: Bool = false, userInitiated: Bool = false
    ) -> Bool {
        let suppressed = immediate ? isImmediateSuppressed : isForceSleepSuppressed
        if !bypassCooldown, suppressed { return false }

        switch sleepController.sleepNow() {
        case .success:
            AppLog.engine.notice(
                "Forced sleep: \(reason, privacy: .public) (immediate=\(immediate), userInitiated=\(userInitiated), onBattery=\(self.power.onBattery))"
            )
            clearError()
            // Arm the idle cooldown so we don't re-sleep right after wake.
            suppressForceSleepUntil = now().addingTimeInterval(idleCooldownSeconds)
            if immediate {
                suppressImmediateUntil = now().addingTimeInterval(immediateCooldownSeconds)
            }
            // Don't claim we slept yet — "pmset launched" isn't "the kernel slept."
            // systemWillSleep() records it only if the transition actually happens;
            // reconcilePendingSleepFeedback() surfaces a user sleep that never took.
            pendingForcedSleep = (reason, now(), power.onBattery, userInitiated)
            return true
        case .failure(let error):
            setError(error.description)
            suppressForceSleepUntil = now().addingTimeInterval(failureCooldownSeconds)
            if immediate {
                suppressImmediateUntil = now().addingTimeInterval(failureCooldownSeconds)
            }
            return false
        }
    }

    private func setError(_ message: String) {
        lastError = message
        lastErrorAt = now()
    }

    private func clearError() {
        lastError = nil
        lastErrorAt = nil
    }

    /// Close the two feedback loops the app used to leave silent: a user's
    /// **Sleep Now** that never actually slept (an app is holding system sleep
    /// open), and a transient error that would otherwise linger forever.
    private func reconcilePendingSleepFeedback() {
        if let pending = pendingForcedSleep, pending.userInitiated,
            now().timeIntervalSince(pending.requestedAt) > userSleepFeedbackSeconds
        {
            setError("The Mac didn\u{2019}t sleep \u{2014} an app is holding system sleep open.")
            pendingForcedSleep = nil
        }
        if let at = lastErrorAt, now().timeIntervalSince(at) > errorVisibilitySeconds {
            clearError()
        }
    }

    /// The Mac just finished waking (NSWorkspace.didWake). Grace the idle engine:
    /// HID idle survives the sleep as wall-clock time, so a wake with no fresh
    /// input yet (lid open, scheduled wake) reads as hours idle on the very next
    /// tick — without this, pmset would fire straight back in the user's face.
    /// (The pmset-time cooldown only covers sleeps shorter than itself.) The
    /// immediate thermal/battery guards keep their own separate cooldown.
    /// Internal (not private) so tests can drive it without a live NSWorkspace.
    func systemDidWake() {
        suppressForceSleepUntil = now().addingTimeInterval(idleCooldownSeconds)
    }

    /// The kernel is beginning a real sleep transition (NSWorkspace.willSleep).
    /// If we recently launched a forced sleep, this confirms it actually took, so
    /// now — and only now — do we record it. Otherwise it's a natural/user sleep
    /// (lid close, Apple menu → Sleep, macOS idle) and we log it as such.
    /// Internal (not private) so tests can drive it without a live NSWorkspace.
    func systemWillSleep() {
        let when = now()
        if let pending = pendingForcedSleep,
            when.timeIntervalSince(pending.requestedAt) <= forcedSleepConfirmationWindow
        {
            lastSleepAt = when
            lastSleepReason = pending.reason
            history.record(
                SleepEvent(date: when, reason: pending.reason, onBattery: pending.onBattery))
            restHistory.record(
                RestEvent(date: when, kind: .forcedSleep, onBattery: pending.onBattery))
            if settings.notifyOnForcedSleep {
                notifier.notifyForcedSleep(reason: pending.reason)
            }
        } else {
            restHistory.record(
                RestEvent(date: when, kind: .systemSleep, onBattery: power.onBattery))
        }
        pendingForcedSleep = nil
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
            if rulesEngine.hasEffectiveDecision(for: blocker, now: now()) { continue }
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
            notifier.notifyNewBlocker(
                appName: blocker.displayName, reason: blocker.reason.category.label)
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

    // MARK: Session identity & coalescing (stable across `caffeinate -t` respawns)

    /// A stable identity for a hold that survives the agent's `caffeinate -t`
    /// respawns. Agent holds coalesce by (agent + project folder + terminal);
    /// everything else keeps its own per-assertion identity, so non-agent rows
    /// never merge and behave exactly as before.
    func sessionKey(for assertion: PowerAssertion) -> String {
        guard isAgentSession(assertion),
            let provenance = provenanceResolver.provenance(for: assertion.pid)
        else {
            return "solo:" + assertion.id
        }
        let agent = (provenance.originDisplayName ?? "agent").lowercased()
        let folder = (provenance.cwd ?? "·").lowercased()
        let tty = provenance.ttyName ?? "·"
        return "agent:\(agent)|\(folder)|\(tty)"
    }

    /// Record first-/last-seen per session key, pruning a key only after it's
    /// been absent past the grace period (so a respawn gap doesn't reset it).
    private func updateSessionTracking(_ systemBlockers: [PowerAssertion]) {
        let t = now()
        var liveKeys: Set<String> = []
        for blocker in systemBlockers {
            let k = sessionKey(for: blocker)
            liveKeys.insert(k)
            sessionLastSeen[k] = t
            // Anchor to the real assertion start (up to ~5 min old for a hold that
            // predates app launch), and back-date if a concurrent member is older —
            // a respawn is always newer, so this only ever improves the estimate.
            let start = blocker.createdAt ?? t
            if let existing = sessionFirstSeen[k] {
                if start < existing { sessionFirstSeen[k] = start }
            } else {
                sessionFirstSeen[k] = start
            }
        }
        for (k, last) in sessionLastSeen where !liveKeys.contains(k) {
            if t.timeIntervalSince(last) > sessionGracePeriod {
                sessionFirstSeen.removeValue(forKey: k)
                sessionLastSeen.removeValue(forKey: k)
            }
        }
    }

    /// The stable "holding since" anchor for a hold's session, if tracked.
    func sessionAnchor(for assertion: PowerAssertion) -> Date? {
        sessionFirstSeen[sessionKey(for: assertion)]
    }

    /// Seconds a session has been continuously holding — anchored to its first
    /// sighting, not the current process's `createdAt`, so a `-t` respawn doesn't
    /// reset it. Falls back to the assertion's own age when untracked.
    func sessionHeldSeconds(for assertion: PowerAssertion) -> TimeInterval? {
        if let first = sessionAnchor(for: assertion) {
            return now().timeIntervalSince(first)
        }
        if let created = assertion.createdAt { return now().timeIntervalSince(created) }
        return nil
    }

    /// "for 12m" — the stable, respawn-proof held duration string.
    func sessionHeldDuration(for assertion: PowerAssertion) -> String? {
        sessionHeldSeconds(for: assertion).map { "for " + Format.duration($0) }
    }

    /// Coalesce the live system-blocking holds into stable rows: one group per
    /// agent session, singletons for everything else. Order follows the scan sort
    /// (first occurrence of each key).
    private func computeGroupedSystemBlockers() -> [HoldGroup] {
        let blockers = assertions.filter(\.blocksSystemSleep)
        var order: [String] = []
        var bucket: [String: [PowerAssertion]] = [:]
        for blocker in blockers {
            let k = sessionKey(for: blocker)
            if bucket[k] == nil { order.append(k) }
            bucket[k, default: []].append(blocker)
        }
        let groups = order.map { k in
            let members = bucket[k] ?? []
            let rep = representative(of: members)
            return HoldGroup(
                id: k, representative: rep, members: members,
                isAgentSession: isAgentSession(rep), firstSeen: sessionFirstSeen[k])
        }
        // Stable, alphabetic by the user-visible title — so churning agent rows
        // (all named "caffeinate") no longer float up and down with pid order.
        return groups.sorted {
            Self.stableTitleOrder($0.id, $1.id, groupTitle(for: $0), groupTitle(for: $1))
        }
    }

    /// Pick a stable representative so the row's label/icon doesn't flicker as
    /// pids churn: the longest-lived member, tie-broken by lowest pid.
    private func representative(of members: [PowerAssertion]) -> PowerAssertion {
        members.min { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case (let l?, let r?) where l != r: return l < r
            default: return lhs.pid < rhs.pid
            }
        } ?? members[0]
    }

    /// The user-visible title for a group's row (matches `RDRow.titleText`).
    func groupTitle(for group: HoldGroup) -> String { rowTitle(for: group.representative) }

    /// The user-visible title for a single hold — agent crumb, else app name. An
    /// unattributed audio hold (bare "coreaudiod") reads clearer titled by its
    /// device, so several audio sources are distinguishable at a glance.
    func rowTitle(for assertion: PowerAssertion) -> String {
        if isAgentSession(assertion), let crumb = originCrumb(for: assertion) { return crumb }
        // A genuinely unattributed audio hold (bare daemon — no real owner, no
        // bundle) reads clearer titled by its device than "coreaudiod".
        if assertion.realOwner == nil, assertion.bundleIdentifier == nil,
            let device = audioDeviceLabel(for: assertion)
        {
            return device
        }
        return assertion.displayName
    }

    /// Order two rows alphabetically by their visible title, with a deterministic
    /// identity tiebreaker so equal titles never reorder frame-to-frame.
    static func stableTitleOrder(_ lid: String, _ rid: String, _ lt: String, _ rt: String) -> Bool {
        switch lt.localizedCaseInsensitiveCompare(rt) {
        case .orderedSame: return lid < rid
        case let order: return order == .orderedAscending
        }
    }

    /// `assertions` not holding system sleep (screen-only / background), sorted
    /// with the same stable alphabetic order as the grouped rows.
    var sortedOtherBlockers: [PowerAssertion] {
        assertions
            .filter { !$0.blocksSystemSleep }
            .sorted { Self.stableTitleOrder($0.id, $1.id, rowTitle(for: $0), rowTitle(for: $1)) }
    }

    /// Whether this blocker still needs the user's allow/block decision. Matched
    /// by the firewall **key** (real owner / bundle / process) — the pending
    /// queue dedups per app, so a sibling assertion from the same daemon (same
    /// key, different `id`) is still "pending" and must show its approval buttons.
    func isPendingDecision(_ assertion: PowerAssertion) -> Bool {
        let k = key(assertion)
        return pendingClassification.contains { key($0) == k }
    }

    // MARK: Derived UI state

    /// Project every derived UI string from the single `SleepOutlook` — the header,
    /// the mug, and the countdown. The banner (`sleepBanner`) and row verdicts
    /// (`rowVerdict(for:)`) project from the same value, so they can never disagree.
    private func updateDerivedState(
        decision: SafetyDecision,
        remaining: TimeInterval?,
        agentFinished: Bool
    ) {
        let s = settings
        let inputs = SleepOutlookInputs(
            decaffeinateEnabled: s.decaffeinateEnabled,
            caffeinateActive: s.caffeinateEnabled && caffeine.isActive,
            caffeinateKeepsDisplayAwake: s.caffeinateKeepsDisplayAwake,
            decision: decision,
            isQuietWindowActive: isQuietWindowActive,
            quietWindowHoldingAwake: quietWindowHoldingAwake,
            quietUntil: quietUntil,
            triggerReason: (caffeine.isActive && activeTriggerReason != nil)
                ? activeTriggerReason : nil,
            idleMinutes: idleSleepMinutes,
            batteryNote: idleBatteryNote,
            idleSeconds: idleSeconds,
            agentFinished: agentFinished,
            remainingSeconds: remaining,
            activeHoldingCount: activeHoldingCount
        )
        let o = SleepOutlook.classify(inputs)
        outlook = o
        headline = o.headline
        detail = o.subline
        mug = o.mug
        secondsUntilForcedSleep = o.countdownSeconds
    }

    // MARK: Convenience for the UI

    var systemBlockerCount: Int { assertions.filter(\.blocksSystemSleep).count }

    /// Distinct things actively holding the Mac awake that you have **not**
    /// allowed — the count the headline speaks to. Agent sessions count per
    /// session (Claude in ~/repoA and ~/repoB are two), non-agent apps dedup by
    /// display name as before. (Allowed apps still appear in the list, tagged.)
    var activeHoldingCount: Int {
        let held =
            assertions
            .filter(\.blocksSystemSleep)
            .filter { !rulesEngine.isActivelyAllowed($0, now: now()) }
        let identities = held.map { isAgentSession($0) ? sessionKey(for: $0) : $0.displayName }
        return Set(identities).count
    }

    /// True when the idle force-sleep engine is currently held off for any reason
    /// (keep-awake, an active quiet window, an active-hours schedule, or a safety
    /// hold). Used so the watcher doesn't promise "sleeping soon" when it can't.
    var isAutoSleepHeld: Bool {
        (settings.caffeinateEnabled && !decision.shouldDropKeepAwake)
            || quietWindowHoldingAwake || !decision.canForceSleep
    }

    /// When a quiet window is set but a safety rail has paused its hold, why.
    var quietWindowPausedReason: String? {
        guard isQuietWindowActive, !quietWindowHoldingAwake else { return nil }
        return decision.dropKeepAwakeReasons.first ?? "Paused by a safety rail"
    }

    /// Minutes after stepping away that the Mac will sleep (battery-aware) — feeds
    /// the "step away" copy in `SleepOutlook`.
    var idleSleepMinutes: Int {
        Int(settings.effectiveIdleSeconds(onBattery: power.onBattery) / 60)
    }

    /// Whether the "(on battery)" note applies to the idle-sleep phrase.
    var idleBatteryNote: Bool {
        power.onBattery && settings.sleepSoonerOnBattery
            && settings.batteryIdleThresholdMinutes < settings.idleThresholdMinutes
    }

    /// "for 12m" since the assertion was created, if known.
    func heldDuration(_ assertion: PowerAssertion) -> String? {
        guard let created = assertion.createdAt else { return nil }
        return "for " + Format.duration(now().timeIntervalSince(created))
    }
}
