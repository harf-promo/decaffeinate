import CoreGraphics
import Foundation
import IOKit.hid

/// External-display topology — one of the ingredients (alongside lid state
/// and power) Apple's own clamshell mode requires. Public CoreGraphics
/// (`CGGetOnlineDisplayList` / `CGDisplayIsBuiltin` — already implicitly
/// linked, this is an AppKit/SwiftUI app); no root, no private API.
struct DisplayTopology: Sendable, Equatable {
    /// How many displays besides the built-in panel are currently online.
    let externalDisplayCount: Int
    /// Whether the built-in panel is itself among the online displays —
    /// false while the lid is closed and macOS has blanked it, or on a
    /// desktop Mac with no built-in panel at all.
    let builtinDisplayActive: Bool

    var hasExternalDisplay: Bool { externalDisplayCount > 0 }

    static let none = DisplayTopology(externalDisplayCount: 0, builtinDisplayActive: false)
}

@MainActor
protocol DisplayTopologyReading {
    func snapshot() -> DisplayTopology
}

struct DisplayTopologyReader: DisplayTopologyReading {
    func snapshot() -> DisplayTopology {
        var count: UInt32 = 0
        // The standard CGGetOnlineDisplayList two-call idiom: size first, fetch second.
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return .none
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return .none
        }
        let builtinActive = ids.contains { CGDisplayIsBuiltin($0) != 0 }
        let externalCount = ids.filter { CGDisplayIsBuiltin($0) == 0 }.count
        return DisplayTopology(
            externalDisplayCount: externalCount, builtinDisplayActive: builtinActive)
    }
}

/// Best-effort signal for whether an external keyboard/pointer is connected.
///
/// Deliberately three-valued: HID transport enumeration is not a fully
/// reliable signal for every keyboard/mouse combination (Bluetooth vs USB vs
/// some wireless dongles report differently), so `.inconclusive` is a
/// legitimate, expected result — never a false-confident guess. Downstream
/// copy should read "make sure a keyboard and mouse are connected," not
/// assert a state this probe can't actually back up.
enum InputProbeResult: Sendable, Equatable {
    case detected
    case notDetected
    case inconclusive
}

@MainActor
protocol ExternalInputProbing {
    func probe() -> InputProbeResult
}

/// Live probe: enumerates HID keyboard/pointer devices via `IOHIDManager` and
/// looks for one whose transport isn't Apple's internal keyboard/trackpad
/// transport (`kIOHIDTransportKey` reads "SPI"/"I2C" for the built-in
/// keyboard/trackpad on modern Macs; "USB"/"Bluetooth"/… for anything else).
struct ExternalInputProbe: ExternalInputProbing {
    /// Apple's internal keyboard/trackpad report over these transports.
    /// Anything else is genuinely external.
    private static let internalTransports: Set<String> = ["spi", "i2c"]
    private static let genericDesktopUsagePage = 0x01
    private static let keyboardUsage = 0x06
    private static let pointerUsages: Set<Int> = [0x01, 0x02]  // Pointer, Mouse

    func probe() -> InputProbeResult {
        guard
            let manager = IOHIDManagerCreate(
                kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
                as IOHIDManager?
        else { return .inconclusive }
        // Match every HID device; we filter to keyboards/pointers ourselves
        // below (reading each device's own usage-page/usage is more robust
        // than a matching-dictionary criteria array here).
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else {
            return .inconclusive
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty
        else {
            return .notDetected
        }

        var sawKeyboardOrPointer = false
        for device in devices {
            guard
                let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString)
                    as? Int,
                page == Self.genericDesktopUsagePage,
                let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString)
                    as? Int,
                usage == Self.keyboardUsage || Self.pointerUsages.contains(usage)
            else { continue }
            sawKeyboardOrPointer = true
            let transport =
                (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String)?
                .lowercased()
            if let transport, !Self.internalTransports.contains(transport) {
                return .detected
            }
        }
        // Found keyboard/pointer HID devices but none read as external: a
        // real negative, not a probe failure.
        return sawKeyboardOrPointer ? .notDetected : .inconclusive
    }
}
