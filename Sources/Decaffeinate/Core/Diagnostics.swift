import Foundation

/// Builds a copy-pasteable diagnostics report — the thing a user attaches to a
/// bug report so a maintainer can actually reproduce it. Crucially it captures
/// the *effective settings, rules, and schedule* alongside the live scan, since
/// the trickiest bugs are settings *combinations* (keep-awake + battery floor,
/// strict-takeover + auto-sleep off) that a bare `--scan` can't reveal.
///
/// Pure over an injected snapshot, so the composition is unit-testable and never
/// touches the system itself. All app-controlled free text is sanitized.
enum Diagnostics {
    struct Snapshot {
        var version: String
        var macOSVersion: String
        var model: String
        var generatedAt: Date
        var settings: DecaffeinateSettings
        var rules: [Rule]
        var power: PowerSnapshot
        var thermal: ProcessInfo.ThermalState
        var idleSeconds: TimeInterval
        var uptimeSeconds: TimeInterval?
        var stateHeadline: String
        var stateDetail: String
        var systemBlockers: [PowerAssertion]
        var otherAssertions: [PowerAssertion]
    }

    static func report(_ s: Snapshot) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append(""); out.append("## \(title)") }

        out.append("# Decaffeinate diagnostics")
        out.append("Generated: \(iso(s.generatedAt))")
        out.append("Version: \(s.version)")
        out.append("macOS: \(s.macOSVersion) · \(s.model)")

        section("State right now")
        out.append("Verdict: \(clean(s.stateHeadline)) — \(clean(s.stateDetail))")
        out.append("Idle: \(Int(s.idleSeconds))s")
        out.append(powerLine(s.power))
        out.append("Thermal: \(thermalLabel(s.thermal))")
        if let up = s.uptimeSeconds { out.append("Uptime: \(RestartAdvisor.uptimeLabel(up))") }

        section("Effective settings")
        for line in settingsLines(s.settings) { out.append(line) }

        section("App sleep rules (\(s.rules.count))")
        if s.rules.isEmpty {
            out.append("(none)")
        } else {
            for r in s.rules {
                out.append(
                    "• \(clean(r.displayName)) [\(r.bundleIdentifier ?? r.processName)] → \(r.policy.shortLabel)"
                )
            }
        }

        section("Holding system sleep (\(s.systemBlockers.count))")
        if s.systemBlockers.isEmpty {
            out.append("(nothing)")
        } else {
            for a in s.systemBlockers { out.append(blockerLine(a, now: s.generatedAt)) }
        }

        if !s.otherAssertions.isEmpty {
            section("Screen-only / background (\(s.otherAssertions.count))")
            for a in s.otherAssertions { out.append(blockerLine(a, now: s.generatedAt)) }
        }

        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - Lines

    private static func settingsLines(_ s: DecaffeinateSettings) -> [String] {
        [
            "auto-sleep (decaffeinateEnabled): \(s.decaffeinateEnabled)",
            "idle threshold: \(Int(s.idleThresholdMinutes)) min (battery: \(Int(s.batteryIdleThresholdMinutes)) min, sleepSoonerOnBattery: \(s.sleepSoonerOnBattery))",
            "keep-awake (caffeinateEnabled): \(s.caffeinateEnabled) (display: \(s.caffeinateKeepsDisplayAwake))",
            "strict takeover: \(s.strictTakeoverMode)",
            "triggers: \(s.triggers.count)",
            "battery floor: \(s.batteryFloorPercent)% · thermal guard: \(s.thermalGuardEnabled)",
            "pause for: call=\(s.pauseForActiveCall) media=\(s.pauseForActiveMedia) timeMachine=\(s.pauseForTimeMachine) update=\(s.pauseForSystemUpdate) whitelist=\(s.respectWhitelist)",
            "schedule: \(s.scheduleEnabled) (\(s.activeHoursStart):00–\(s.activeHoursEnd):00)",
            "auto-sleep on agent finish: \(s.autoSleepWhenAgentFinishes)",
            "restart recommendation: \(s.restartRecommendationDays) days",
            "launch at login: \(s.launchAtLogin) · menu-bar countdown: \(s.showMenuBarCountdown)",
        ]
    }

    private static func blockerLine(_ a: PowerAssertion, now: Date) -> String {
        let owner = a.realOwner.map { " (via \(a.processName) → \(clean($0.name)))" } ?? ""
        let held =
            a.createdAt.map { " · held \(Format.duration(max(0, now.timeIntervalSince($0))))" }
            ?? ""
        let auto = a.reason.autoReleaseSeconds.map { " · auto-releases \($0)s" } ?? ""
        return
            "• \(clean(a.displayName))\(owner) — \(clean(a.reason.explanation)) [\(a.assertionType)]\(held)\(auto)"
    }

    private static func powerLine(_ p: PowerSnapshot) -> String {
        if p.onBattery {
            let pct = p.chargePercent.map { "\($0)%" } ?? "?"
            return "Power: battery \(pct)\(p.isCharging ? " (charging)" : "")"
        }
        return "Power: AC"
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

    private static func clean(_ s: String) -> String { ReasonEngine.sanitize(s, maxLength: 200) }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
