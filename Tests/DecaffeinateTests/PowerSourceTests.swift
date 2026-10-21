import IOKit.ps
import XCTest

@testable import Decaffeinate

final class PowerSourceTests: XCTestCase {

    private func battery(
        current: Any = 50, max: Any = 100, charging: Bool = false,
        state: String = kIOPSBatteryPowerValue
    ) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSPowerSourceStateKey: state,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSIsChargingKey: charging,
        ]
    }

    private func ups(percent: Int) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSUPSType,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSCurrentCapacityKey: percent,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
        ]
    }

    func testInternalBatteryOnBatteryPower() {
        let snap = PowerSourceParser.snapshot(
            providingType: kIOPSBatteryPowerValue, descriptions: [battery(current: 42)])
        XCTAssertTrue(snap.onBattery)
        XCTAssertEqual(snap.charge ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertFalse(snap.isCharging)
    }

    func testUPSListedFirstDoesNotHideInternalBattery() {
        let snap = PowerSourceParser.snapshot(
            providingType: kIOPSBatteryPowerValue,
            descriptions: [ups(percent: 100), battery(current: 3)])
        XCTAssertTrue(snap.onBattery)
        XCTAssertEqual(snap.chargePercent, 3)
        XCTAssertFalse(snap.isCharging, "the UPS's charging flag must not leak in")
    }

    func testBatteryListedFirstStillUsed() {
        let snap = PowerSourceParser.snapshot(
            providingType: kIOPSACPowerValue,
            descriptions: [
                battery(current: 80, charging: true, state: kIOPSACPowerValue), ups(percent: 10),
            ])
        XCTAssertFalse(snap.onBattery)
        XCTAssertEqual(snap.chargePercent, 80)
        XCTAssertTrue(snap.isCharging)
    }

    func testUPSProvidingPowerIsNotOnBattery() {
        let snap = PowerSourceParser.snapshot(
            providingType: "UPS Power",
            descriptions: [ups(percent: 60), battery(current: 90, state: kIOPSACPowerValue)])
        XCTAssertFalse(snap.onBattery)
        XCTAssertEqual(snap.chargePercent, 90)
    }

    func testDesktopWithOnlyUPSHasNoCharge() {
        let snap = PowerSourceParser.snapshot(
            providingType: kIOPSACPowerValue, descriptions: [ups(percent: 70)])
        XCTAssertFalse(snap.onBattery)
        XCTAssertNil(snap.charge)
        XCTAssertFalse(snap.isCharging)
    }

    func testNoSourcesIsUnknown() {
        XCTAssertEqual(PowerSourceParser.snapshot(providingType: nil, descriptions: []), .unknown)
    }

    func testMissingProvidingTypeFallsBackToBatteryState() {
        let snap = PowerSourceParser.snapshot(
            providingType: nil, descriptions: [battery(current: 20)])
        XCTAssertTrue(snap.onBattery)
        XCTAssertEqual(snap.chargePercent, 20)
    }

    func testDoubleCapacitiesAndZeroMax() {
        let snap = PowerSourceParser.snapshot(
            providingType: kIOPSBatteryPowerValue, descriptions: [battery(current: 25.0, max: 50.0)]
        )
        XCTAssertEqual(snap.chargePercent, 50)
        let bad = PowerSourceParser.snapshot(
            providingType: kIOPSBatteryPowerValue, descriptions: [battery(current: 5, max: 0)])
        XCTAssertNil(bad.charge)
        XCTAssertTrue(bad.onBattery)
    }
}
