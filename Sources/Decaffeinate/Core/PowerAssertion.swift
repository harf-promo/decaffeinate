import Foundation

/// The effect a power assertion has on the machine's ability to sleep.
///
/// macOS lets any process register a "power assertion" that silently overrides
/// the idle timer. We classify each one by how much it actually holds the
/// machine awake so Decaffeinate can reason about whether the Mac *should* sleep.
enum AssertionKind: String, Sendable, Codable {
    /// Blocks the whole machine from idle-sleeping (the ones that drain batteries
    /// overnight). e.g. `PreventUserIdleSystemSleep`, `PreventSystemSleep`.
    case systemSleep
    /// Only keeps the *display* awake (video players, presentations, calls).
    /// The Mac can still sleep its CPU; usually a sign of active media.
    case displaySleep
    /// Everything else (network, disk, push-service assertions, etc.).
    case other

    var label: String {
        switch self {
        case .systemSleep: return "Keeps Mac awake"
        case .displaySleep: return "Keeps screen on"
        case .other: return "Background hold"
        }
    }
}

/// The real application behind an assertion that was routed through a shared
/// daemon (e.g. a browser tab's audio surfacing under `coreaudiod`).
struct AssertionOwner: Hashable, Sendable {
    let name: String
    let bundleIdentifier: String?
}

/// A single live power assertion attributed to the process that owns it.
///
/// This is the unit of "truth" Decaffeinate reports: exactly who is holding the
/// Mac awake, with what, and for how long.
struct PowerAssertion: Identifiable, Hashable, Sendable {
    let id: String
    let pid: pid_t
    let processName: String
    let bundleIdentifier: String?
    /// The raw IOKit assertion type string, e.g. `"PreventUserIdleSystemSleep"`.
    let assertionType: String
    /// The human-readable name the process gave the assertion.
    let name: String
    let kind: AssertionKind
    /// When the assertion was first created, if IOKit reported it.
    let createdAt: Date?
    /// The real app behind a hold routed through a shared daemon, if resolved.
    let realOwner: AssertionOwner?

    // "Why" detail straight from IOKit (all optional / empty when not reported).
    /// macOS' localized reason, e.g. "THE CAFFEINATE TOOL IS PREVENTING SLEEP".
    let humanReadableReason: String?
    /// Caller-supplied context, e.g. "caffeinate asserting for 300 secs".
    let details: String?
    /// Resource tokens, e.g. `["audio-in"]` (mic) / `["audio-out"]` (speaker).
    let resources: [String]
    /// Seconds until the hold auto-releases (timeout with release action), if any.
    let autoReleaseSeconds: Int?
    /// The resolved assertion type (may differ from `assertionType`).
    let trueType: String?
    /// Path to the creating process's bundle, if reported.
    let bundlePath: String?
    /// The app this hold was created on behalf of, if any.
    let onBehalfOfPID: pid_t?
    /// Whether `runningboardd` is mediating this hold for a background app.
    let viaRunningboard: Bool

    init(
        id: String,
        pid: pid_t,
        processName: String,
        bundleIdentifier: String?,
        assertionType: String,
        name: String,
        kind: AssertionKind,
        createdAt: Date?,
        realOwner: AssertionOwner? = nil,
        humanReadableReason: String? = nil,
        details: String? = nil,
        resources: [String] = [],
        autoReleaseSeconds: Int? = nil,
        trueType: String? = nil,
        bundlePath: String? = nil,
        onBehalfOfPID: pid_t? = nil,
        viaRunningboard: Bool = false
    ) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.bundleIdentifier = bundleIdentifier
        self.assertionType = assertionType
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.realOwner = realOwner
        self.humanReadableReason = humanReadableReason
        self.details = details
        self.resources = resources
        self.autoReleaseSeconds = autoReleaseSeconds
        self.trueType = trueType
        self.bundlePath = bundlePath
        self.onBehalfOfPID = onBehalfOfPID
        self.viaRunningboard = viaRunningboard
    }

    /// The classified "why" — computed lazily from the captured fields.
    var reason: AssertionReason { ReasonEngine.classify(self) }

    /// Whether this assertion is one of the ones that prevents the *machine*
    /// from sleeping (as opposed to merely keeping the screen on).
    var blocksSystemSleep: Bool { kind == .systemSleep }

    /// The owning process's own friendly name (no attribution applied).
    var ownerName: String {
        if let bundleIdentifier, let app = localizedAppName(forBundleID: bundleIdentifier) {
            return app
        }
        return processName
    }

    /// The best name to show the user: the attributed real owner when known,
    /// otherwise the owning process.
    var displayName: String {
        realOwner?.name ?? ownerName
    }

    /// "via coreaudiod" when this hold was attributed to a different real owner.
    var attribution: String? {
        guard realOwner != nil else { return nil }
        return "via \(ownerName)"
    }
}

/// IOKit assertion-type string constants. Kept here so the rest of the codebase
/// reasons about ``AssertionKind`` rather than raw strings.
enum AssertionType {
    static let preventUserIdleSystemSleep = "PreventUserIdleSystemSleep"
    static let preventSystemSleep = "PreventSystemSleep"
    static let preventUserIdleDisplaySleep = "PreventUserIdleDisplaySleep"
    static let noIdleSleep = "NoIdleSleepAssertion"
    static let preventDiskIdle = "PreventDiskIdle"
    static let networkClientActive = "NetworkClientActive"

    static func classify(_ type: String) -> AssertionKind {
        switch type {
        case preventUserIdleSystemSleep, preventSystemSleep, noIdleSleep:
            return .systemSleep
        case preventUserIdleDisplaySleep:
            return .displaySleep
        default:
            return .other
        }
    }
}
