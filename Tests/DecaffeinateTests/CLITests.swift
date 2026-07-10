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
    }
}
