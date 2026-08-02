import Foundation

/// The individual requirements Apple's own clamshell mode needs, named so the
/// UI can list exactly what's missing instead of a blanket "not ready."
enum ClamshellRequirement: String, Equatable, Sendable, CaseIterable {
    case power
    case externalDisplay
    case externalInput

    /// Plain-language instruction for the readiness panel.
    var label: String {
        switch self {
        case .power: return "Connect to power"
        case .externalDisplay: return "Plug in an external display"
        case .externalInput: return "Connect a keyboard and mouse"
        }
    }
}

/// The Clamshell Advisor's classification of whether this Mac is ready for
/// Apple's own built-in clamshell mode (lid closed + external display + AC
/// power + external keyboard/mouse).
enum ClamshellReadiness: Equatable, Sendable {
    /// This Mac has no lid (desktop) — clamshell mode doesn't apply.
    case notApplicable
    /// Every requirement Apple's clamshell mode needs is met.
    case ready
    /// At least one requirement is missing; `unmet` names which.
    case missing(unmet: Set<ClamshellRequirement>)
}

/// Pure, static decision engine — mirrors `SafetyRails.evaluate`'s shape
/// exactly: no IOKit/CoreGraphics calls live inside it, only the already-read
/// snapshots the caller (`AppState`, the CLI, the MCP server) collected. Fully
/// unit-testable without a live system.
enum ClamshellAdvisor {
    static func classify(
        lid: LidSnapshot,
        displays: DisplayTopology,
        power: PowerSnapshot,
        input: InputProbeResult
    ) -> ClamshellReadiness {
        guard lid.isPresent else { return .notApplicable }

        var unmet: Set<ClamshellRequirement> = []
        if power.onBattery { unmet.insert(.power) }
        if !displays.hasExternalDisplay { unmet.insert(.externalDisplay) }
        // Only an explicit "not detected" counts against readiness — an
        // inconclusive probe is not evidence of *absence* (see
        // `InputProbeResult`'s doc comment): a keyboard/mouse this probe
        // can't see is still plausibly there, and treating "inconclusive" as
        // "missing" would be false-confident in the other direction.
        if input == .notDetected { unmet.insert(.externalInput) }

        return unmet.isEmpty ? .ready : .missing(unmet: unmet)
    }
}

/// Machine-readable status for `Decaffeinate --clamshell-status --json` and
/// the `clamshell_status` MCP tool — the same stable-sorted-keys `Codable`
/// convention as `StatusReport`.
struct ClamshellStatusReport: Codable, Equatable {
    /// "notApplicable" | "ready" | "missing"
    var state: String
    /// `ClamshellRequirement` raw values still unmet; empty unless `state == "missing"`.
    var missing: [String]

    static func from(readiness: ClamshellReadiness) -> ClamshellStatusReport {
        switch readiness {
        case .notApplicable:
            return ClamshellStatusReport(state: "notApplicable", missing: [])
        case .ready:
            return ClamshellStatusReport(state: "ready", missing: [])
        case .missing(let unmet):
            let names = ClamshellRequirement.allCases.filter { unmet.contains($0) }.map(\.rawValue)
            return ClamshellStatusReport(state: "missing", missing: names)
        }
    }

    /// Pretty, stable JSON (sorted keys) — matches `StatusReport.jsonString()`.
    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8)
        else { return "{}" }
        return s
    }
}
