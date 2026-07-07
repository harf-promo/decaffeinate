import Foundation

/// Parses the *reason a Mac last woke* from `pmset -g log` output — the missing
/// half of the truth Decaffeinate tells. The app explains holds that prevent
/// sleep in exhaustive detail; this answers the mirror question, "what woke my
/// Mac while I was away?" — all from public, user-space `pmset` data (no root).
///
/// `pmset -g log` prints one wake per line, e.g.
///   `2026-07-06 23:41:02 -0500 Wake   Wake from Standby [CDNVA] : due to EC.LidOpen/HID Activity`
/// The parser is pure (string in → friendly reason out), so it's unit-testable
/// against captured fixtures without a live `pmset`.
enum WakeReasonParser {

    /// The friendly reason for the most recent wake in `log`, or nil if none is
    /// found. Scans bottom-up (the log is chronological) for a `Wake` domain
    /// line carrying a "due to …" cause.
    static func latestWakeReason(from log: String) -> String? {
        for line in log.split(separator: "\n").reversed() {
            let s = String(line)
            // The domain column reads "Wake" (or "DarkWake"); require an actual
            // wake cause so we skip sleep/assertion lines that mention "Wake".
            guard s.contains(" Wake") || s.hasPrefix("Wake"), let cause = dueToCause(s) else {
                continue
            }
            return friendly(cause)
        }
        return nil
    }

    /// Extract the raw cause after "due to " up to the trailing "Using …" note.
    static func dueToCause(_ line: String) -> String? {
        guard let range = line.range(of: "due to ") else { return nil }
        var cause = String(line[range.upperBound...])
        // Trim the trailing power annotation pmset appends ("Using AC", "Using Batt").
        for marker in [" Using ", " Battery", " (Charge"] {
            if let r = cause.range(of: marker) { cause = String(cause[..<r.lowerBound]) }
        }
        return cause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : cause.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Map a raw pmset cause to a plain-English reason.
    static func friendly(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("lidopen") || lower.contains("lid open") { return "You opened the lid" }
        if lower.contains("hid activity") || lower.contains("useractivity")
            || lower.contains("hid ")
        {
            return "Keyboard or trackpad"
        }
        if lower.contains("powerbutton") || lower.contains("power button") { return "Power button" }
        if lower.contains("rtc") || lower.contains("alarm") || lower.contains("maintenance") {
            return "Scheduled wake"
        }
        if lower.contains("wow") || lower.contains("magic packet") || lower.contains("network")
            || lower.contains("ethernet") || lower.contains("wifi")
        {
            return "Network (Wake on LAN)"
        }
        if lower.contains("bluetooth") { return "A Bluetooth device" }
        if lower.contains("usb") || lower.contains("thunderbolt") { return "A connected device" }
        if lower.contains("clamshell") { return "The lid" }
        // Fall back to the first token group, cleaned up.
        let head =
            raw.split(whereSeparator: { $0 == "/" || $0 == "." }).first.map(String.init) ?? raw
        return ReasonEngine.sanitize(head, maxLength: 60)
    }
}

/// Reads the live wake reason. The live implementation shells out to
/// `pmset -g log`; injected so AppState can be tested without a subprocess.
/// Sendable + non-isolated so it can run off the main actor (the read is slow).
protocol WakeReasonReading: Sendable {
    /// Best-effort — returns nil on any failure (never throws).
    func latestWakeReason() -> String?
}

/// Live reader: `pmset -g log`, parsed. Bounded so a huge log can't hang the app.
struct LiveWakeReasonReader: WakeReasonReading {
    func latestWakeReason() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read all available output, then wait — pmset log is bounded in practice.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return WakeReasonParser.latestWakeReason(from: text)
    }
}
