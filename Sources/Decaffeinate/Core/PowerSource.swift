import Foundation
import IOKit.ps

/// A point-in-time reading of the Mac's power source.
struct PowerSnapshot: Sendable, Equatable {
    /// `true` when running on the internal battery (not AC / wall power).
    let onBattery: Bool
    /// Battery charge as a fraction in `0...1`, or `nil` on desktops.
    let charge: Double?
    /// `true` while the battery is actively charging.
    let isCharging: Bool

    var chargePercent: Int? {
        charge.map { Int(($0 * 100).rounded()) }
    }

    /// Desktops (no battery) report as "plugged in, full".
    static let unknown = PowerSnapshot(onBattery: false, charge: nil, isCharging: false)
}

/// Pure interpretation of IOKit power-source dictionaries, kept separate from the
/// IOKit calls so it can be unit-tested with hand-built fixtures.
///
/// A Mac can list several sources (internal battery, a USB UPS, ...) in no guaranteed
/// order, so neither "first source" nor "any source" is a safe way to read the
/// battery: the battery rails (critical-battery force-sleep, battery floor) must use
/// the *internal battery* source, and "on battery" must come from what is currently
/// *providing* power.
enum PowerSourceParser {

    /// - Parameters:
    ///   - providingType: `IOPSGetProvidingPowerSourceType` ("AC Power",
    ///     "Battery Power", "UPS Power"), or `nil` if unavailable.
    ///   - descriptions: one `IOPSGetPowerSourceDescription` dictionary per source.
    static func snapshot(providingType: String?, descriptions: [[String: Any]]) -> PowerSnapshot {
        let internalBattery = descriptions.first {
            ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        }

        let onBattery: Bool
        if let providingType {
            onBattery = providingType == kIOPSBatteryPowerValue
        } else if let internalBattery {
            // No providing-type answer: fall back to the internal battery's own state.
            onBattery =
                (internalBattery[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        } else {
            onBattery = false
        }

        guard let internalBattery else {
            return PowerSnapshot(onBattery: onBattery, charge: nil, isCharging: false)
        }

        var charge: Double?
        if let current = number(internalBattery[kIOPSCurrentCapacityKey]),
            let max = number(internalBattery[kIOPSMaxCapacityKey]), max > 0
        {
            charge = current / max
        }
        let isCharging = (internalBattery[kIOPSIsChargingKey] as? Bool) ?? false
        return PowerSnapshot(onBattery: onBattery, charge: charge, isCharging: isCharging)
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }
}

/// Reads the current power source via IOKit's IOPowerSources API (public, no
/// entitlements). Used by the battery-floor safety rail and the menu UI.
struct PowerSourceReader {

    func snapshot() -> PowerSnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unknown
        }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
        let sources = (IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        let descriptions: [[String: Any]] = sources.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSourceParser.snapshot(providingType: providing, descriptions: descriptions)
    }
}
