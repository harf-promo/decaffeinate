import Darwin
import Foundation

/// Folds per-member cumulative CPU readings into one subtree total that never
/// goes backwards. Members are keyed by pid **and** start time (so a reused pid
/// is a new member); a member that vanishes between samples keeps its last-seen
/// CPU in the running total instead of being dropped.
///
/// This is the guard against the "fork-heavy build reads as idle" failure: a
/// child that forked, ran hot, and exited between two 1 Hz samples used to
/// contribute *zero* to the total, clamping the CPU delta to 0% and letting the
/// agent watcher declare a still-working job finished. Pure value type so the
/// folding rules are unit-testable without libproc.
struct SubtreeCPUAccumulator: Equatable {
    private var lastSeen: [String: UInt64] = [:]
    private var missingStreak: [String: Int] = [:]
    private var retired: UInt64 = 0
    /// Consecutive absent samples before a member's CPU is folded into
    /// `retired`. A single-sample absence is usually a `proc_pidinfo` read
    /// racing a fork/exit, not a real exit — retiring immediately and then
    /// re-adding the member on reappearance would double-count its lifetime
    /// CPU (one huge phantom delta that resets the agent quiet window).
    private let retireAfterMisses = 3

    /// Fold one sample of live members (key → cumulative CPU ns) and return the
    /// subtree's lifetime total: live members + everything that already exited.
    /// A per-process reading can only grow, so a lower value than last seen
    /// (a failed `proc_pidinfo` read racing the exit) keeps the previous one.
    mutating func fold(live: [String: UInt64]) -> UInt64 {
        var merged: [String: UInt64] = [:]
        merged.reserveCapacity(live.count)
        for (key, cpu) in live {
            merged[key] = max(cpu, lastSeen[key] ?? 0)
            missingStreak[key] = nil
        }
        for (key, cpu) in lastSeen where merged[key] == nil {
            let streak = (missingStreak[key] ?? 0) + 1
            if streak >= retireAfterMisses {
                retired &+= cpu
                missingStreak[key] = nil
            } else {
                // Carry the member at its last-seen value until the absence
                // persists — a transient miss must not move CPU into `retired`.
                missingStreak[key] = streak
                merged[key] = cpu
            }
        }
        lastSeen = merged
        return merged.values.reduce(retired, &+)
    }
}

/// Samples a process subtree's PIDs and cumulative CPU using public `libproc`
/// APIs (`proc_listallpids`, `proc_pidinfo`). No private APIs, no root.
///
/// Stateful: it accumulates the CPU of subtree members that have already exited
/// (see `SubtreeCPUAccumulator`), resetting whenever the watched target changes.
@MainActor
final class ProcessWatcher {

    private var accumulator = SubtreeCPUAccumulator()
    private var currentTarget: WatchTarget?

    func sample(_ target: WatchTarget, now: Date) -> ProcessSample {
        if target != currentTarget {
            currentTarget = target
            accumulator = SubtreeCPUAccumulator()
        }

        // Names are only needed to match `.processName` roots; a `.pid` target
        // (the auto-arm agent path) matches by pid alone, and resolving an
        // NSRunningApplication-backed name for hundreds of processes every
        // second is the single most expensive part of the sample.
        let needsNames: Bool
        if case .processName = target { needsNames = true } else { needsNames = false }
        let processes = ProcessTable.snapshot(resolveNames: needsNames)

        let roots: [pid_t]
        switch target {
        case .pid(let pid):
            roots = processes.contains(where: { $0.pid == pid }) ? [pid] : []
        case .processName(let needle):
            roots =
                processes
                .filter { $0.name.caseInsensitiveCompare(needle) == .orderedSame }
                .map(\.pid)
        }

        guard !roots.isEmpty else {
            // Retire whatever was live so the total stays monotonic if a
            // same-named root ever reappears.
            _ = accumulator.fold(live: [:])
            return ProcessSample(pids: [], cpuNanoseconds: 0, at: now)
        }

        let subtree = ProcessTable.descendants(of: Set(roots), in: processes)
        var live: [String: UInt64] = [:]
        live.reserveCapacity(subtree.count)
        for proc in processes where subtree.contains(proc.pid) {
            live["\(proc.pid)-\(proc.startTime)"] = ProcessTable.cpuNanoseconds(pid: proc.pid)
        }
        let cpu = accumulator.fold(live: live)
        return ProcessSample(pids: subtree, cpuNanoseconds: cpu, at: now)
    }
}
