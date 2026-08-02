import Foundation

/// Parses the `SleepDisabled` line from `pmset -g` output — the global,
/// system-wide flag `sudo pmset disablesleep 1` sets. Decaffeinate never sets
/// this itself (see `docs/ARCHITECTURE.md`'s negative knowledge on
/// `disablesleep` — root-only, out of scope in Phase A); this is read-only
/// observability so a stray `sudo pmset disablesleep` from elsewhere doesn't
/// go unexplained.
///
/// A pure parser, separate from the process-spawning wrapper below, so it's
/// unit-testable against fixture strings without a live `pmset`.
enum SleepDisabledParser {
    /// `true`/`false` if the `SleepDisabled` line is present and its value is
    /// parseable, else nil (line absent, or a shape `pmset` never actually
    /// emits) — nil means "don't know," never a guess.
    static func parse(pmsetOutput: String) -> Bool? {
        for rawLine in pmsetOutput.split(separator: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("SleepDisabled") else { continue }
            let rest = trimmed.dropFirst("SleepDisabled".count)
                .trimmingCharacters(in: .whitespaces)
            switch rest.lowercased() {
            case "1", "yes", "true": return true
            case "0", "no", "false": return false
            default: return nil
            }
        }
        return nil
    }
}

/// Reads the live global `SleepDisabled` flag. `Sendable` and not
/// `@MainActor` so it can run off the main actor (a subprocess spawn) —
/// mirrors `WakeReasonReading`. Sampled on a cadence by `AppState`
/// (`refreshClamshellReadiness()`), never the 1 Hz tick.
protocol SleepDisabledReading: Sendable {
    /// Best-effort — nil on any failure (never throws).
    func isSleepDisabled() -> Bool?
}

/// Live reader: `pmset -g`, parsed. Reuses the same subprocess-invocation
/// shape as `SleepController`/`LiveWakeReasonReader` (no root — `pmset -g` is
/// a plain read, not a privileged write like `disablesleep`).
struct LiveSleepDisabledReader: SleepDisabledReading {
    func isSleepDisabled() -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return SleepDisabledParser.parse(pmsetOutput: text)
    }
}
