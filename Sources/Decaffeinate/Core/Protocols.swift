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
}

@MainActor
protocol ProcessSampling {
    /// Sample the watched process subtree right now. Returns an empty sample
    /// (`pids` empty) when no matching process is running.
    func sample(_ target: WatchTarget, now: Date) -> ProcessSample
}

// MARK: - Real engines conform

extension TelemetryEngine: PowerAssertionScanning {}
extension IdleMonitor: IdleReading {}
extension PowerSourceReader: PowerReading {}
extension SleepController: SystemSleeping {}
extension CaffeineEngine: KeepAwakeControlling {}
extension Notifier: BlockerNotifying {}
extension ProcessWatcher: ProcessSampling {}
