import Foundation
import IOKit

/// Whether this Mac has a lid at all, and whether it's currently closed.
///
/// Read from the `IOPMrootDomain`'s `AppleClamshellState` IORegistry
/// property — a **public IORegistry read** (`IOServiceGetMatchingService` +
/// `IORegistryEntryCreateCFProperty` on the well-known `IOPMrootDomain`
/// service), the same technique third-party lid-monitoring utilities have
/// used for roughly two decades. This is NOT one of the private,
/// entitlement-gated APIs `docs/ARCHITECTURE.md` already rules out for
/// *forcing* sleep prevention (`RootDomainUserClient` selector 12,
/// `IOPMSetSystemPowerSetting`, …) — those try to change kernel behavior;
/// this only *reads* a published property, the same trust boundary as
/// `PowerSourceReader`/`SystemStateReader`.
struct LidSnapshot: Sendable, Equatable {
    /// `false` on a desktop Mac (Mac mini/Studio/Pro) — no lid, so every
    /// downstream consumer (`ClamshellAdvisor`, the readiness panel) degrades
    /// cleanly instead of showing nonsense on hardware with no lid.
    let isPresent: Bool
    /// Only meaningful when `isPresent` is true.
    let isClosed: Bool

    /// The safe default: no lid, not closed. Used whenever the registry read
    /// fails or the key is absent — fail closed to "not applicable" rather
    /// than crash or guess at a lid state that isn't there.
    static let notPresent = LidSnapshot(isPresent: false, isClosed: false)
}

@MainActor
protocol LidStateReading {
    func snapshot() -> LidSnapshot
}

/// Live reader: `IOPMrootDomain`'s `AppleClamshellState` boolean property.
struct LidStateReader: LidStateReading {
    func snapshot() -> LidSnapshot {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return .notPresent }
        defer { IOObjectRelease(service) }
        guard
            let property = IORegistryEntryCreateCFProperty(
                service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
            let isClosed = property as? Bool
        else {
            // Absent/unreadable key: fail closed to "not applicable" rather
            // than guess a lid state that isn't there.
            return .notPresent
        }
        return LidSnapshot(isPresent: true, isClosed: isClosed)
    }
}
