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

/// A mutable clock for tests that drive time-dependent behavior.
final class MutableClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
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

/// A canned boot-time reader for tests.
@MainActor
final class FakeSystemStateReader: SystemStateReading {
    var boot: Date?
    init(boot: Date? = nil) { self.boot = boot }
    func bootTime() -> Date? { boot }
}

/// A canned wake-reason reader for tests (no pmset subprocess).
struct FakeWakeReasonReader: WakeReasonReading {
    var reason: String?
    func latestWakeReason() -> String? { reason }
}

/// A canned audio-device resolver for tests (no CoreAudio).
@MainActor
final class FakeAudioDeviceResolver: AudioDeviceResolving {
    var byToken: [String: String] = [:]
    var devices: [String: AudioDeviceInfo] = [:]
    private(set) var lookups: [String] = []
    func friendlyName(forToken token: String) -> String? {
        lookups.append(token)
        return byToken[token]
    }
    func device(forToken token: String) -> AudioDeviceInfo? { devices[token] }
}
