import AppKit
import Darwin
import Foundation

/// The per-pid facts the provenance walk needs, behind a seam so the walk is
/// testable without syscalls.
struct ProcessFacts: Sendable {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let bundleID: String?
    let ttyDev: UInt32
    let startTime: TimeInterval
    let isRegularApp: Bool
    let regularAppName: String?
    let regularAppBundleID: String?
}

/// Reads raw per-pid facts. The live implementation uses public `libproc` /
/// `sysctl` (no root, no private SPI); tests inject a fake process graph.
@MainActor
protocol ProcessIntrospecting {
    /// Returns nil when the pid is gone or its basic info can't be read.
    func facts(for pid: pid_t) -> ProcessFacts?
    func ttyName(forDev dev: UInt32) -> String?
    func cwd(for pid: pid_t) -> String?
    func argv(for pid: pid_t) -> [String]
}

/// Resolves where a sleep-holder came from — the window / terminal / agent /
/// project behind a `caffeinate` (or any) hold. Walks the parent chain with
/// public APIs only; lazy + cached so it never runs in the 1 Hz tick path.
@MainActor
final class ProcessProvenanceResolver {
    private let introspector: any ProcessIntrospecting
    private let now: () -> Date
    private let maxDepth = 12
    private let ttl: TimeInterval = 5

    private struct CacheEntry {
        let value: ProcessProvenance
        let at: Date
        let startTime: TimeInterval
    }
    private var cache: [pid_t: CacheEntry] = [:]

    init(
        introspector: any ProcessIntrospecting = LiveProcessIntrospector(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.introspector = introspector
        self.now = now
    }

    /// Resolve (and cache) the provenance for a holder pid. Nil if the process is
    /// gone or nothing readable. Cache key is pid+startTime (defeats PID reuse).
    func provenance(for pid: pid_t) -> ProcessProvenance? {
        guard let holder = introspector.facts(for: pid) else {
            cache[pid] = nil
            return nil
        }
        if let entry = cache[pid], entry.startTime == holder.startTime,
            now().timeIntervalSince(entry.at) < ttl
        {
            return entry.value
        }
        let resolved = resolve(holder: holder)
        cache[pid] = CacheEntry(value: resolved, at: now(), startTime: holder.startTime)
        return resolved
    }

    private func resolve(holder: ProcessFacts) -> ProcessProvenance {
        let holderArgv = introspector.argv(for: holder.pid)
        let ttyName = introspector.ttyName(forDev: holder.ttyDev)
        let cwd = introspector.cwd(for: holder.pid)

        var originApp: AssertionOwner?
        var originKind: OriginKind = .unknown
        var parentChain: [ProcessLink] = []
        var originCommand: [String]?

        if holder.isRegularApp, let name = holder.regularAppName {
            // The holder is itself a regular GUI app — no walk needed.
            originApp = AssertionOwner(name: name, bundleIdentifier: holder.regularAppBundleID)
            originKind = .guiApp
        } else {
            var cur = holder.ppid
            var seen: Set<pid_t> = [holder.pid]
            var depth = 0
            walk: while cur > 1, depth < maxDepth {
                if seen.contains(cur) { break }  // cycle guard
                seen.insert(cur)
                guard let parent = introspector.facts(for: cur) else { break }
                parentChain.append(ProcessLink(pid: cur, name: parent.name))

                // A recognized terminal / editor / agent host stops the walk.
                if let (owner, kind) = OriginRegistry.classify(
                    name: parent.name, bundleID: parent.bundleID)
                {
                    if parent.isRegularApp, let regName = parent.regularAppName {
                        originApp = AssertionOwner(
                            name: regName, bundleIdentifier: parent.regularAppBundleID)
                    } else {
                        originApp = owner
                    }
                    originKind = kind
                    break walk
                }

                // A plain regular GUI app ancestor is the origin.
                if parent.isRegularApp, let regName = parent.regularAppName {
                    originApp = AssertionOwner(
                        name: regName, bundleIdentifier: parent.regularAppBundleID)
                    originKind = .guiApp
                    break walk
                }

                // Otherwise capture the nearest non-shell ancestor's command line.
                // This is how we identify an agent (e.g. Claude Code) whose process
                // name is a version string but whose argv[0] is `claude`.
                if originCommand == nil, !OriginRegistry.isShell(parent.name) {
                    let a = introspector.argv(for: cur)
                    if !a.isEmpty { originCommand = a }
                }

                cur = parent.ppid
                depth += 1
            }
            if originApp == nil, cur <= 1 {
                // Reparented to launchd — the spawning terminal already exited.
                originKind = .launchAgent
            }
            // No GUI ancestor, but the command line names a known agent.
            if originApp == nil,
                ProcessProvenance.friendlyAgentName(argv: originCommand ?? []) != nil
            {
                originKind = .agentHost
            }
        }

        let originName =
            originApp?.name
            ?? ProcessProvenance.friendlyAgentName(argv: originCommand ?? holderArgv)
        let label = ProcessProvenance.composeLabel(
            originName: originName, cwd: cwd, ttyName: ttyName)

        return ProcessProvenance(
            holderPid: holder.pid,
            holderName: holder.name,
            holderArgv: holderArgv,
            parentChain: parentChain,
            originApp: originApp,
            originKind: originKind,
            ttyName: ttyName,
            cwd: cwd,
            originCommand: originCommand,
            sessionLabel: label)
    }
}

/// Live `libproc` / `sysctl` reader. Every call degrades to nil/[] on any
/// non-success return — never traps, never force-unwraps.
@MainActor
final class LiveProcessIntrospector: ProcessIntrospecting {
    func facts(for pid: pid_t) -> ProcessFacts? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let start =
            TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        let reg = runningRegularApp(forPID: pid)
        return ProcessFacts(
            pid: pid,
            ppid: pid_t(info.pbi_ppid),
            name: processName(forPID: pid),
            bundleID: bundleIdentifier(forPID: pid),
            ttyDev: info.e_tdev,
            startTime: start,
            isRegularApp: reg != nil,
            regularAppName: reg?.name,
            regularAppBundleID: reg?.bundleID)
    }

