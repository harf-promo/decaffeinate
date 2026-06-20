import Darwin
import Foundation

/// Samples a process subtree's PIDs and cumulative CPU using public `libproc`
/// APIs (`proc_listallpids`, `proc_pidinfo`). No private APIs, no root.
struct ProcessWatcher {

    func sample(_ target: WatchTarget, now: Date) -> ProcessSample {
        let processes = allProcesses()

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

        guard !roots.isEmpty else { return ProcessSample(pids: [], cpuNanoseconds: 0, at: now) }

        let subtree = descendants(of: Set(roots), in: processes)
        let cpu = subtree.reduce(UInt64(0)) { $0 + cpuNanoseconds(pid: $1) }
        return ProcessSample(pids: subtree, cpuNanoseconds: cpu, at: now)
    }

    // MARK: libproc helpers

    private struct ProcInfo {
        let pid: pid_t
        let ppid: pid_t
        let name: String
    }

    private func allProcesses() -> [ProcInfo] {
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
                ProcInfo(pid: pid, ppid: pid_t(info.pbi_ppid), name: processName(forPID: pid)))
        }
        return result
    }

    private func cpuNanoseconds(pid: pid_t) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard read == size else { return 0 }
        return info.pti_total_user &+ info.pti_total_system
    }

    private func descendants(of roots: Set<pid_t>, in processes: [ProcInfo]) -> Set<pid_t> {
        let childrenByParent = Dictionary(grouping: processes, by: \.ppid)
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
}
