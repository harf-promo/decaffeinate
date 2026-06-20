import Foundation

/// A process (tree) to watch for completion, so the Mac can sleep once a long
/// agent/build finishes. Either a named process (e.g. `node`, `claude`,
/// `xcodebuild`) or a specific PID.
enum WatchTarget: Codable, Hashable, Sendable {
    case processName(String)
    case pid(pid_t)

    var label: String {
        switch self {
        case .processName(let name): return name
        case .pid(let pid): return "PID \(pid)"
        }
    }
}

/// A point-in-time reading of a watched process subtree.
struct ProcessSample: Sendable, Equatable {
    /// Every PID in the watched subtree (root + descendants).
    let pids: Set<pid_t>
    /// Total cumulative CPU time (user + system) across the subtree, nanoseconds.
    let cpuNanoseconds: UInt64
    /// When this sample was taken.
    let at: Date

    var exists: Bool { !pids.isEmpty }

    static let empty = ProcessSample(pids: [], cpuNanoseconds: 0, at: .distantPast)
}
