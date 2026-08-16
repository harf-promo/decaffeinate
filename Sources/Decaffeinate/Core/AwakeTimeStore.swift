import Combine
import Foundation

/// One day's cumulative held-seconds for one app — the unit `AwakeTimeStore`
/// persists. `day` is always truncated to the start of its calendar day, so
/// every tick that finds the same app holding on the same day accumulates
/// into one entry instead of the log growing without bound.
struct AwakeTimeEntry: Codable, Hashable, Sendable {
    var day: Date
    var appName: String
    var seconds: TimeInterval
}

extension AwakeTimeEntry {
    /// Resilient decode: every field uses `decodeIfPresent` with a safe default,
    /// mirroring `SleepEvent`'s pattern — so adding a field later degrades one old
    /// record gracefully instead of failing the entire persisted array. Encode
    /// stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let day = try c.decodeIfPresent(Date.self, forKey: .day) ?? Date()
        let appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? ""
        let seconds = try c.decodeIfPresent(TimeInterval.self, forKey: .seconds) ?? 0
        self.init(day: day, appName: appName, seconds: seconds)
    }
}

/// Persists a rolling, per-day-per-app tally of how long each app has held the
/// Mac awake — the data behind "which app held your Mac awake longest this
/// week." Mirrors `SleepHistoryStore`'s shape (an `ObservableObject` that loads
/// once and writes back to `UserDefaults` on every change), bounded so it never
/// grows without limit.
///
/// This is a *measured accumulation*, not a heuristic: `AppState.tick()` feeds
/// `record(appName:seconds:)` once per tick with the actual elapsed wall-clock
/// time since the previous tick for every app currently blocking system sleep
/// — never a flat "1 tick = 1 second" assumption, since the underlying
/// `Timer` has a 0.25 s tolerance and can drift further under load.
@MainActor
final class AwakeTimeStore: ObservableObject {
    private static let key = "DecaffeinateAwakeTime.v1"
    /// Keep a bit more than a week so "this week" always has a full week of
    /// data behind it regardless of when in the day `clear()`/prune runs, without
    /// the log growing without bound.
    private let maxDays = 14

    @Published private(set) var entries: [AwakeTimeEntry] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([AwakeTimeEntry].self, from: data)
        {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    /// Accumulate `seconds` of held time for `appName` on `date`'s calendar day,
    /// merging into that day's existing entry for the app if one exists. A no-op
    /// for a non-positive duration or an empty name (defensive — callers should
    /// never pass either, but a silent no-op is safer than a bogus zero-day entry).
    func record(appName: String, seconds: TimeInterval, date: Date = Date()) {
        guard seconds > 0, !appName.isEmpty else { return }
        let day = calendar.startOfDay(for: date)
        if let i = entries.firstIndex(where: { $0.day == day && $0.appName == appName }) {
            entries[i].seconds += seconds
        } else {
            entries.append(AwakeTimeEntry(day: day, appName: appName, seconds: seconds))
        }
        pruneOldEntries(referenceDate: date)
    }

    func clear() { entries = [] }

    /// App name → total held seconds over the last 7 days (inclusive of today),
    /// ranked highest-first, capped at `limit` — the "This week" list.
    func weeklyRanking(now: Date = Date(), limit: Int = 8) -> [(
        appName: String, seconds: TimeInterval
    )] {
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: now) else { return [] }
        let cutoff = calendar.startOfDay(for: weekAgo)
        var totals: [String: TimeInterval] = [:]
        for entry in entries where entry.day >= cutoff {
            totals[entry.appName, default: 0] += entry.seconds
        }
        return
            totals
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (appName: $0.key, seconds: $0.value) }
    }

    /// Drop entries older than `maxDays` before `referenceDate` — called after
    /// every `record` so the log self-trims instead of needing a separate sweep.
    private func pruneOldEntries(referenceDate: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -maxDays, to: referenceDate) else {
            return
        }
        let cutoffDay = calendar.startOfDay(for: cutoff)
        entries.removeAll { $0.day < cutoffDay }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
