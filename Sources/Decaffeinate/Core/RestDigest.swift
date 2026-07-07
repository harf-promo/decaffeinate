import Foundation

/// A one-line "while you were away" recap of the Mac's recent rest — mirrors the
/// trust-building morning summary that agent-scoped tools show on lid-open, but
/// built entirely from the rest timeline Decaffeinate already keeps. Pure over
/// the event list + a clock, so it's fully unit-testable.
enum RestDigest {

    /// Summarise rest activity within `window` before `now` (default 12h).
    /// Returns nil when nothing noteworthy happened, so the UI can hide the line.
    static func summary(
        rest: [RestEvent], now: Date, window: TimeInterval = 12 * 3600
    ) -> String? {
        let since = now.addingTimeInterval(-window)
        let recent = rest.filter { $0.date >= since && $0.date <= now }
        guard !recent.isEmpty else { return nil }

        let forced = recent.filter { $0.kind == .forcedSleep }.count
        let sleeps = recent.filter { $0.kind == .systemSleep || $0.kind == .forcedSleep }.count
        let wakes = recent.filter { $0.kind == .wake }.count

        // Nothing worth a line if the Mac neither slept nor woke.
        guard sleeps > 0 || wakes > 0 else { return nil }

        var parts: [String] = []
        if let lastSleep = recent.first(where: {
            $0.kind == .systemSleep || $0.kind == .forcedSleep
        }) {
            parts.append("Last slept \(ScheduleEngine.timeLabel(lastSleep.date))")
        }
        if wakes > 0 { parts.append("woken \(countLabel(wakes, "time", "times"))") }
        if forced > 0 {
            parts.append("Decaffeinate stepped in \(countLabel(forced, "time", "times"))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func countLabel(_ n: Int, _ singular: String, _ plural: String) -> String {
        n == 1 ? "once" : "\(n) \(plural)"
    }
}
