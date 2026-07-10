import Foundation

/// CPU-based evidence about whether a live system-sleep holder is actually doing
/// any work — the difference between "this app *classifies* as an indefinite
/// hold" and "this app has demonstrably been asleep at the wheel for 10 minutes
/// while still asserting." Produced by ``StaleHolderDetector``, read by the row
/// subtitle and (in the honest cases) the row verdict.
struct StaleEvidence: Equatable, Sendable {
    /// Instantaneous subtree CPU% between the last two samples; nil until two
    /// samples exist for this holder.
    let cpuPercent: Double?
    /// How long this holder has been continuously near-idle while still holding.
    let quietSeconds: TimeInterval
    /// True once `quietSeconds` clears the sustained-window bar — evidence the
    /// hold is likely leaked/forgotten. A *label*, never a force-sleep trigger.
    let isStale: Bool
}

/// Inverts ``AgentWatcher``'s quiet-window state machine. AgentWatcher declares a
/// *watched, opted-in* task finished after a short 90 s of near-idle. This
/// declares an *unwatched, third-party* hold "likely stale" — a much stronger,
/// less-invited claim — so it demands a far higher bar (10 min of continuous
/// near-0% CPU while the process is *still* asserting system-sleep). A build
/// blocked on the network or an agent between turns is briefly idle but not
/// stale; ten minutes of a flat line is.
///
/// Pure value type: it takes `ProcessSample`s in and returns evidence out, so the
/// whole window/threshold logic is unit-testable without libproc. It never sleeps
/// anything and holds no reference to the sleep engine.
struct StaleHolderDetector: Equatable {
    /// Near-idle ceiling (reused from AgentWatcher's `cpuThresholdPercent`): at or
    /// below this subtree CPU%, the holder counts as quiet.
    var cpuThresholdPercent: Double = 5
    /// Continuous quiet time before a hold is labelled stale. Deliberately far
    /// above AgentWatcher's 90 s — see the type doc.
    var requiredStaleSeconds: TimeInterval = 600

    /// Per-holder rolling state.
    private var lastSample: [pid_t: ProcessSample] = [:]
    private var quietSince: [pid_t: Date] = [:]

    init(cpuThresholdPercent: Double = 5, requiredStaleSeconds: TimeInterval = 600) {
        self.cpuThresholdPercent = cpuThresholdPercent
        self.requiredStaleSeconds = requiredStaleSeconds
    }

    /// Fold this tick's samples for the currently-`holding` pids and return the
    /// evidence for each. `samples` maps holder pid → its subtree sample (an empty
    /// sample when the process is gone). Holders no longer in `holding` are pruned.
    mutating func update(
        samples: [pid_t: ProcessSample], holding: Set<pid_t>, now: Date
    ) -> [pid_t: StaleEvidence] {
        var evidence: [pid_t: StaleEvidence] = [:]
        for pid in holding {
            let sample = samples[pid] ?? .empty
            let cpu = cpuPercent(from: lastSample[pid], to: sample)
            lastSample[pid] = sample

            // Unknown CPU (first sample) and a vanished subtree both count as
            // "busy" — i.e. NOT evidence of staleness. We only ever label a hold
            // stale on positive evidence of sustained idleness.
            let busy = !sample.exists || (cpu ?? cpuThresholdPercent + 1) > cpuThresholdPercent
            if busy {
                quietSince[pid] = nil
                evidence[pid] = StaleEvidence(cpuPercent: cpu, quietSeconds: 0, isStale: false)
            } else {
                let since = quietSince[pid] ?? now
                quietSince[pid] = since
                let quiet = now.timeIntervalSince(since)
                evidence[pid] = StaleEvidence(
                    cpuPercent: cpu, quietSeconds: quiet, isStale: quiet >= requiredStaleSeconds)
            }
        }
        lastSample = lastSample.filter { holding.contains($0.key) }
        quietSince = quietSince.filter { holding.contains($0.key) }
        return evidence
    }

    /// Instantaneous subtree CPU% between two cumulative-CPU samples. A lower
    /// current reading than the previous one (a `proc_pidinfo` read racing an
    /// exit) clamps to 0% rather than reading as a negative/huge delta.
    private func cpuPercent(from previous: ProcessSample?, to current: ProcessSample) -> Double? {
        guard let previous, previous.exists else { return nil }
        let elapsed = current.at.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return nil }
        let delta =
            current.cpuNanoseconds >= previous.cpuNanoseconds
            ? current.cpuNanoseconds - previous.cpuNanoseconds : 0
        return Double(delta) / 1_000_000_000.0 / elapsed * 100.0
    }
}
