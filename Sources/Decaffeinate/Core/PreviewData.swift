import Foundation

/// Deterministic sample data for rendering README screenshots (via the hidden
/// `--render-previews` CLI mode) without touching real system state or user prefs.

@MainActor
final class PreviewSampler: PowerAssertionScanning {
    func scan() -> [PowerAssertion] {
        let now = Date()
        return [
            PowerAssertion(
                id: "p1", pid: 408, processName: "coreaudiod", bundleIdentifier: nil,
                assertionType: AssertionType.preventUserIdleSystemSleep,
                name: "com.apple.audio.AudioTap.context.preventuseridlesleep", kind: .systemSleep,
                createdAt: now.addingTimeInterval(-540),
                realOwner: AssertionOwner(name: "Zoom", bundleIdentifier: "us.zoom.xos"),
                resources: ["audio-in", "DEVICE-UUID"]),
            PowerAssertion(
                id: "p2", pid: 403, processName: "runningboardd", bundleIdentifier: nil,
                assertionType: AssertionType.preventUserIdleSystemSleep,
                name: "WebKit Media Playback", kind: .systemSleep,
                createdAt: now.addingTimeInterval(-845),
                realOwner: AssertionOwner(name: "Safari", bundleIdentifier: "com.apple.Safari")),
            PowerAssertion(
                id: "p3", pid: 940, processName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                assertionType: AssertionType.preventUserIdleSystemSleep,
                name: "com.apple.audio.BuiltInSpeakerDevice", kind: .systemSleep,
                createdAt: now.addingTimeInterval(-3120),
                resources: ["audio-out", "BuiltInSpeakerDevice"]),
            PowerAssertion(
                id: "p4", pid: 2810, processName: "caffeinate", bundleIdentifier: nil,
                assertionType: AssertionType.preventUserIdleSystemSleep,
                name: "caffeinate command-line tool", kind: .systemSleep,
                createdAt: now.addingTimeInterval(-7260),
                details: "caffeinate asserting for 300 secs", autoReleaseSeconds: 84),
        ]
    }
}

@MainActor
struct PreviewProvenance: ProcessProvenanceResolving {
    /// The sample `caffeinate` (pid 2810) resolves to an agent session so the
    /// detail view + the agentic offer render in screenshots.
    func provenance(for pid: pid_t) -> ProcessProvenance? {
        guard pid == 2810 else { return nil }
        let cwd = FileManager.default.homeDirectoryForCurrentUser.path + "/dev/myrepo"
        return ProcessProvenance(
            holderPid: 2810,
            holderName: "caffeinate",
            holderArgv: ["caffeinate", "-i", "-t", "300"],
            parentChain: [
                ProcessLink(pid: 2700, name: "claude"),
                ProcessLink(pid: 1500, name: "zsh"),
                ProcessLink(pid: 1490, name: "Ghostty"),
            ],
            originApp: nil,
            originKind: .agentHost,
            ttyName: "ttys004",
            cwd: cwd,
            originCommand: ["claude", "--model", "opusplan"],
            sessionLabel: "started by Claude Code · in ~/dev/myrepo")
    }
}

@MainActor
struct PreviewIdle: IdleReading {
    var seconds: TimeInterval = 8
    func secondsSinceLastInput() -> TimeInterval { seconds }
}

@MainActor
struct PreviewPower: PowerReading {
    func snapshot() -> PowerSnapshot {
        PowerSnapshot(onBattery: true, charge: 0.82, isCharging: false)
    }
}

extension AppState {
    /// An `AppState` wired to deterministic sample data, for screenshot rendering.
    /// Uses a throwaway `UserDefaults` suite so it never touches real prefs.
    static func preview() -> AppState {
        let defaults = UserDefaults(suiteName: "decaffeinate.preview")!
        defaults.removePersistentDomain(forName: "decaffeinate.preview")
        let settings = SettingsStore(defaults: defaults)
        // Keep the one-time explainer collapsed so the README menu shot is clean.
        settings.settings.hasSeenAwakeExplainer = true
        let rules = RulesEngine(defaults: defaults)
        let state = AppState(
            settingsStore: settings,
            rulesEngine: rules,
            telemetry: PreviewSampler(),
            idleMonitor: PreviewIdle(),
            powerReader: PreviewPower(),
            thermalProvider: { .nominal },
            provenanceResolver: PreviewProvenance()
        )
        state.tick()
        return state
    }
}
