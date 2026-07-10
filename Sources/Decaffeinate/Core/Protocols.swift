import Foundation

/// Seams for ``AppState``'s system dependencies, so the decision loop can be
/// driven by fakes in tests. Each protocol is satisfied by the real engine in
/// production (via the defaults on `AppState.init`) — zero behaviour change —
/// and by a fake in `AppStateTests`.
///
/// All are `@MainActor` because `AppState` and the stateful engines
/// (`CaffeineEngine`, `Notifier`) live on the main actor.

@MainActor
protocol PowerAssertionScanning {
    func scan() -> [PowerAssertion]
}

@MainActor
protocol IdleReading {
    func secondsSinceLastInput() -> TimeInterval
}

@MainActor
protocol PowerReading {
    func snapshot() -> PowerSnapshot
}

@MainActor
protocol SystemSleeping {
    @discardableResult
    func sleepNow() -> Result<Void, SleepController.SleepError>
    @discardableResult
    func displayOffNow() -> Result<Void, SleepController.SleepError>
}

@MainActor
protocol KeepAwakeControlling {
    var isActive: Bool { get }
    func update(keepSystemAwake: Bool, keepDisplayAwake: Bool, reason: String)
    func releaseAll()
}

@MainActor
protocol BlockerNotifying {
    func requestAuthorizationIfNeeded()
    /// `reason` must be a non-identifying, classified label (e.g. "Playing
    /// media"), never raw app-supplied assertion text — notifications surface on
    /// the lock screen.
    func notifyNewBlocker(appName: String, reason: String)
    /// Posted when a confirmed forced sleep actually happens.
    func notifyForcedSleep(reason: String)
    /// Posted when a watched build/agent finishes and the Mac is sleeping now.
    func notifyAgentFinished(label: String)
    /// Posted once when uptime crosses into the overdue/urgent band.
    func notifyRestartOverdue(uptimeLabel: String)
}

@MainActor
protocol ProcessSampling {
    /// Sample the watched process subtree right now. Returns an empty sample
    /// (`pids` empty) when no matching process is running.
    func sample(_ target: WatchTarget, now: Date) -> ProcessSample
}

@MainActor
protocol SubtreeCPUSampling {
    /// Sample each pid-rooted subtree against ONE machine snapshot, folding each
    /// holder's cumulative CPU monotonically. A non-running root returns an empty
    /// sample. Used for stale-holder CPU evidence.
    func sampleSubtrees(_ roots: Set<pid_t>, now: Date) -> [pid_t: ProcessSample]
}

@MainActor
protocol SystemStateReading {
    /// The kernel boot time, or nil if it can't be read. Uptime = now − bootTime.
    func bootTime() -> Date?
}

@MainActor
protocol ProcessProvenanceResolving {
    /// Resolve where a holder pid came from (terminal / agent / project). Lazy &
    /// cached; safe on row-expand / first-seen. Nil when the process is gone or
    /// nothing could be read (never throws, never traps).
    func provenance(for pid: pid_t) -> ProcessProvenance?
}

// MARK: - Real engines conform

extension TelemetryEngine: PowerAssertionScanning {}
extension IdleMonitor: IdleReading {}
extension PowerSourceReader: PowerReading {}
extension SleepController: SystemSleeping {}
extension CaffeineEngine: KeepAwakeControlling {}
extension Notifier: BlockerNotifying {}
extension ProcessWatcher: ProcessSampling {}
extension SubtreeSampler: SubtreeCPUSampling {}
extension ProcessProvenanceResolver: ProcessProvenanceResolving {}