    func ttyName(forDev dev: UInt32) -> String? {
        guard dev != 0, dev != UInt32.max else { return nil }
        guard let c = devname(dev_t(Int32(bitPattern: dev)), mode_t(S_IFCHR)) else { return nil }
        let name = String(cString: c)
        return name.isEmpty ? nil : name
    }

    func cwd(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            let bytes = raw.bindMemory(to: UInt8.self)
            let len = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<len], as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    func argv(for pid: pid_t) -> [String] {
        var argmax: Int32 = 0
        var sizeMax = MemoryLayout<Int32>.size
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &argmax, &sizeMax, nil, 0) == 0, argmax > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(argmax))
        var length = Int(argmax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0,
            length > MemoryLayout<Int32>.size
        else { return [] }

        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) {
            $0.copyBytes(from: buffer.prefix(4).withUnsafeBytes { $0 })
        }
        guard argc > 0 else { return [] }

        return buffer.withUnsafeBufferPointer { ptr -> [String] in
            guard let base = ptr.baseAddress else { return [] }
            let end = base + length
            var cur = base + MemoryLayout<Int32>.size

            // Skip exec_path, then its trailing NUL padding.
            while cur < end, cur.pointee != 0 { cur += 1 }
            while cur < end, cur.pointee == 0 { cur += 1 }

            var args: [String] = []
            var i: Int32 = 0
            while i < argc, cur < end {
                let start = cur
                while cur < end, cur.pointee != 0 { cur += 1 }
                let count = start.distance(to: cur)
                if count > 0 {
                    let token = start.withMemoryRebound(to: UInt8.self, capacity: count) {
                        String(
                            decoding: UnsafeBufferPointer(start: $0, count: count), as: UTF8.self)
                    }
                    // argv is attacker-controlled free text — sanitize before it
                    // can reach the UI / --scan. The env block is never read.
                    args.append(ReasonEngine.sanitize(token, maxLength: 256))
                }
                if cur < end { cur += 1 }  // step over the NUL
                i += 1
            }
            return args
        }
    }
}
