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
}
