import Foundation

/// A record of one forced sleep — the timeline behind "here's every time I put
/// your Mac to sleep and why". Deliberately minimal: process/reason text only,
/// never raw assertion names that could be sensitive.
struct SleepEvent: Codable, Identifiable, Hashable, Sendable {
    /// The user-facing copy for a stored `reason`.
    ///
    /// Reasons are persisted in canonical English (see `AppState.forceSleep`
    /// callers and `SafetyRails`) and localized only when shown, so history
    /// recorded before a language change still reads in the current language.
    /// Unrecognized reasons pass through unchanged.
    static func localizedReason(_ reason: String) -> String {
        switch reason {
        case "Sleep Now pressed", "Sleep Now pressed (confirmed during a call)":
            return L10n.localized(reason)
        case "Watched work finished \u{2014} putting Mac to sleep":
            return L10n.localized("Watched work finished \u{2014} putting Mac to sleep")
        default: break
        }
        let idle = (prefix: "Idle ", suffix: " min \u{2014} putting Mac to sleep")
        if reason.hasPrefix(idle.prefix), reason.hasSuffix(idle.suffix),
            let minutes = Int(reason.dropFirst(idle.prefix.count).dropLast(idle.suffix.count))
        {
            return L10n.localized("Idle %ld min \u{2014} putting Mac to sleep", minutes)
        }
        return SafetyRails.localizedReason(reason)
    }

    var id: UUID
    var date: Date
    var reason: String
    var onBattery: Bool
    /// Measured seconds the Mac actually stayed asleep after this forced sleep.
    /// Filled in when the matching wake event arrives; `nil` until then (and
    /// permanently nil if we never observe a wake, e.g. the app was quit first).
    var sleptSeconds: TimeInterval?

    init(
        id: UUID = UUID(), date: Date, reason: String, onBattery: Bool,
        sleptSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.date = date
        self.reason = reason
        self.onBattery = onBattery
        self.sleptSeconds = sleptSeconds
    }
}

extension SleepEvent {
    /// Resilient decode: every field uses `decodeIfPresent` with a safe default,
    /// so adding a new field in a later version degrades one old record gracefully
    /// instead of failing the entire persisted array. Encode stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        let reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        let onBattery = try c.decodeIfPresent(Bool.self, forKey: .onBattery) ?? false
        let sleptSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .sleptSeconds)
        self.init(
            id: id, date: date, reason: reason, onBattery: onBattery, sleptSeconds: sleptSeconds)
    }
}
