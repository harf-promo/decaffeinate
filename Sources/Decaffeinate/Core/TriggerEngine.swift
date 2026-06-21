import AppKit
import Darwin

/// A condition that, while true, *keeps the Mac awake* — the opt-in inverse of
/// the decaffeinate engine, for the "stay awake while X is happening" cases
/// (the main feature gap vs Amphetamine). Pure value type, fully testable.
enum TriggerCondition: Codable, Equatable, Hashable, Sendable {
    /// While a process / app whose name contains this string is running.
    case appRunning(String)
    /// While the Mac is on AC power.
    case onACPower
    /// While system CPU load is at or above this percentage.
    case cpuAbove(Int)

    var label: String {
        switch self {
        case .appRunning(let name): return "While “\(name)” is running"
        case .onACPower: return "While on AC power"
        case .cpuAbove(let pct): return "While CPU is above \(pct)%"
        }
    }
}

/// One user-configured trigger rule.
struct TriggerRule: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var condition: TriggerCondition
    var enabled: Bool

    init(id: UUID = UUID(), condition: TriggerCondition, enabled: Bool = true) {
        self.id = id
        self.condition = condition
        self.enabled = enabled
    }
}

/// The live signals the engine evaluates rules against.
struct TriggerSignals: Equatable, Sendable {
    var runningAppNames: Set<String>  // lowercased
    var onACPower: Bool
    var cpuPercent: Double
}

/// Pure: decide whether any enabled trigger is currently satisfied, and why.
enum TriggerEngine {
    /// The reason of the first satisfied enabled rule, or `nil` if none apply.
    static func activeReason(rules: [TriggerRule], signals: TriggerSignals) -> String? {
        for rule in rules where rule.enabled {
            switch rule.condition {
            case .appRunning(let name):
                let needle = name.lowercased()
                if !needle.isEmpty, signals.runningAppNames.contains(where: { $0.contains(needle) })
                {
                    return "“\(name)” is running"
                }
            case .onACPower:
                if signals.onACPower { return "On AC power" }
            case .cpuAbove(let pct):
                if signals.cpuPercent >= Double(pct) {
                    return "CPU is busy (\(Int(signals.cpuPercent))%)"
                }
            }
        }
        return nil
    }
}

/// Injectable seam so `AppState` can be tested with deterministic signals.
@MainActor
protocol TriggerSampling {
    func sample(onACPower: Bool) -> TriggerSignals
}

/// The real sampler: running apps from `NSWorkspace`, system CPU from Mach.
@MainActor
final class LiveTriggerSampler: TriggerSampling {
    private let cpu = CPUSampler()

    func sample(onACPower: Bool) -> TriggerSignals {
        let names = Set(
            NSWorkspace.shared.runningApplications.compactMap {
                $0.localizedName?.lowercased()
            })
        return TriggerSignals(
            runningAppNames: names, onACPower: onACPower, cpuPercent: cpu.sample())
    }
}

/// System-wide CPU usage from the Mach host load counters (delta between ticks).
@MainActor
final class CPUSampler {
    private var previous: host_cpu_load_info?

    func sample() -> Double {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { previous = info }
        guard let prev = previous else { return 0 }
        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return (user + system + nice) / total * 100
    }
}
