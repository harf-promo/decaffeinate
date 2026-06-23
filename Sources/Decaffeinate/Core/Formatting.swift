import Foundation

extension Array where Element: Hashable {
    /// Order-preserving de-duplication.
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum Format {
    /// `m:ss` / `mm:ss` countdown, e.g. `9:05`. Negative clamps to `0:00`.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Compact "how long ago", e.g. `just now`, `3m ago`, `2h ago`, `5d ago`.
    static func relative(since date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<10: return "just now"
        case ..<60: return "\(Int(elapsed))s ago"
        case ..<3600: return "\(Int(elapsed / 60))m ago"
        case ..<86_400: return "\(Int(elapsed / 3600))h ago"
        case ..<604_800: return "\(Int(elapsed / 86_400))d ago"
        default: return "\(Int(elapsed / 604_800))wk ago"
        }
    }

    /// "for 12m", "for 3h 5m" — how long an assertion has been held.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}
