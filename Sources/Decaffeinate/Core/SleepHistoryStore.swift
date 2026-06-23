import Combine
import Foundation

/// Persists a rolling log of forced sleeps (newest first) to `UserDefaults`,
/// mirroring `RulesEngine`'s persistence pattern. Bounded so it never grows
/// without limit.
@MainActor
final class SleepHistoryStore: ObservableObject {
    private static let key = "DecaffeinateHistory.v1"
    private let maxEvents = 50

    @Published private(set) var events: [SleepEvent] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([SleepEvent].self, from: data)
        {
            self.events = decoded
        } else {
            self.events = []
        }
    }

    func record(_ event: SleepEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    func clear() { events = [] }

    var batteryCount: Int { events.filter(\.onBattery).count }

    /// Total *measured* time the Mac stayed asleep after Decaffeinate-forced sleeps,
    /// in minutes — counting only events where a wake was actually observed. Use
    /// `unmeasuredSleepCount` to surface the complementary "not yet measured" count.
    ///
    /// This is a real, grounded measurement — not a counterfactual claim about
    /// "wake avoided." The UI labels it accordingly.
    var measuredMinutesAsleep: Int {
        Int(events.compactMap(\.sleptSeconds).reduce(0, +) / 60)
    }

    /// Number of forced sleeps whose wake was never observed — the app was quit
    /// before the Mac woke, or the wake fired before observers registered.
    var unmeasuredSleepCount: Int {
        events.filter { $0.sleptSeconds == nil }.count
    }

    /// Pair the most-recent unmatched forced sleep with an observed wake so we can
    /// measure how long the Mac actually stayed asleep. A 4-hour cap guards against
    /// pairing with a wake from a completely different sleep session (e.g. if the
    /// user manually sleeps the Mac hours after Decaffeinate's last forced sleep).
    func recordWakeDuration(at wakeDate: Date, maxGap: TimeInterval = 14_400) {
        guard
            let i = events.indices.first(where: {
                events[$0].sleptSeconds == nil
                    && events[$0].date <= wakeDate
            })
        else { return }
        let duration = wakeDate.timeIntervalSince(events[i].date)
        guard duration > 0, duration <= maxGap else { return }
        events[i].sleptSeconds = duration
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
