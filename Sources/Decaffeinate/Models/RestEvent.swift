import Foundation

/// One moment in the Mac's natural rest rhythm — distinct from `SleepEvent`,
/// which logs *forced* sleeps only. This is the passive timeline behind the
/// "Rest & Restart" pillar: system sleeps/wakes, screen rests, and the inferred
/// restart across launches.
struct RestEvent: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case forcedSleep  // Decaffeinate forced it (mirrors a SleepEvent)
        case systemSleep  // NSWorkspace.willSleepNotification
        case wake  // NSWorkspace.didWakeNotification
        case displayOff  // screensDidSleepNotification
        case displayOn  // screensDidWakeNotification
        case restart  // inferred: boot time advanced across a launch
        case launch  // app launched; carries the uptime at launch

        /// Resilient decode: an unknown future kind decodes to `.systemSleep`
        /// rather than failing the whole event.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .systemSleep
        }

        var label: String {
            switch self {
            case .forcedSleep: return "Forced to sleep"
            case .systemSleep: return "Slept"
            case .wake: return "Woke"
            case .displayOff: return "Screen rested"
            case .displayOn: return "Screen on"
            case .restart: return "Restarted"
            case .launch: return "Decaffeinate launched"
            }
        }

        var symbol: String {
            switch self {
            case .forcedSleep, .systemSleep: return "moon.zzz.fill"
            case .wake: return "sun.max.fill"
            case .displayOff: return "display.trianglebadge.exclamationmark"
            case .displayOn: return "display"
            case .restart: return "arrow.clockwise.circle.fill"
            case .launch: return "bolt.fill"
            }
        }
    }

    var id: UUID
    var date: Date
    var kind: Kind
    var onBattery: Bool
    /// For `.restart` / `.launch`: the uptime (seconds) observed at that moment.
    var uptimeSeconds: TimeInterval?

    init(
        id: UUID = UUID(), date: Date, kind: Kind, onBattery: Bool = false,
        uptimeSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.onBattery = onBattery
        self.uptimeSeconds = uptimeSeconds
    }
}
