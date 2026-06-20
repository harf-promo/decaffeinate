import Foundation
import IOKit.pwr_mgt

/// Holds keep-awake power assertions on Decaffeinate's behalf.
///
/// Two independent holds are tracked: one that stops the *system* from
/// idle-sleeping (used by both the opt-in caffeine toggle and strict-takeover
/// mode) and one that additionally stops the *display* from sleeping. The
/// engine reconciles the live IOKit state to a desired state idempotently, so
/// callers can just describe what they want on every tick.
@MainActor
final class CaffeineEngine {
    private var systemAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var displayAssertionID: IOPMAssertionID = IOPMAssertionID(0)

    private(set) var holdingSystem = false
    private(set) var holdingDisplay = false

    var isActive: Bool { holdingSystem || holdingDisplay }

    /// Reconcile the held assertions to the desired state.
    /// - Parameters:
    ///   - keepSystemAwake: prevent the machine from idle-sleeping.
    ///   - keepDisplayAwake: also prevent the display from sleeping.
    ///   - reason: human-readable reason recorded with the assertion (shows up
    ///     in `pmset -g assertions`, so make it legible).
    func update(keepSystemAwake: Bool, keepDisplayAwake: Bool, reason: String) {
        reconcile(
            hold: keepSystemAwake,
            currentlyHolding: &holdingSystem,
            assertionID: &systemAssertionID,
            type: kIOPMAssertionTypePreventUserIdleSystemSleep,
            reason: reason
        )
        reconcile(
            hold: keepDisplayAwake,
            currentlyHolding: &holdingDisplay,
            assertionID: &displayAssertionID,
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            reason: reason
        )
    }

    /// Release everything. Called on quit and by the safety rails.
    func releaseAll() {
        update(keepSystemAwake: false, keepDisplayAwake: false, reason: "")
    }

    private func reconcile(
        hold: Bool,
        currentlyHolding: inout Bool,
        assertionID: inout IOPMAssertionID,
        type: String,
        reason: String
    ) {
        if hold, !currentlyHolding {
            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
                currentlyHolding = true
            }
        } else if !hold, currentlyHolding {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
            currentlyHolding = false
        }
    }
}
