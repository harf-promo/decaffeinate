import Foundation

/// A record of one forced sleep — the timeline behind "here's every time I put
/// your Mac to sleep and why". Deliberately minimal: process/reason text only,
/// never raw assertion names that could be sensitive.
struct SleepEvent: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var reason: String
    var onBattery: Bool

    init(id: UUID = UUID(), date: Date, reason: String, onBattery: Bool) {
        self.id = id
        self.date = date
        self.reason = reason
        self.onBattery = onBattery
    }
}
