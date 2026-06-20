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
        let capacity = 8192
        var pids = [pid_t](repeating: 0, count: capacity)
        let returned = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard returned > 0 else { return [] }

        var result: [ProcInfo] = []
        // `returned` may be a pid count or a byte count depending on SDK; the
        // `pid > 0` guard makes either interpretation safe.
        for index in 0..<min(Int(returned), capacity) {
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
