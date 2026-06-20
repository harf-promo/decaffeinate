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

/// Reads the current power source via IOKit's IOPowerSources API (public, no
/// entitlements). Used by the battery-floor safety rail and the menu UI.
struct PowerSourceReader {

    func snapshot() -> PowerSnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, first)?
                .takeUnretainedValue() as? [String: Any]
        else {
            return .unknown
        }

        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let onBattery = powerState == kIOPSBatteryPowerValue

        var charge: Double?
        if let current = description[kIOPSCurrentCapacityKey] as? Double,
           let max = description[kIOPSMaxCapacityKey] as? Double, max > 0 {
            charge = current / max
        }

        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false

        return PowerSnapshot(onBattery: onBattery, charge: charge, isCharging: isCharging)
    }
}
