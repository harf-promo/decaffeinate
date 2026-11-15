import XCTest

@testable import Decaffeinate

/// `--keep-awake`'s safety guard: the CLI hold must honor the same Backpack
/// Guard / Battery Floor rails as the GUI toggle.
final class CLITests: XCTestCase {

    private let settings = DecaffeinateSettings()  // thermal guard on, floor 20%

    func testKeepAwakeDropsBelowBatteryFloor() {
        let reason = CLI.keepAwakeSafetyDropReason(
            power: PowerSnapshot(onBattery: true, charge: 0.10, isCharging: false),
            thermalState: .nominal,
            settings: settings)
        XCTAssertNotNil(reason, "battery below the floor must drop the CLI hold")
    }

    func testKeepAwakeDropsUnderThermalPressure() {
        let reason = CLI.keepAwakeSafetyDropReason(
            power: .unknown,
            thermalState: .critical,
            settings: settings)
        XCTAssertNotNil(reason, "the backpack guard must drop the CLI hold")
    }

    func testKeepAwakeHoldsInNormalConditions() {
        let reason = CLI.keepAwakeSafetyDropReason(
            power: PowerSnapshot(onBattery: true, charge: 0.80, isCharging: false),
            thermalState: .nominal,
            settings: settings)
        XCTAssertNil(reason, "a healthy Mac keeps the hold for the full duration")
    }

    func testKeepAwakeRespectsDisabledThermalGuard() {
        var relaxed = DecaffeinateSettings()
        relaxed.thermalGuardEnabled = false
        let reason = CLI.keepAwakeSafetyDropReason(
            power: .unknown,
            thermalState: .serious,
            settings: relaxed)
        XCTAssertNil(reason, "the user's configured rails apply to the CLI too")
    }

    // MARK: --sleep-if-idle gating (v1.19)

    func testShouldSleepIsInclusiveAtTheBoundary() {
        XCTAssertTrue(CLI.shouldSleep(idleSeconds: 300, threshold: 300))
        XCTAssertTrue(CLI.shouldSleep(idleSeconds: 301, threshold: 300))
        XCTAssertFalse(CLI.shouldSleep(idleSeconds: 299, threshold: 300))
    }

    // MARK: --sleep-if-idle / MCP sleep_if_idle safety rails (T4 / F4)

    private func verdict(
        idle: TimeInterval = 900, threshold: Int = 300,
        assertions: [PowerAssertion] = [],
        power: PowerSnapshot = PowerSnapshot(onBattery: false, charge: 1.0, isCharging: false),
        settings: DecaffeinateSettings = DecaffeinateSettings()
    ) -> CLI.SleepIfIdleVerdict {
        CLI.sleepIfIdleVerdict(
            idleSeconds: idle, threshold: threshold, assertions: assertions,
            power: power, thermalState: .nominal, settings: settings)
    }

    func testSleepIfIdleSleepsWhenIdleAndNothingObjects() {
        XCTAssertEqual(verdict(), .sleep)
    }

    func testSleepIfIdleStaysAwakeWhenActive() {
        XCTAssertEqual(verdict(idle: 10), .stillActive)
    }

    func testSleepIfIdleLeavesAwakeDuringACall() {
        let mic = Fixtures.assertion(
            pid: 900, process: "coreaudiod", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, resources: ["audio-in"])
        guard case .leaveAwake(let reason) = verdict(assertions: [mic]) else {
            return XCTFail("a hands-off call must not be slept through")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("microphone"), reason)
    }

    func testSleepIfIdleHonoursTheUserTurningTheCallGuardOff() {
        let mic = Fixtures.assertion(
            pid: 900, process: "coreaudiod", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, resources: ["audio-in"])
        var relaxed = DecaffeinateSettings()
        relaxed.pauseForActiveCall = false
        relaxed.pauseForActiveMedia = false
        XCTAssertEqual(verdict(assertions: [mic], settings: relaxed), .sleep)
    }

    func testSleepIfIdleLeavesAwakeDuringTimeMachine() {
        let backup = Fixtures.assertion(
            pid: 55, process: "backupd", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, name: "com.apple.backupd")
        guard case .leaveAwake(let reason) = verdict(assertions: [backup]) else {
            return XCTFail("a Time Machine backup must hold the hook's sleep off")
        }
        XCTAssertTrue(reason.contains("Time Machine"), reason)
    }

