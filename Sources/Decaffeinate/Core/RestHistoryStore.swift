import Combine
import Foundation

/// Persists a rolling log of the Mac's rest rhythm (newest first) — sleeps,
/// wakes, screen rests, and inferred restarts. Separate from `SleepHistoryStore`
/// (which is *forced sleeps only* with a "wake avoided" estimate); this is the
/// passive timeline behind the Rest & Restart pillar. Own `UserDefaults` key, so
/// no migration risk to the existing sleep history.
@MainActor
final class RestHistoryStore: ObservableObject {
    private static let key = "DecaffeinateRestHistory.v1"
    private let maxEvents = 50

    @Published private(set) var events: [RestEvent] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([RestEvent].self, from: data)
        {
            self.events = decoded
        } else {
            self.events = []
        }
    }

    func record(_ event: RestEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    func clear() { events = [] }

    var lastSystemSleep: RestEvent? {
        events.first { $0.kind == .systemSleep || $0.kind == .forcedSleep }
    }
    var lastDisplayOff: RestEvent? { events.first { $0.kind == .displayOff } }
    var lastRestart: RestEvent? { events.first { $0.kind == .restart } }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
