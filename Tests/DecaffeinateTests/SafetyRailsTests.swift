import XCTest

@testable import Decaffeinate

final class SafetyRailsTests: XCTestCase {

    private func evaluate(
        assertions: [PowerAssertion] = [],
        power: PowerSnapshot = .unknown,
        thermal: ProcessInfo.ThermalState = .nominal,
        idleSeconds: TimeInterval = 0,
        whitelisted: [String] = [],
        settings: DecaffeinateSettings = DecaffeinateSettings()
    ) -> SafetyDecision {
        SafetyRails.evaluate(
            assertions: assertions,
            power: power,
            thermalState: thermal,
            idleSeconds: idleSeconds,
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
        let decision = evaluate(power: power)  // default floor 20%
        XCTAssertTrue(decision.shouldDropKeepAwake)
        XCTAssertFalse(decision.mustSleepNow)
    }

    func testBatteryCriticallyLowForcesImmediateSleep() {
        let power = PowerSnapshot(onBattery: true, charge: 0.02, isCharging: false)
        let decision = evaluate(power: power)
        XCTAssertTrue(decision.mustSleepNow)
    }

    func testBatteryCriticallyLowAlsoDropsKeepAwakeBelowAnyFloor() {
        // A user-set floor below the 3% critical line must NOT let us force sleep
        // while still asserting a keep-awake hold — critical drops the hold too.
        var settings = DecaffeinateSettings()
        settings.batteryFloorPercent = 0
        let power = PowerSnapshot(onBattery: true, charge: 0.03, isCharging: false)
        let decision = evaluate(power: power, settings: settings)
        XCTAssertTrue(decision.mustSleepNow)
        XCTAssertTrue(decision.shouldDropKeepAwake)
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

    func testMicrophoneInUseHoldsForcedSleep() {
        let mic = Fixtures.assertion(process: "coreaudiod", resources: ["audio-in", "DEVICE-UUID"])
        let decision = evaluate(assertions: [mic])
        XCTAssertFalse(decision.canForceSleep)
        XCTAssertTrue(decision.holdForceSleepReasons.contains { $0.contains("Microphone") })
    }

    func testAudioOutputCountsAsMedia() {
        let audio = Fixtures.assertion(process: "coreaudiod", resources: ["audio-out", "Speaker"])
        XCTAssertTrue(SafetyRails.isMediaActive([audio]))
        XCTAssertFalse(evaluate(assertions: [audio]).canForceSleep)
    }

    func testTimeMachineDetectedFromBackupd() {
        let backup = Fixtures.assertion(process: "backupd", bundle: nil, name: "Backup")
        XCTAssertTrue(SafetyRails.isTimeMachineActive([backup]))
        let decision = evaluate(assertions: [backup])
        XCTAssertFalse(decision.canForceSleep)
    }

    func testSystemUpdateDetectedFromInstaller() {
        let update = Fixtures.assertion(
            process: "softwareupdated", bundle: nil, name: "Install macOS")
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

    // MARK: Idle-cap on media, uncapped mic, anti-spoofing

    func testStaleMediaHoldIsReleasedAfterLongIdle() {
        let audio = Fixtures.assertion(process: "coreaudiod", resources: ["audio-out", "Speaker"])
        // Within the grace: still held.
        XCTAssertFalse(evaluate(assertions: [audio], idleSeconds: 60).canForceSleep)
        // Idle well past the threshold + 30-min grace: a stale token must not
        // keep the Mac awake forever.
        let pastGrace = 10 * 60 + SafetyRails.staleMediaGraceSeconds + 1
        XCTAssertTrue(evaluate(assertions: [audio], idleSeconds: pastGrace).canForceSleep)
    }

    func testMicrophoneHoldIsNeverIdleCapped() {
        let mic = Fixtures.assertion(process: "coreaudiod", resources: ["audio-in", "DEVICE"])
        let veryIdle = 10 * 60 + SafetyRails.staleMediaGraceSeconds + 10_000
        let decision = evaluate(assertions: [mic], idleSeconds: veryIdle)
        XCTAssertFalse(decision.canForceSleep, "a call must hold even after long passive idle")
    }

    func testCallGuardIsIndependentOfMediaToggle() {
        var settings = DecaffeinateSettings()
        settings.pauseForActiveMedia = false  // sleep aggressively through media…
        let mic = Fixtures.assertion(process: "coreaudiod", resources: ["audio-in"])
        // …but the call guard still holds.
        XCTAssertFalse(evaluate(assertions: [mic], settings: settings).canForceSleep)

        settings.pauseForActiveCall = false
        XCTAssertTrue(evaluate(assertions: [mic], settings: settings).canForceSleep)
    }

    func testSpoofedTimeMachineNameDoesNotHoldSleep() {
        // A rogue app cannot dodge force-sleep by *naming* its assertion "Backup".
        let spoof = Fixtures.assertion(process: "EvilApp", name: "Backup in progress")
        XCTAssertFalse(SafetyRails.isTimeMachineActive([spoof]))
        XCTAssertTrue(evaluate(assertions: [spoof]).canForceSleep)
    }

    func testSpoofedUpdateNameDoesNotHoldSleep() {
        let spoof = Fixtures.assertion(process: "EvilApp", name: "Install macOS Sequoia")
        XCTAssertFalse(SafetyRails.isSystemUpdateActive([spoof]))
        XCTAssertTrue(evaluate(assertions: [spoof]).canForceSleep)
    }
}
