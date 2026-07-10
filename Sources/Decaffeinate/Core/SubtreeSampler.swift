import Foundation

/// Samples several holder subtrees per tick against **one** machine snapshot.
///
/// `ProcessWatcher` is single-target (it resets its accumulator whenever the
/// watched target changes) and re-enumerates the whole machine on every call, so
/// round-robining N holders through it would both wipe state and cost
/// O(procs × holders) every second. This sampler enumerates once
/// (`ProcessTable.snapshot`) and evaluates each holder's subtree against that
/// single snapshot — O(procs + Σ subtrees) — while keeping a per-holder
/// `SubtreeCPUAccumulator` so each holder's total stays monotonic across
/// fork-heavy churn and pid reuse.
///
/// Pure libproc, in-process — no subprocess. Called only when holders exist.
@MainActor
final class SubtreeSampler {

    private var accumulators: [pid_t: SubtreeCPUAccumulator] = [:]

    func sampleSubtrees(_ roots: Set<pid_t>, now: Date) -> [pid_t: ProcessSample] {
        guard !roots.isEmpty else {
            accumulators = [:]
            return [:]
        }

        let processes = ProcessTable.snapshot(resolveNames: false)
        let childrenByParent = ProcessTable.childrenByParent(processes)
        let livePIDs = Set(processes.map(\.pid))

        var out: [pid_t: ProcessSample] = [:]
        out.reserveCapacity(roots.count)
        for root in roots {
            var accumulator = accumulators[root] ?? SubtreeCPUAccumulator()
            defer { accumulators[root] = accumulator }

            guard livePIDs.contains(root) else {
                // Root gone: retire whatever was live so the total stays monotonic
                // if the same pid ever reappears, and report an empty sample.
                _ = accumulator.fold(live: [:])
                out[root] = ProcessSample(pids: [], cpuNanoseconds: 0, at: now)
                continue
            }

            let subtree = ProcessTable.descendants(of: [root], childrenByParent: childrenByParent)
            var live: [String: UInt64] = [:]
            live.reserveCapacity(subtree.count)
            for proc in processes where subtree.contains(proc.pid) {
                live["\(proc.pid)-\(proc.startTime)"] = ProcessTable.cpuNanoseconds(pid: proc.pid)
            }
            let cpu = accumulator.fold(live: live)
            out[root] = ProcessSample(pids: subtree, cpuNanoseconds: cpu, at: now)
        }

        // Drop accumulators for holders that are no longer in scope.
        accumulators = accumulators.filter { roots.contains($0.key) }
        return out
    }
}
