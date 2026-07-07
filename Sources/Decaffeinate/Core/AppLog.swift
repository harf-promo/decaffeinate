import Foundation
import os

/// Lightweight `os.Logger` wrappers for the decisions worth being able to trace
/// after the fact — visible in Console.app / `log show --predicate
/// 'subsystem == "com.harfpromo.Decaffeinate"'` and folded into the diagnostics
/// export. Deliberately sparse: the tick runs every second, so only genuine
/// state changes (a forced sleep, a dropped keep-awake hold) are logged, never
/// per-tick noise. No identifying free text is logged (reasons are the app's own
/// classified strings, never raw assertion names).
enum AppLog {
    private static let subsystem = "com.harfpromo.Decaffeinate"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