    func testSleepIfIdleIdleGateWinsOverRails() {
        let mic = Fixtures.assertion(
            pid: 900, process: "coreaudiod", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, resources: ["audio-in"])
        XCTAssertEqual(verdict(idle: 10, assertions: [mic]), .stillActive)
    }

    // MARK: --sleep-if-idle must respect a live keep-awake hold (M1)

    func testSleepIfIdleLeavesAwakeWhileAKeepAwakeHoldIsLive() {
        // `--keep-awake` / the menu toggle / MCP `keep_awake` hold an assertion from a
        // process named Decaffeinate; `pmset sleepnow` would override it.
        let hold = Fixtures.assertion(
            pid: 700, process: "Decaffeinate", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, name: "Decaffeinate --keep-awake")
        guard case .leaveAwake(let reason) = verdict(assertions: [hold]) else {
            return XCTFail("a hands-off hook must not sleep through the user's keep-awake hold")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("keep"), reason)
    }

    func testSleepIfIdleLeavesAwakeWhileCaffeinateHoldsTheMac() {
        let hold = Fixtures.assertion(
            pid: 701, process: "caffeinate", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep)
        guard case .leaveAwake = verdict(assertions: [hold]) else {
            return XCTFail("a live caffeinate hold must keep the Mac awake")
        }
    }

    func testSleepIfIdleLeavesAwakeWhenTheKeepAwakeSettingIsOn() {
        var keepAwake = DecaffeinateSettings()
        keepAwake.caffeinateEnabled = true
        guard case .leaveAwake = verdict(settings: keepAwake) else {
            return XCTFail("Keep Awake is on in Settings; the hook must not sleep the Mac")
        }
    }

    func testSleepIfIdleStillSleepsWhenASafetyRailDropsTheKeepAwakeHold() {
        // The same rule the GUI engine applies: a battery-floor drop releases the hold,
        // so it can no longer hold sleep off.
        var keepAwake = DecaffeinateSettings()
        keepAwake.caffeinateEnabled = true
        let low = PowerSnapshot(onBattery: true, charge: 0.05, isCharging: false)
        let hold = Fixtures.assertion(
            pid: 700, process: "Decaffeinate", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep)
        XCTAssertEqual(verdict(assertions: [hold], power: low, settings: keepAwake), .sleep)
    }

    func testSleepIfIdleIgnoresTheAppsStrictTakeoverHold() {
        // Strict takeover holds the app's assertion all the time; that is not the user
        // asking for the Mac to stay awake, or the hook could never sleep it.
        let appHold = Fixtures.assertion(
            pid: 700, process: "Decaffeinate", bundle: nil,
            type: AssertionType.preventUserIdleSystemSleep, name: CLI.appHoldReason)
        var strict = DecaffeinateSettings()
        strict.strictTakeoverMode = true
        XCTAssertEqual(verdict(assertions: [appHold], settings: strict), .sleep)
        guard case .leaveAwake = verdict(assertions: [appHold]) else {
            return XCTFail("without strict takeover the app hold is a keep-awake request")
        }
    }

    func testSleepIfIdleLeavesAwakeWhileAnotherAgentSessionIsActive() {
        let verdict = CLI.sleepIfIdleVerdict(
            idleSeconds: 900, threshold: 300, assertions: [],
            power: PowerSnapshot(onBattery: false, charge: 1.0, isCharging: false),
            thermalState: .nominal, settings: DecaffeinateSettings(),
            otherAgentSessions: ["Claude Code (~/api)"])
        guard case .leaveAwake(let reason) = verdict else {
            return XCTFail("another session is mid-task; this session's Stop hook must not sleep")
        }
        XCTAssertTrue(reason.contains("Claude Code (~/api)"), reason)
    }

