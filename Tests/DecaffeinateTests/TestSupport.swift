import Foundation

@testable import Decaffeinate

enum Fixtures {
    static func assertion(
        pid: pid_t = 1234,
        process: String = "TestApp",
        bundle: String? = "com.example.TestApp",
        type: String = AssertionType.preventUserIdleSystemSleep,
        name: String = "Test assertion",
        created: Date? = nil,
        realOwner: AssertionOwner? = nil,
        humanReadableReason: String? = nil,
        details: String? = nil,
        resources: [String] = [],
        autoReleaseSeconds: Int? = nil,
        viaRunningboard: Bool = false
    ) -> PowerAssertion {
        PowerAssertion(
            id: "\(pid)-\(type)",
            pid: pid,
            processName: process,
            bundleIdentifier: bundle,
            assertionType: type,
            name: name,
            kind: AssertionType.classify(type),
            createdAt: created,
            realOwner: realOwner,
            humanReadableReason: humanReadableReason,
            details: details,
            resources: resources,
            autoReleaseSeconds: autoReleaseSeconds,
            viaRunningboard: viaRunningboard
        )
    }

    static let defaultSettings = DecaffeinateSettings()
}

/// An injectable process graph for testing the provenance walk without syscalls.
@MainActor
final class FakeProcessIntrospector: ProcessIntrospecting {
    struct Node {
        var ppid: pid_t
        var name: String
        var bundleID: String?
        var ttyDev: UInt32 = 0
        var startTime: TimeInterval = 0
        var isRegularApp: Bool = false
        var regularAppName: String?
        var regularAppBundleID: String?
        var cwd: String?
        var argv: [String] = []
    }

    var graph: [pid_t: Node] = [:]
    var ttyByDev: [UInt32: String] = [:]

    func add(
        _ pid: pid_t, ppid: pid_t, name: String, bundleID: String? = nil,
        regularApp: String? = nil, cwd: String? = nil, argv: [String] = [], ttyDev: UInt32 = 0
    ) {
        graph[pid] = Node(
            ppid: ppid, name: name, bundleID: bundleID, ttyDev: ttyDev,
            isRegularApp: regularApp != nil, regularAppName: regularApp,
            regularAppBundleID: bundleID, cwd: cwd, argv: argv)
    }

    func facts(for pid: pid_t) -> ProcessFacts? {
        guard let n = graph[pid] else { return nil }
        return ProcessFacts(
            pid: pid, ppid: n.ppid, name: n.name, bundleID: n.bundleID, ttyDev: n.ttyDev,
            startTime: n.startTime, isRegularApp: n.isRegularApp, regularAppName: n.regularAppName,
            regularAppBundleID: n.regularAppBundleID)
    }
    func ttyName(forDev dev: UInt32) -> String? { dev == 0 ? nil : ttyByDev[dev] }
    func cwd(for pid: pid_t) -> String? { graph[pid]?.cwd }
    func argv(for pid: pid_t) -> [String] { graph[pid]?.argv ?? [] }
}

/// A canned provenance resolver for AppState-level tests.
@MainActor
final class FakeProvenanceResolver: ProcessProvenanceResolving {
    var byPid: [pid_t: ProcessProvenance] = [:]
    private(set) var resolveCount: [pid_t: Int] = [:]
    func provenance(for pid: pid_t) -> ProcessProvenance? {
        resolveCount[pid, default: 0] += 1
        return byPid[pid]
    }
}
