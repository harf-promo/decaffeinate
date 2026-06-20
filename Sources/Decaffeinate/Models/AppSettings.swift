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
    /// Don't force sleep while something is keeping the *screen* on — a strong
    /// signal of an active video, call, or presentation.
    var pauseForActiveMedia: Bool = true
    /// Don't force sleep during a Time Machine backup.
    var pauseForTimeMachine: Bool = true
    /// Don't force sleep during a macOS software update / install.
    var pauseForSystemUpdate: Bool = true
    /// Respect whitelisted apps: while an allowed app holds the Mac awake, don't
    /// force sleep.
    var respectWhitelist: Bool = true

    // MARK: Firewall / notifications

    /// Post a notification when a *new* unclassified app starts holding the Mac
    /// awake, so you can choose to allow or block it.
    var notifyOnNewBlocker: Bool = true

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
