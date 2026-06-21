import Foundation

/// What an app is *actually doing* that keeps the Mac awake. Decaffeinate's
/// "intelligence": turn a raw power assertion into a plain-English reason +
/// category, using the public IOKit detail (`ResourcesUsed`, the assertion
/// name/type, `HumanReadableReason`/`Details`). No private APIs.
enum AssertionCategory: String, Sendable, Hashable {
    case microphone  // audio-in resource → a call / recording
    case audioPlayback  // audio-out resource → playing sound
    case mediaPlayback  // video / WebKit media
    case networkTransfer  // download / active network client
    case handoff  // Continuity / Handoff
    case softwareUpdate
    case backup  // Time Machine
    case displayOn  // the screen is on
    case location
    case push  // push-notification delivery
    case keepAwakeTool  // caffeinate & friends
    case systemBackground  // runningboardd-mediated background task
    case unknown

    var label: String {
        switch self {
        case .microphone: return "Microphone in use"
        case .audioPlayback: return "Playing audio"
        case .mediaPlayback: return "Playing media"
        case .networkTransfer: return "Transferring data"
        case .handoff: return "Handoff / Continuity"
        case .softwareUpdate: return "Installing an update"
        case .backup: return "Backing up (Time Machine)"
        case .displayOn: return "Keeping the display on"
        case .location: return "Using your location"
        case .push: return "Delivering notifications"
        case .keepAwakeTool: return "Keeping awake on purpose"
        case .systemBackground: return "Background activity"
        case .unknown: return "Holding the Mac awake"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: return "mic.fill"
        case .audioPlayback: return "speaker.wave.2.fill"
        case .mediaPlayback: return "play.rectangle.fill"
        case .networkTransfer: return "arrow.down.circle.fill"
        case .handoff: return "rectangle.2.swap"
        case .softwareUpdate: return "arrow.down.app.fill"
        case .backup: return "externaldrive.fill.badge.timemachine"
        case .displayOn: return "display"
        case .location: return "location.fill"
        case .push: return "bell.badge.fill"
        case .keepAwakeTool: return "bolt.fill"
        case .systemBackground: return "gearshape.fill"
        case .unknown: return "sun.max.fill"
        }
    }
}

/// The classified "why" for one assertion.
struct AssertionReason: Sendable, Hashable {
    let category: AssertionCategory
    /// Plain-English explanation to show the user.
    let explanation: String
    /// Friendly resource names, e.g. ["Microphone"] / ["Speaker"].
    let resourceLabels: [String]
    /// Seconds until it auto-releases, if it's a timed hold.
    let autoReleaseSeconds: Int?
}

enum ReasonEngine {

    static func classify(_ assertion: PowerAssertion) -> AssertionReason {
        let category = categorize(assertion)
        return AssertionReason(
            category: category,
            explanation: explanation(for: category, assertion: assertion),
            resourceLabels: resourceLabels(assertion.resources),
            autoReleaseSeconds: assertion.autoReleaseSeconds
        )
    }

    /// Pure classification from the assertion's fields (testable).
    static func categorize(_ a: PowerAssertion) -> AssertionCategory {
        let resources = a.resources.map { $0.lowercased() }
        if resources.contains("audio-in") { return .microphone }
        if resources.contains("audio-out") { return .audioPlayback }

        let haystack = (a.name + " " + (a.details ?? "")).lowercased()
        let proc = a.processName.lowercased()

        if proc == "caffeinate" || haystack.contains("caffeinate") { return .keepAwakeTool }
        if haystack.contains("media playback") || haystack.contains("htmlmediaelement")
            || haystack.contains("avfoundation") || haystack.contains("video")
            || haystack.contains("now playing")
        {
            return .mediaPlayback
        }
        if haystack.contains("handoff") || haystack.contains("continuity") { return .handoff }
        if a.assertionType == AssertionType.networkClientActive
            || haystack.contains("download") || haystack.contains("networkclient")
        {
            return .networkTransfer
        }
        // Only the verified daemon or the specific "Time Machine" phrase — a bare
        // "backup" keyword would mislabel every cloud-backup client as Time Machine.
        if proc == "backupd" || haystack.contains("time machine") {
            return .backup
        }
        if proc == "softwareupdated" || proc == "installd"
            || haystack.contains("software update") || haystack.contains("install macos")
        {
            return .softwareUpdate
        }
        if haystack.contains("display is on") || haystack.contains("prevent display") {
            return .displayOn
        }
        if haystack.contains("location") || haystack.contains("corelocation") { return .location }
        if haystack.contains("push") || haystack.contains("apns") { return .push }
        if a.viaRunningboard { return .systemBackground }
        return .unknown
    }

    /// Prefer a clean category label; fall back to macOS' own reason only when
    /// we genuinely don't recognize the hold.
    private static func explanation(for category: AssertionCategory, assertion a: PowerAssertion)
        -> String
    {
        if category != .unknown { return category.label }
        // The fallback text is fully app-controlled, so sanitize it before it
        // reaches the UI, the history log, a notification, or `--scan`'s stdout.
        if let reason = a.humanReadableReason, !reason.isEmpty {
            return sanitize(sentenceCased(reason))
        }
        if let details = a.details, !details.isEmpty { return sanitize(details) }
        return category.label
    }

    /// Strip control characters (NUL, ESC/ANSI terminal-injection sequences, …),
    /// collapse whitespace, and clamp the length of app-supplied free text before
    /// it's displayed or printed. Keeps the feature (showing macOS' own reason)
    /// while removing the untrusted-text-to-terminal / oversharing vector.
    static func sanitize(_ string: String, maxLength: Int = 120) -> String {
        let stripped = String(
            string.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        let collapsed = stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }

    /// The known resource-class tokens (everything else is a device id/name).
    private static let resourceClassTokens: Set<String> = [
        "audio-in", "audio-out", "network", "gpu", "disk", "usb",
    ]

    static func resourceLabels(_ resources: [String]) -> [String] {
        var labels: [String] = []
        for token in resources.map({ $0.lowercased() }) {
            switch token {
            case "audio-in": labels.append("Microphone")
            case "audio-out": labels.append("Speaker")
            case "network": labels.append("Network")
            case "gpu": labels.append("GPU")
            case "disk": labels.append("Disk")
            case "usb": labels.append("USB")
            default: break  // device UUIDs / names — surfaced via deviceTokens()
            }
        }
        return labels.removingDuplicates()
    }

    /// The device id/name token(s) in a resources array — the things
    /// `resourceLabels` skips (e.g. "BuiltInSpeakerDevice", a device UUID). Used
    /// to name *which* audio device is keeping the Mac awake.
    static func deviceTokens(_ resources: [String]) -> [String] {
        resources
            .filter { !resourceClassTokens.contains($0.lowercased()) }
            .removingDuplicates()
    }

    /// "THE CAFFEINATE TOOL IS PREVENTING SLEEP." → "The caffeinate tool is preventing sleep."
    private static func sentenceCased(_ string: String) -> String {
        let lower = string.lowercased()
        guard let first = lower.first else { return string }
        return first.uppercased() + lower.dropFirst()
    }
}
