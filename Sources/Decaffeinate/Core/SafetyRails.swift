import Foundation

/// The outcome of evaluating every safety rail against the current system state.
/// Pure value type so the decision logic is fully unit-testable.
struct SafetyDecision: Equatable, Sendable {
    /// Reasons to release any keep-awake / takeover assertion (e.g. low battery).
    var dropKeepAwakeReasons: [String] = []
    /// Reasons to put the Mac to sleep *immediately*, regardless of idle time
    /// (the backpack / overheating guard).
    var immediateSleepReasons: [String] = []
    /// Reasons the idle force-sleep engine should hold off (active media, an
    /// in-progress backup, a whitelisted app, …).
    var holdForceSleepReasons: [String] = []

    var mustSleepNow: Bool { !immediateSleepReasons.isEmpty }
    var shouldDropKeepAwake: Bool { !dropKeepAwakeReasons.isEmpty }
    var canForceSleep: Bool { holdForceSleepReasons.isEmpty }
}

/// Evaluates the PRD's safety rails from already-collected, in-process signals.
/// No subprocesses, no polling: Time Machine, software updates and media are all
/// detected from the same assertion snapshot the scanner already produces.
enum SafetyRails {

    static func evaluate(
        assertions: [PowerAssertion],
        power: PowerSnapshot,
        thermalState: ProcessInfo.ThermalState,
        whitelistedAwakeAppNames: [String],
        settings: DecaffeinateSettings
    ) -> SafetyDecision {
        var decision = SafetyDecision()

        // --- Immediate-sleep guards (these win over keep-awake) ---
        if settings.thermalGuardEnabled, thermalState == .critical {
            decision.immediateSleepReasons.append("Mac is overheating (backpack guard)")
        }
        if power.onBattery, let pct = power.chargePercent, pct <= 3 {
            decision.immediateSleepReasons.append("Battery critically low (\(pct)%)")
        }

        // --- Drop keep-awake overrides (but don't force sleep on an active user) ---
        if settings.thermalGuardEnabled, thermalState == .serious || thermalState == .critical {
            decision.dropKeepAwakeReasons.append("Thermal pressure is high")
        }
        if power.onBattery, let pct = power.chargePercent, pct < settings.batteryFloorPercent {
            decision.dropKeepAwakeReasons.append("Battery below \(settings.batteryFloorPercent)% floor")
        }

        // --- Hold-off reasons for the idle force-sleep engine ---
        if settings.respectWhitelist, !whitelistedAwakeAppNames.isEmpty {
            let list = whitelistedAwakeAppNames.joined(separator: ", ")
            decision.holdForceSleepReasons.append("Allowed app keeping awake: \(list)")
        }
        if settings.pauseForActiveMedia, isMediaActive(assertions) {
            decision.holdForceSleepReasons.append("Media or a call appears active")
        }
        if settings.pauseForTimeMachine, isTimeMachineActive(assertions) {
            decision.holdForceSleepReasons.append("Time Machine backup in progress")
        }
        if settings.pauseForSystemUpdate, isSystemUpdateActive(assertions) {
            decision.holdForceSleepReasons.append("macOS update or install in progress")
        }

        return decision
    }

    // MARK: Detectors (in-process, from the assertion snapshot)

    /// A display-sleep assertion is the macOS-blessed signal for "the user is
    /// watching something" — video players, screen-sharing, and video calls all
    /// raise one. Treat its presence as active media.
    static func isMediaActive(_ assertions: [PowerAssertion]) -> Bool {
        assertions.contains { $0.kind == .displaySleep }
    }

    static func isTimeMachineActive(_ assertions: [PowerAssertion]) -> Bool {
        assertions.contains { assertion in
            matches(assertion, processes: ["backupd"], keywords: ["time machine", "backup"])
        }
    }

    static func isSystemUpdateActive(_ assertions: [PowerAssertion]) -> Bool {
        assertions.contains { assertion in
            matches(
                assertion,
                processes: ["softwareupdated", "installd", "system_installd", "Installer"],
                keywords: ["install macos", "software update", "softwareupdate", "os install"]
            )
        }
    }

    private static func matches(_ assertion: PowerAssertion,
                                processes: [String],
                                keywords: [String]) -> Bool {
        let proc = assertion.processName.lowercased()
        if processes.contains(where: { proc == $0.lowercased() }) { return true }
        let haystack = (assertion.name + " " + assertion.processName).lowercased()
        return keywords.contains { haystack.contains($0) }
    }
}