    func testOtherAgentSessionsExcludeTheCallersOwnSession() {
        let claudeA = ProcessLink(pid: 50, name: "2.1.0")
        let claudeB = ProcessLink(pid: 60, name: "2.1.0")
        func provenance(_ holder: pid_t, via parent: ProcessLink) -> ProcessProvenance {
            ProcessProvenance(
                holderPid: holder, holderName: "caffeinate", holderArgv: ["caffeinate", "-i"],
                parentChain: [parent], originApp: nil, originKind: .agentHost, ttyName: nil,
                cwd: nil, originCommand: ["claude"], sessionLabel: nil)
        }
        let mine = Fixtures.assertion(pid: 100, process: "caffeinate", bundle: nil)
        let theirs = Fixtures.assertion(pid: 200, process: "caffeinate", bundle: nil)
        let names = CLI.otherAgentSessionNames(
            assertions: [mine, theirs], ownSessionRoot: 50,
            provenance: {
                $0 == 100 ? provenance(100, via: claudeA) : provenance(200, via: claudeB)
            })
        XCTAssertEqual(names.count, 1, "only session B counts as another session: \(names)")
    }

    func testSleepIfIdleIgnoresTheCallersOwnWrapperButNotAnotherSessions() {
        let own = Fixtures.assertion(pid: 100, process: "caffeinate", bundle: nil)
        let other = Fixtures.assertion(pid: 200, process: "caffeinate", bundle: nil)
        func run(_ assertions: [PowerAssertion]) -> CLI.SleepIfIdleVerdict {
            CLI.sleepIfIdleVerdict(
                idleSeconds: 900, threshold: 300, assertions: assertions,
                power: PowerSnapshot(onBattery: false, charge: 1.0, isCharging: false),
                thermalState: .nominal, settings: DecaffeinateSettings(),
                ownSessionHolders: [100])
        }
        XCTAssertEqual(run([own]), .sleep, "this session's own caffeinate must not block its hook")
        guard case .leaveAwake = run([own, other]) else {
            return XCTFail("another session's caffeinate still holds the Mac awake")
        }
    }

    func testOwnSessionWrapperIsOnlyADirectChildOfTheSessionRoot() {
        func provenance(_ pid: pid_t, chain: [pid_t]) -> ProcessProvenance {
            ProcessProvenance(
                holderPid: pid, holderName: "caffeinate", holderArgv: ["caffeinate"],
                parentChain: chain.map { ProcessLink(pid: $0, name: "x") }, originApp: nil,
                originKind: .agentHost, ttyName: nil, cwd: nil, originCommand: nil,
                sessionLabel: nil)
        }
        let wrapper = Fixtures.assertion(pid: 100, process: "caffeinate", bundle: nil)
        let deliberate = Fixtures.assertion(pid: 101, process: "caffeinate", bundle: nil)
        let foreign = Fixtures.assertion(pid: 102, process: "caffeinate", bundle: nil)
        let notCaffeinate = Fixtures.assertion(pid: 103, process: "Decaffeinate", bundle: nil)
        let chains: [pid_t: [pid_t]] = [
            100: [50, 5], 101: [70, 50, 5], 102: [60, 5], 103: [50, 5],
        ]
        let all = [wrapper, deliberate, foreign, notCaffeinate]
        XCTAssertEqual(
            CLI.ownSessionWrapperPIDs(
                assertions: all, ownSessionRoot: 50,
                provenance: { provenance($0, chain: chains[$0] ?? []) }),
            [100], "only the session's direct caffeinate child is its own wrapper")
        XCTAssertTrue(
            CLI.ownSessionWrapperPIDs(
                assertions: all, ownSessionRoot: nil,
                provenance: { provenance($0, chain: chains[$0] ?? []) }
            ).isEmpty, "no session root (a hand-run from a terminal) excludes nothing")
    }

