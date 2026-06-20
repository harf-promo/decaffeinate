import XCTest
@testable import Decaffeinate

final class SafetyRailsTests: XCTestCase {

    private func evaluate(
        assertions: [PowerAssertion] = [],
        power: PowerSnapshot = .unknown,
        thermal: ProcessInfo.ThermalState = .nominal,
        whitelisted: [String] = [],
        settings: DecaffeinateSettings = DecaffeinateSettings()
    ) -> SafetyDecision {
        SafetyRails.evaluate(
            assertions: assertions,
            power: power,
            thermalState: thermal,
            whitelistedAwakeAppNames: whitelisted,
            settings: settings
        )
    }

    func testCleanStateAllowsForcedSleep() {
        let decision = evaluate()
        XCTAssertTrue(decision.canForceSleep)
        XCTAssertFalse(decision.mustSleepNow)
        XCTAssertFalse(decision.shouldDropKeepAwake)
    }

    func testCriticalThermalForcesImmediateSleep() {
        let decision = evaluate(thermal: .critical)
        XCTAssertTrue(decision.mustSleepNow)
        XCTAssertTrue(decision.shouldDropKeepAwake)
    }

    func testSeriousThermalDropsKeepAwakeButNotImmediate() {
        let decision = evaluate(thermal: .serious)
        XCTAssertFalse(decision.mustSleepNow)
        XCTAssertTrue(decision.shouldDropKeepAwake)
    }

    func testThermalGuardCanBeDisabled() {
        var settings = DecaffeinateSettings()
        settings.thermalGuardEnabled = false
        let decision = evaluate(thermal: .critical, settings: settings)
        XCTAssertFalse(decision.mustSleepNow)
        XCTAssertFalse(decision.shouldDropKeepAwake)
    }

    func testBatteryBelowFloorDropsKeepAwake() {
        let power = PowerSnapshot(onBattery: true, charge: 0.15, isCharging: false)
        let decision = evaluate(power: power) // default floor 20%
        XCTAssertTrue(decision.shouldDropKeepAwake)
        XCTAssertFalse(decision.mustSleepNow)
    }

    func testBatteryCriticallyLowForcesImmediateSleep() {
        let power = PowerSnapshot(onBattery: true, charge: 0.02, isCharging: false)
        let decision = evaluate(power: power)
        XCTAssertTrue(decision.mustSleepNow)
    }

    func testBatteryFloorIgnoredOnAC() {
        let power = PowerSnapshot(onBattery: false, charge: 0.05, isCharging: true)
        let decision = evaluate(power: power)
        XCTAssertFalse(decision.shouldDropKeepAwake)
        XCTAssertFalse(decision.mustSleepNow)
    }

    func testActiveMediaHoldsForcedSleep() {
        let media = Fixtures.assertion(
            process: "QuickTime",
            type: AssertionType.preventUserIdleDisplaySleep,
            name: "Playing video"
        )
        let decision = evaluate(assertions: [media])
        XCTAssertFalse(decision.canForceSleep)
    }

    func testMediaPauseCanBeDisabled() {
        var settings = DecaffeinateSettings()
        settings.pauseForActiveMedia = false
        let media = Fixtures.assertion(type: AssertionType.preventUserIdleDisplaySleep)
        let decision = evaluate(assertions: [media], settings: settings)
        XCTAssertTrue(decision.canForceSleep)
    }

    func testTimeMachineDetectedFromBackupd() {
        let backup = Fixtures.assertion(process: "backupd", bundle: nil, name: "Backup")
        XCTAssertTrue(SafetyRails.isTimeMachineActive([backup]))
        let decision = evaluate(assertions: [backup])
        XCTAssertFalse(decision.canForceSleep)
    }

    func testSystemUpdateDetectedFromInstaller() {
        let update = Fixtures.assertion(process: "softwareupdated", bundle: nil, name: "Install macOS")
        XCTAssertTrue(SafetyRails.isSystemUpdateActive([update]))
        let decision = evaluate(assertions: [update])
        XCTAssertFalse(decision.canForceSleep)
    }

    func testWhitelistedAppHoldsForcedSleep() {
        let decision = evaluate(whitelisted: ["Final Cut Pro"])
        XCTAssertFalse(decision.canForceSleep)
        XCTAssertTrue(decision.holdForceSleepReasons.contains { $0.contains("Final Cut Pro") })
    }

    func testWhitelistRespectCanBeDisabled() {
        var settings = DecaffeinateSettings()
        settings.respectWhitelist = false
        let decision = evaluate(whitelisted: ["Final Cut Pro"], settings: settings)
        XCTAssertTrue(decision.canForceSleep)
    }
}
