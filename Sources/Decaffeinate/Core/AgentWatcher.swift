import Foundation

/// Watches a process subtree (a build, an agent, a long job) and decides when it
/// has *finished*, so Decaffeinate can let the Mac sleep — the headline
/// "sleep after my agent is done" feature.
///
/// Completion = the subtree's CPU has stayed below a threshold for a sustained
/// quiet window **and** it no longer holds a system-sleep assertion, or the
/// subtree has exited entirely. The CPU-rate maths and the quiet-window state
/// live here; the actual PID/CPU sampling is injected (`ProcessSampling`) so
/// this is fully unit-testable.
@MainActor
final class AgentWatcher {
    enum Status: Equatable {
        case idle
        case waiting(label: String)  // target set but not yet seen running
        case watching(label: String, cpuPercent: Double?)
        case completed(label: String, reason: String)
    }

    var cpuThresholdPercent: Double = 5
    var requiredQuietSeconds: TimeInterval = 90

    private let sampler: any ProcessSampling
    private var target: WatchTarget?
    private var lastSample: ProcessSample?
    private var quietSince: Date?
    private var everRan = false

    private(set) var status: Status = .idle

    init(sampler: any ProcessSampling = ProcessWatcher()) {
        self.sampler = sampler
    }

    /// `true` once the watched work has finished (until the target is changed).
    var hasCompleted: Bool {
        if case .completed = status { return true }
        return false
    }

    var isActive: Bool { target != nil && !hasCompleted }

    func setTarget(_ newTarget: WatchTarget?) {
        target = newTarget
        lastSample = nil
        quietSince = nil
        everRan = false
        status = newTarget.map { .waiting(label: $0.label) } ?? .idle
    }

    /// Advance the watcher one tick. `systemBlockingPIDs` are the PIDs currently
    /// holding a system-sleep assertion (so a still-working subtree that holds an
    /// assertion is never considered finished).
    func tick(now: Date, systemBlockingPIDs: Set<pid_t>) {
        guard let target, !hasCompleted else { return }

        let sample = sampler.sample(target, now: now)
        defer { lastSample = sample }

        guard sample.exists else {
            // Only call it "done" if we actually saw it running first — otherwise
            // a not-yet-started or mistyped target would complete instantly.
            if everRan {
                status = .completed(
                    label: target.label, reason: "\(target.label) is no longer running")
            } else {
                status = .waiting(label: target.label)
            }
            return
        }

        everRan = true
        let holdsAssertion = !sample.pids.isDisjoint(with: systemBlockingPIDs)
        let cpu = cpuPercent(from: lastSample, to: sample)
        // Unknown CPU (first sample) counts as "busy" so we never complete early.
        let busy = holdsAssertion || (cpu ?? 100) >= cpuThresholdPercent

        if busy {
            quietSince = nil
            status = .watching(label: target.label, cpuPercent: cpu)
            return
        }

        let since = quietSince ?? now
        quietSince = since
        if now.timeIntervalSince(since) >= requiredQuietSeconds {
            status = .completed(label: target.label, reason: "\(target.label) finished")
        } else {
            status = .watching(label: target.label, cpuPercent: cpu)
        }
    }

    private func cpuPercent(from previous: ProcessSample?, to current: ProcessSample) -> Double? {
        guard let previous, previous.exists else { return nil }
        let elapsed = current.at.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return nil }
        let deltaNanos =
            current.cpuNanoseconds >= previous.cpuNanoseconds
            ? current.cpuNanoseconds - previous.cpuNanoseconds : 0
        return (Double(deltaNanos) / 1_000_000_000.0) / elapsed * 100.0
    }
}