    func testOtherAgentSessionsCountAnAgentHoldingItsOwnAssertion() {
        // `pmset -g assertions` shows grok holding "agent turn in progress" itself.
        let own = ProcessProvenance(
            holderPid: 400, holderName: "grok-1.0.77-macos-aarch64",
            holderArgv: ["grok-1.0.77-macos-aarch64"],
            parentChain: [ProcessLink(pid: 77, name: "zsh")], originApp: nil,
            originKind: .terminal, ttyName: nil, cwd: nil, originCommand: nil, sessionLabel: nil)
        let hold = Fixtures.assertion(
            pid: 400, process: "grok-1.0.77-macos-aarch64", bundle: nil,
            type: AssertionType.noIdleSleep, name: "grok: agent turn in progress")
        XCTAssertEqual(
            CLI.otherAgentSessionNames(
                assertions: [hold], ownSessionRoot: 50, provenance: { _ in own }
            ).count, 1)
        XCTAssertTrue(CLI.isAgentExecutable("claude"))
        XCTAssertFalse(CLI.isAgentExecutable("zsh"))
        XCTAssertFalse(CLI.isAgentExecutable("node"), "node is a tool, not an AI agent")
    }

    func testOtherAgentSessionsIgnoreNonAgentHolders() {
        let plain = ProcessProvenance(
            holderPid: 300, holderName: "caffeinate", holderArgv: ["caffeinate"],
            parentChain: [ProcessLink(pid: 77, name: "zsh")], originApp: nil,
            originKind: .terminal, ttyName: nil, cwd: nil, originCommand: nil, sessionLabel: nil)
        let hold = Fixtures.assertion(pid: 300, process: "caffeinate", bundle: nil)
        XCTAssertTrue(
            CLI.otherAgentSessionNames(
                assertions: [hold], ownSessionRoot: 50, provenance: { _ in plain }
            ).isEmpty)
    }

    func testIdleThresholdParsesNumberAfterFlag() {
        let args = ["Decaffeinate", "--sleep-if-idle", "600"]
        XCTAssertEqual(CLI.idleThreshold(after: 1, in: args, default: 300), 600)
    }

    func testIdleThresholdFallsBackWhenFlagAlone() {
        let args = ["Decaffeinate", "--sleep-if-idle"]
        XCTAssertEqual(CLI.idleThreshold(after: 1, in: args, default: 300), 300)
    }

    func testIdleThresholdIgnoresTrailingCodexJSON() {
        // Codex invokes: notify = [bin, "--sleep-if-idle", "300"] and appends the
        // JSON payload as the LAST argv — the number is still parsed, JSON ignored.
        let args = ["Decaffeinate", "--sleep-if-idle", "300", "{\"type\":\"agent-turn-complete\"}"]
        XCTAssertEqual(CLI.idleThreshold(after: 1, in: args, default: 300), 300)
        // If Codex is configured without a number, the JSON is at i+1 → non-numeric
        // → fall back to the default rather than crash.
        let noNum = ["Decaffeinate", "--sleep-if-idle", "{\"type\":\"agent-turn-complete\"}"]
        XCTAssertEqual(CLI.idleThreshold(after: 1, in: noNum, default: 300), 300)
    }

    // MARK: --install-hook target parsing

    func testHookTargetDefaultsToAll() {
        XCTAssertEqual(
            CLI.hookTarget(after: 0, in: ["--install-hook"]), HookInstaller.Client.allCases)
        XCTAssertEqual(
            CLI.hookTarget(after: 0, in: ["--install-hook", "all"]), HookInstaller.Client.allCases)
    }

    func testHookTargetSelectsSingleClient() {
        XCTAssertEqual(CLI.hookTarget(after: 0, in: ["--install-hook", "claude"]), [.claude])
        XCTAssertEqual(CLI.hookTarget(after: 0, in: ["--install-hook", "codex"]), [.codex])
        XCTAssertEqual(CLI.hookTarget(after: 0, in: ["--install-hook", "cursor"]), [.cursor])
    }

    // MARK: --clamshell-status line (v1.24)

    func testClamshellStatusLineNotApplicable() {
        XCTAssertTrue(CLI.clamshellStatusLine(.notApplicable).contains("doesn\u{2019}t have a lid"))
    }

    func testClamshellStatusLineReady() {
        XCTAssertTrue(CLI.clamshellStatusLine(.ready).contains("Ready for clamshell mode"))
    }

    func testClamshellStatusLineListsWhatsMissing() {
        let line = CLI.clamshellStatusLine(.missing(unmet: [.power, .externalDisplay]))
        XCTAssertTrue(line.contains("Connect to power"))
        XCTAssertTrue(line.contains("Plug in an external display"))
    }
}
