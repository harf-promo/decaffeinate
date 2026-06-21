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

    /// How long past the idle threshold a *media* (audio-out / display-on) hold
    /// is honored before it's treated as stale and force-sleep is allowed. The
    /// microphone (call) hold is deliberately exempt — a long, passive call is
    /// normal and wrongly sleeping through it is unacceptable.
    static let staleMediaGraceSeconds: TimeInterval = 1800  // 30 min

    static func evaluate(
        assertions: [PowerAssertion],
        power: PowerSnapshot,
        thermalState: ProcessInfo.ThermalState,
        idleSeconds: TimeInterval = 0,
        whitelistedAwakeAppNames: [String],
        settings: DecaffeinateSettings
    ) -> SafetyDecision {
        var decision = SafetyDecision()

        // --- Immediate-sleep guards (these win over keep-awake) ---
        if settings.thermalGuardEnabled, thermalState == .critical {
            decision.immediateSleepReasons.append("Mac is overheating (backpack guard)")
        }
        if power.onBattery, let pct = power.chargePercent, pct <= 3 {
            // Force sleep AND drop any keep-awake hold: if we don't also drop the
            // hold, a user-set battery floor of ≤3% would let us try to force sleep
            // while still asserting keep-awake — a self-contradiction. (Thermal-
            // critical below already does both; this keeps the two guards in step.)
            let reason = "Battery critically low (\(pct)%)"
            decision.immediateSleepReasons.append(reason)
            decision.dropKeepAwakeReasons.append(reason)
        }

        // --- Drop keep-awake overrides (but don't force sleep on an active user) ---
        if settings.thermalGuardEnabled, thermalState == .serious || thermalState == .critical {
            decision.dropKeepAwakeReasons.append("Thermal pressure is high")
        }
        if power.onBattery, let pct = power.chargePercent, pct < settings.batteryFloorPercent {
            decision.dropKeepAwakeReasons.append(
                "Battery below \(settings.batteryFloorPercent)% floor")
        }

        // --- Hold-off reasons for the idle force-sleep engine ---
        if settings.respectWhitelist, !whitelistedAwakeAppNames.isEmpty {
            let list = whitelistedAwakeAppNames.joined(separator: ", ")
            decision.holdForceSleepReasons.append("Allowed app keeping awake: \(list)")
        }
        // Microphone/call: the strongest "don't sleep" signal, never idle-capped.
        let mediaHoldFresh =
            idleSeconds < settings.effectiveIdleSeconds(onBattery: power.onBattery)
            + staleMediaGraceSeconds
        if settings.pauseForActiveCall, isMicrophoneActive(assertions) {
            decision.holdForceSleepReasons.append("Microphone is in use (likely a call)")
        } else if settings.pauseForActiveMedia, mediaHoldFresh, isMediaActive(assertions) {
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

    /// `audio-in` in an assertion's resources means the microphone is live —
    /// an honest "you're probably on a call" signal from public IOKit.
    static func isMicrophoneActive(_ assertions: [PowerAssertion]) -> Bool {
        assertions.contains { $0.resources.contains { $0.lowercased() == "audio-in" } }
    }

    /// Active media: a display-sleep assertion (video/screen-share/call) or an
    /// `audio-out` resource (something is playing sound).
    static func isMediaActive(_ assertions: [PowerAssertion]) -> Bool {
        assertions.contains {
            $0.kind == .displaySleep || $0.resources.contains { $0.lowercased() == "audio-out" }
        }
    }

    /// Trust only the verified owning process, not the caller-controlled
    /// assertion *name*: any app can register a hold named "Backup" or "Software
    /// Update" to dodge force-sleep, so a free-text keyword match here would be a
    /// trivial safety bypass. `processName` is resolved from the real PID.
    static func isTimeMachineActive(_ assertions: [PowerAssertion]) -> Bool {
        assertions.contains { $0.processName.lowercased() == "backupd" }
    }

    static func isSystemUpdateActive(_ assertions: [PowerAssertion]) -> Bool {
        let updaters: Set<String> = ["softwareupdated", "installd", "system_installd"]
        return assertions.contains { updaters.contains($0.processName.lowercased()) }
    }
}
