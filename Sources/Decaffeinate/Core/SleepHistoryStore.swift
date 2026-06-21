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

    /// A *rough, clearly-labelled* estimate: assume each forced sleep avoided
    /// ~15 minutes of needless wake. Honest about being an approximation.
    var estimatedMinutesAvoided: Int { events.count * 15 }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
