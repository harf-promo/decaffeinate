import Combine
import Foundation

/// User-tunable behaviour for the sleep engine, persisted to `UserDefaults` as
/// one JSON blob. Defaults are deliberately *decaffeination-first*: out of the
/// box, an idle Mac that was left running will be put to sleep.
struct DecaffeinateSettings: Codable, Equatable, Sendable {

    // MARK: Decaffeinate (the headline feature)

    /// Master switch for the force-sleep engine.
    var decaffeinateEnabled: Bool = true
    /// Minutes of human inactivity before Decaffeinate forces the Mac to sleep,
    /// overriding any rogue assertion that would otherwise keep it awake.
    var idleThresholdMinutes: Double = 10
    /// On battery, use a shorter idle threshold — save power harder when unplugged.
    var sleepSoonerOnBattery: Bool = true
    /// The shorter idle threshold (minutes) applied on battery when the above is on.
    var batteryIdleThresholdMinutes: Double = 3

    /// The idle threshold in effect for the current power state, clamped to ≥ 1 min.
    func effectiveIdleSeconds(onBattery: Bool) -> TimeInterval {
        let minutes =
            (onBattery && sleepSoonerOnBattery)
            ? Swift.min(idleThresholdMinutes, batteryIdleThresholdMinutes)
            : idleThresholdMinutes
        return max(1, minutes) * 60
    }

    // MARK: Caffeinate (the secondary, opt-in feature)

    /// Hold a keep-awake assertion. Off by default — the whole point of this app
    /// is the opposite. When you do want it, here it is.
    var caffeinateEnabled: Bool = false
    /// Whether keep-awake should also stop the *display* from sleeping.
    var caffeinateKeepsDisplayAwake: Bool = false

    // MARK: Safety rails

    /// On battery, never force sleep below this charge — instead let macOS take
    /// over so nothing is interrupted at a bad moment. (Force-sleep itself is
    /// safe; this is about predictability.) Also drops keep-awake below the floor.
    var batteryFloorPercent: Int = 20
    /// Backpack guard: if the Mac gets thermally stressed (lid closed in a bag),
    /// drop all keep-awake holds and let it sleep immediately.
    var thermalGuardEnabled: Bool = true
    /// Don't force sleep while the microphone is in use — the strongest "you're
    /// probably on a call" signal. Kept separate from `pauseForActiveMedia` so a
    /// user who sleeps aggressively through passive media never accidentally
    /// disables the call guard. Unlike media, this is not idle-capped.
    var pauseForActiveCall: Bool = true
    /// Don't force sleep while something is keeping the *screen* on or playing
    /// audio — a signal of active video, music, or a presentation. Released once
    /// you've been idle well past the idle threshold (a stale/leaked token, e.g.
    /// a forgotten background tab, must not keep the Mac awake forever).
    var pauseForActiveMedia: Bool = true
    /// Don't force sleep during a Time Machine backup.
    var pauseForTimeMachine: Bool = true
    /// Don't force sleep during a macOS software update / install.
    var pauseForSystemUpdate: Bool = true
    /// Respect whitelisted apps: while an allowed app holds the Mac awake, don't
    /// force sleep.
    var respectWhitelist: Bool = true

    // MARK: Schedules

    /// When on, Decaffeinate never *forces* sleep during your active hours — it
    /// stands down so it can't cut off work mid-flow. (macOS's own sleep still
    /// applies; this only suppresses the force-sleep engine.)
    var scheduleEnabled: Bool = false
    /// Start of the active-hours window, an hour-of-day 0...23.
    var activeHoursStart: Int = 9
    /// End of the active-hours window (exclusive), an hour-of-day 0...23. May be
    /// earlier than the start to describe an overnight window (e.g. 22 → 6).
    var activeHoursEnd: Int = 17

    /// Show the live "sleeping in M:SS" countdown next to the menu-bar icon while
    /// a forced sleep is approaching. Off by default to keep the menu bar quiet.
    var showMenuBarCountdown: Bool = false

    // MARK: Firewall / notifications

    /// Post a notification when a *new* unclassified app starts holding the Mac
    /// awake, so you can choose to allow or block it.
    var notifyOnNewBlocker: Bool = true

    // MARK: First run

    /// Set once the user has seen the welcome flow, so it only shows on first run.
    var hasCompletedOnboarding: Bool = false

    // MARK: Advanced

    /// Strict takeover: hold our own idle-sleep assertion so macOS never
    /// idle-sleeps on its own — Decaffeinate becomes the *only* thing that
    /// decides when to sleep. Off by default. If Decaffeinate ever quits or
    /// crashes, the assertion is released and normal macOS sleep resumes.
    var strictTakeoverMode: Bool = false

    /// Start Decaffeinate automatically at login.
    var launchAtLogin: Bool = false

    /// Clamped to at least one minute so a corrupted or hand-edited `0` in
    /// persisted defaults can never disable the idle gate and force constant sleep.
    var idleThresholdSeconds: TimeInterval { max(1, idleThresholdMinutes) * 60 }
}

/// Observable wrapper that loads settings on init and writes them back to
/// `UserDefaults` whenever they change.
@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "DecaffeinateSettings.v1"

    @Published var settings: DecaffeinateSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode(DecaffeinateSettings.self, from: data)
        {
            self.settings = decoded
        } else {
            self.settings = DecaffeinateSettings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
