import Darwin
import Foundation

/// Public-`libproc` process-tree primitives (`proc_listallpids`, `proc_pidinfo`),
/// factored out of `ProcessWatcher` so the single-target agent watcher and the
/// multi-holder stale-evidence sampler share one battle-tested implementation —
/// in particular the macOS-26 `proc_listallpids` count/truncation handling, which
/// must never be duplicated (a second copy would drift on the next fix).
///
/// No private APIs, no root.
enum ProcessTable {

    /// One process's identity in the tree. Keyed by pid **and** start time so a
    /// reused pid reads as a new process.
    struct ProcInfo: Equatable {
        let pid: pid_t
        let ppid: pid_t
        let name: String
        /// Kernel start time (seconds) — pairs with pid to defeat pid reuse.
        let startTime: UInt64
    }

    /// Every live process, optionally resolving each process's name. Name
    /// resolution (an `NSRunningApplication`-backed lookup) is the single most
    /// expensive part, so callers that match by pid pass `resolveNames: false`.
    static func snapshot(resolveNames: Bool) -> [ProcInfo] {
        // proc_listallpids fills the buffer and returns the number of PIDs
        // written (verified empirically on macOS 26: the return equals `ps -A`'s
        // count). If the buffer comes back completely full it may be truncated,
        // so grow and retry — that's the real guard against a busy machine
        // silently dropping a watched subtree (the trailing `pid > 0` check also
        // keeps us correct if a future SDK ever returns a byte count instead).
        let stride = MemoryLayout<pid_t>.stride
        var capacity = 4096
        var pids = [pid_t]()
        var pidCount = 0
        while true {
            pids = [pid_t](repeating: 0, count: capacity)
            let returned = proc_listallpids(&pids, Int32(capacity * stride))
            guard returned > 0 else { return [] }
            pidCount = min(Int(returned), capacity)
            if pidCount < capacity || capacity >= 262_144 { break }
            capacity *= 2
        }

        var result: [ProcInfo] = []
        result.reserveCapacity(pidCount)
        for index in 0..<pidCount {
            let pid = pids[index]
            guard pid > 0 else { continue }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
            guard read == size else { continue }
            result.append(
                ProcInfo(
                    pid: pid, ppid: pid_t(info.pbi_ppid),
                    name: resolveNames ? processName(forPID: pid) : "",
                    startTime: info.pbi_start_tvsec))
        }
        return result
    }

    /// Cumulative CPU time (user + system) for a single pid, nanoseconds; 0 when
    /// the process is gone or the read fails.
    static func cpuNanoseconds(pid: pid_t) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard read == size else { return 0 }
        return info.pti_total_user &+ info.pti_total_system
    }

    /// The parent→children index for one process snapshot. Build it once when
    /// evaluating several roots against the same snapshot.
    static func childrenByParent(_ processes: [ProcInfo]) -> [pid_t: [ProcInfo]] {
        Dictionary(grouping: processes, by: \.ppid)
    }

    /// Every pid in the subtree rooted at `roots` (roots included), via BFS over a
    /// precomputed parent→children index.
    static func descendants(of roots: Set<pid_t>, childrenByParent: [pid_t: [ProcInfo]]) -> Set<
        pid_t
    > {
        var result = roots
        var queue = Array(roots)
        while let parent = queue.popLast() {
            for child in childrenByParent[parent] ?? [] where !result.contains(child.pid) {
                result.insert(child.pid)
                queue.append(child.pid)
            }
        }
        return result
    }

    /// Convenience overload for a single evaluation against one snapshot.
    static func descendants(of roots: Set<pid_t>, in processes: [ProcInfo]) -> Set<pid_t> {
        descendants(of: roots, childrenByParent: childrenByParent(processes))
    }
}
