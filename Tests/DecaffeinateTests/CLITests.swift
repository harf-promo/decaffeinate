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
        settings: DecaffeinateSettings = DecaffeinateSettings()
    ) -> CLI.SleepIfIdleVerdict {
        CLI.sleepIfIdleVerdict(
            idleSeconds: idle, threshold: threshold, assertions: assertions,
            power: PowerSnapshot(onBattery: false, charge: 1.0, isCharging: false),
            thermalState: .nominal, settings: settings)
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
