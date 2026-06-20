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

    /// Whether this assertion is one of the ones that prevents the *machine*
    /// from sleeping (as opposed to merely keeping the screen on).
    var blocksSystemSleep: Bool { kind == .systemSleep }

    var displayName: String {
        if let bundleIdentifier, let app = localizedAppName(forBundleID: bundleIdentifier) {
            return app
        }
        return processName
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
