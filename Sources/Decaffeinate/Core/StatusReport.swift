import Foundation

/// Machine-readable status — the JSON behind `Decaffeinate --status --json` and
/// `--why-awake --json`, so scripts, agent hooks, and CI can ask "is my Mac
/// free to sleep?" without scraping human text. Pure `Codable` over a snapshot,
/// so the shape is stable and unit-testable. All app-controlled free text is
/// sanitized before it enters a field.
struct StatusReport: Codable, Equatable {
    var version: String
    var generatedAt: String  // ISO-8601
    var onBattery: Bool
    var batteryPercent: Int?
    var idleSeconds: Int
    var thermal: String
    var uptimeSeconds: Int?
    var holdingSystemSleep: Int
    var blockers: [Blocker]

    struct Blocker: Codable, Equatable {
        var app: String
        var reason: String
        var type: String
        var realOwner: String?
        var heldSeconds: Int?
        var pid: Int32
        var blocksSystemSleep: Bool
    }

    /// Build from a live scan + sensed state. `now` and `ownPID` are injected so
    /// the composition is deterministic and excludes Decaffeinate's own hold.
    static func from(
        version: String, now: Date, ownPID: pid_t,
        assertions: [PowerAssertion], power: PowerSnapshot,
        thermal: ProcessInfo.ThermalState, idleSeconds: TimeInterval, uptimeSeconds: TimeInterval?
    ) -> StatusReport {
        let visible = assertions.filter { $0.pid != ownPID }
        let system = visible.filter(\.blocksSystemSleep)
        let blockers = visible.map { a -> Blocker in
            Blocker(
                app: clean(a.displayName),
                reason: clean(a.reason.explanation),
                type: a.assertionType,
                realOwner: a.realOwner.map { clean($0.name) },
                heldSeconds: a.createdAt.map { Int(max(0, now.timeIntervalSince($0))) },
                pid: a.pid,
                blocksSystemSleep: a.blocksSystemSleep)
        }
        return StatusReport(
            version: version,
            generatedAt: iso(now),
            onBattery: power.onBattery,
            batteryPercent: power.chargePercent,
            idleSeconds: Int(idleSeconds),
            thermal: thermalLabel(thermal),
            uptimeSeconds: uptimeSeconds.map(Int.init),
            holdingSystemSleep: system.count,
            blockers: blockers)
    }

    /// Pretty, stable JSON (sorted keys) — friendly for humans and diffs alike.
    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8)
        else { return "{}" }
        return s
    }

    private static func clean(_ s: String) -> String { ReasonEngine.sanitize(s, maxLength: 200) }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func thermalLabel(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
