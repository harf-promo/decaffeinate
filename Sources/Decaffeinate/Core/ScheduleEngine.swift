import Foundation

/// Pure schedule logic: decides whether a moment falls inside the user's
/// "active hours" (when Decaffeinate should *not* force sleep) and formats the
/// human labels for it. Clock + calendar are injected so it is fully testable.
enum ScheduleEngine {

    /// True when `date`'s hour-of-day is within the half-open window
    /// `[start, end)`. Supports overnight windows (e.g. 22 → 6) by wrapping past
    /// midnight. A degenerate `start == end` window matches nothing.
    static func isWithinActiveHours(
        _ date: Date, start: Int, end: Int, calendar: Calendar = .current
    ) -> Bool {
        guard start != end else { return false }
        let hour = calendar.component(.hour, from: date)
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }

    /// The force-sleep hold reason contributed by the active-hours schedule, or
    /// `nil` when the schedule is off or we're outside the window.
    static func activeHoursHoldReason(
        now: Date, settings: DecaffeinateSettings, calendar: Calendar = .current
    ) -> String? {
        guard settings.scheduleEnabled,
            isWithinActiveHours(
                now, start: settings.activeHoursStart, end: settings.activeHoursEnd,
                calendar: calendar)
        else { return nil }
        return
            "Within your active hours (\(hourLabel(settings.activeHoursStart))–\(hourLabel(settings.activeHoursEnd)))"
    }

    /// "9 AM", "5 PM", "12 AM" — a compact label for an hour-of-day 0...23.
    static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        let period = h < 12 ? "AM" : "PM"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(period)"
    }

    /// A localized wall-clock label for a moment, e.g. "3:30 PM".
    static func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
