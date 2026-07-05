import Foundation

/// The single, authoritative answer to "will my Mac sleep?", from the app's own
/// point of view — folding in whether auto-sleep is on and whether the safety
/// engine will actually override the holds. The header, the list banner, every
/// row verdict, and the menu-bar icon all derive from this ONE value, so they can
/// never contradict each other. Pure value type (like `HoldLifetime`), so the
/// decision-to-copy mapping is fully unit-testable without an `AppState`.
///
/// The old design had three independent producers (`awakeSummary`, `sleepVerdict`,
/// `HoldLifetime.rowVerdict`), none of which consulted `decaffeinateEnabled` or the
/// engine — so the menu could show "held indefinitely" (amber) at the exact moment
/// the app was about to override that hold and sleep. `SleepOutlook` fixes that by
/// speaking from control: the common case is "Your Mac will sleep ~10 min after you
/// step away", and only genuinely-stuck states are amber.
enum SleepOutlook: Equatable, Sendable {
    /// Auto-sleep on, nothing holding — free.
    case freeToSleep(idleMinutes: Int, batteryNote: Bool)
    /// Auto-sleep on, holds present, user active, the engine WILL override them
    /// after idle. The most common state — and the one the old UI mis-framed.
    case willSleepAfterIdle(idleMinutes: Int, batteryNote: Bool, holdCount: Int)
    /// Counting down to a forced sleep (stepped away / watched task finished).
    case sleepingSoon(seconds: TimeInterval, overriding: Int)
    /// A safety rail genuinely holds off force-sleep (call/media/backup/update/
    /// allowed-app/active-hours). The only auto-sleep-ON state that goes amber.
    case heldByBlocker(SleepBlocker)
    /// The master switch is off — the Mac won't sleep on its own.
    case autoSleepOff(holdCount: Int)
    /// The user is deliberately keeping the Mac awake (positive, in control).
    case keepingAwake(KeepAwakeReason)
    /// A user keep-awake window was dropped by a safety rail — the Mac WILL sleep.
    case keepAwakePaused(reason: String)
    /// An immediate guard (overheating / critical battery) is sleeping the Mac now.
    case protectiveSleep(reason: String)
}

/// Green / teal / amber — drives the mug, banner, and row colours (never the
/// header text, which stays calm ink).
enum SleepTone: Equatable, Sendable { case positive, calm, warning }

/// The shape the banner and every row verdict share, so they are literally the
/// same type and cannot drift.
struct SleepVerdict: Equatable, Sendable {
    let glyph: String
    let text: String
    let tone: SleepTone
}

/// A specific reason the idle engine is holding off, classified from the
/// `SafetyDecision` reason strings so state-4 copy is specific ("You're on a
/// call") instead of a blanket "held indefinitely".
enum SleepBlocker: Equatable, Sendable {
    case call
    case media
    case timeMachine
    case systemUpdate
    case allowedApps(String)
    case activeHours(String)
    case batteryFloor
    case thermal
    case lowBattery
    case other(String)

    /// Classify a raw `SafetyRails`/`ScheduleEngine` reason string. Every string
    /// those two can emit maps to a non-`.other` case (enforced by a sync test).
    static func classify(_ reason: String) -> SleepBlocker {
        if reason.hasPrefix("Allowed app keeping awake:") {
            let list = String(reason.dropFirst("Allowed app keeping awake:".count))
                .trimmingCharacters(in: .whitespaces)
            return .allowedApps(list)
        }
        if reason.hasPrefix("Within your active hours") {
            if let open = reason.firstIndex(of: "("), let close = reason.lastIndex(of: ")"),
                open < close
            {
                return .activeHours(String(reason[reason.index(after: open)..<close]))
            }
            return .activeHours("")
        }
        switch reason {
        case "Microphone is in use (likely a call)": return .call
        case "Media or a call appears active": return .media
        case "Time Machine backup in progress": return .timeMachine
        case "macOS update or install in progress": return .systemUpdate
        case "Thermal pressure is high", "Mac is overheating (backpack guard)": return .thermal
        default: break
        }
        if reason.hasPrefix("Battery below") { return .batteryFloor }
        if reason.hasPrefix("Battery critically low") { return .lowBattery }
        return .other(reason)
    }

    /// The hero headline when this blocker holds off sleep (state 4).
    var heroHeadline: String {
        switch self {
        case .activeHours: return "Auto-sleep paused"
        default: return "Won\u{2019}t sleep yet"
        }
    }

    /// The one-line "why", below the hero.
    var subline: String {
        switch self {
        case .call:
            return "You\u{2019}re on a call \u{2014} it\u{2019}ll sleep when your mic frees up"
        case .media: return "Media is playing \u{2014} it\u{2019}ll sleep once that stops"
        case .timeMachine: return "Finishing a Time Machine backup first"
        case .systemUpdate: return "Installing a macOS update first"
        case .allowedApps(let x): return "You allowed \(x) to keep it awake"
        case .activeHours(let x):
            let window = x.isEmpty ? "" : " (\(x))"
            return
                "Standing down within your active hours\(window) \u{2014} macOS\u{2019}s own sleep still applies"
        case .batteryFloor: return "Low battery \u{2014} macOS handles sleep from here"
        case .thermal: return "Cooling down \u{2014} keep-awake dropped"
        case .lowBattery: return "Battery critically low"
        case .other(let s): return s
        }
    }

    /// A short reason for the compact banner / row ("on a call").
    var rowReason: String {
        switch self {
        case .call: return "on a call"
        case .media: return "media playing"
        case .timeMachine: return "backup running"
        case .systemUpdate: return "update installing"
        case .allowedApps: return "you allowed it"
        case .activeHours: return "your active hours"
        case .batteryFloor: return "low battery"
        case .thermal: return "cooling down"
        case .lowBattery: return "battery critically low"
        case .other(let s): return s
        }
    }
}

/// Why the user is deliberately keeping the Mac awake.
enum KeepAwakeReason: Equatable, Sendable {
    case manual(displayStaysOn: Bool)
    case quietWindow(until: Date)
    case trigger(String)
}

/// The inputs `classify` needs — every field is already live at the end of
/// `AppState.tick()`, so no `AppState` reference is required.
struct SleepOutlookInputs {
    var decaffeinateEnabled: Bool
    var caffeinateActive: Bool  // settings.caffeinateEnabled && caffeine.isActive
    var caffeinateKeepsDisplayAwake: Bool
    var decision: SafetyDecision
    var isQuietWindowActive: Bool
    var quietWindowHoldingAwake: Bool
    var quietUntil: Date?
    var triggerReason: String?  // non-nil only while a trigger is actually holding
    var idleMinutes: Int
    var batteryNote: Bool
    var idleSeconds: TimeInterval
    var agentFinished: Bool
    var remainingSeconds: TimeInterval?
    var activeHoldingCount: Int
}

extension SleepOutlook {

    /// The one place the "will it sleep?" decision maps to a state. Precedence
    /// mirrors the old `updateDerivedState` ordering, corrected so a hold the
    /// engine will override reads as state 2, not an amber warning.
    static func classify(_ i: SleepOutlookInputs) -> SleepOutlook {
        // An immediate guard is acting now (reached here only inside its cooldown).
        if i.decision.mustSleepNow {
            return .protectiveSleep(
                reason: i.decision.immediateSleepReasons.first ?? "Safety guard")
        }
        // Deliberate keep-awake (gate on the setting, not the raw assertion, so
        // strict-takeover — which also makes caffeine active — flows to "will sleep").
        if i.caffeinateActive {
            return .keepingAwake(.manual(displayStaysOn: i.caffeinateKeepsDisplayAwake))
        }
        if i.isQuietWindowActive {
            if i.quietWindowHoldingAwake, let until = i.quietUntil {
                return .keepingAwake(.quietWindow(until: until))
            }
            return .keepAwakePaused(
                reason: i.decision.dropKeepAwakeReasons.first ?? "Paused by a safety rail")
        }
        if let reason = i.triggerReason {
            return .keepingAwake(.trigger(reason))
        }
        // Master switch off.
        if !i.decaffeinateEnabled {
            return .autoSleepOff(holdCount: i.activeHoldingCount)
        }
        // A rail genuinely holds off force-sleep — the only amber auto-sleep-ON state.
        if !i.decision.canForceSleep {
            return .heldByBlocker(.classify(i.decision.holdForceSleepReasons.first ?? ""))
        }
        // Counting down (stepped away, or a watched agent just finished).
        if let rem = i.remainingSeconds, i.idleSeconds >= 30 || i.agentFinished {
            return .sleepingSoon(seconds: max(0, rem), overriding: i.activeHoldingCount)
        }
        // Holds present, user active — the engine will override them after idle.
        if i.activeHoldingCount > 0 {
            return .willSleepAfterIdle(
                idleMinutes: i.idleMinutes, batteryNote: i.batteryNote,
                holdCount: i.activeHoldingCount)
        }
        return .freeToSleep(idleMinutes: i.idleMinutes, batteryNote: i.batteryNote)
    }

    // MARK: Header projection

    private static func idlePhrase(_ minutes: Int, batteryNote: Bool) -> String {
        "~\(minutes) min after you step away" + (batteryNote ? " (on battery)" : "")
    }

    private static func holdsPhrase(_ count: Int) -> String {
        count == 1
            ? "1 app is holding it awake now \u{2014} auto-sleep will override it"
            : "\(count) apps holding now \u{2014} auto-sleep will override them"
    }

    var headline: String {
        switch self {
        case .freeToSleep: return "Free to sleep"
        case .willSleepAfterIdle(let m, let note, _):
            return "Your Mac will sleep \(Self.idlePhrase(m, batteryNote: note))"
        case .sleepingSoon(let s, _): return "Sleeping in \(Format.countdown(s))"
        case .heldByBlocker(let b): return b.heroHeadline
        case .autoSleepOff: return "Auto-sleep is off"
        case .keepingAwake(.manual): return "Keeping your Mac awake"
        case .keepingAwake(.quietWindow(let until)):
            return "Awake until \(ScheduleEngine.timeLabel(until))"
        case .keepingAwake(.trigger): return "Keeping your Mac awake"
        case .keepAwakePaused: return "Quiet window paused"
        case .protectiveSleep: return "Sleeping now to protect your Mac"
        }
    }

    var subline: String {
        switch self {
        case .freeToSleep(let m, let note):
            return "Sleeps \(Self.idlePhrase(m, batteryNote: note))"
        case .willSleepAfterIdle(_, _, let count): return Self.holdsPhrase(count)
        case .sleepingSoon(_, let overriding):
            return overriding == 0
                ? "You stepped away \u{2014} winding down"
                : "Overriding \(overriding) sleep block\(overriding == 1 ? "" : "s") \u{2014} sleeping anyway"
        case .heldByBlocker(let b): return b.subline
        case .autoSleepOff:
            return
                "Your Mac won\u{2019}t sleep on its own \u{2014} overheating & critical-battery guards still apply"
        case .keepingAwake(.manual(let displayStaysOn)):
            return displayStaysOn ? "Display stays on too" : "Display can still sleep"
        case .keepingAwake(.quietWindow): return "Quiet window \u{2014} auto-sleep paused"
        case .keepingAwake(.trigger(let r)): return "Trigger \u{2014} \(r)"
        case .keepAwakePaused(let reason): return reason
        case .protectiveSleep(let reason): return reason
        }
    }

    /// Drives the menu-bar icon (reuses the four existing states with clearer
    /// semantics: `.blocked` = genuinely won't sleep; `.free` = will sleep).
    var mug: MugState {
        switch self {
        case .freeToSleep, .willSleepAfterIdle, .keepAwakePaused: return .free
        case .sleepingSoon, .protectiveSleep: return .counting
        case .heldByBlocker: return .blocked
        case .autoSleepOff(let holdCount): return holdCount > 0 ? .blocked : .free
        case .keepingAwake: return .caffeinated
        }
    }

    var severity: SleepTone {
        switch self {
        case .freeToSleep, .willSleepAfterIdle, .keepAwakePaused: return .calm
        case .sleepingSoon, .protectiveSleep, .keepingAwake: return .positive
        case .heldByBlocker: return .warning
        case .autoSleepOff(let holdCount): return holdCount > 0 ? .warning : .calm
        }
    }

    /// Feeds `secondsUntilForcedSleep` — non-nil only while counting down.
    var countdownSeconds: TimeInterval? {
        if case .sleepingSoon(let s, _) = self { return s }
        return nil
    }

    /// True only when auto-sleep is off — drives a one-tap "Turn on auto-sleep".
    var offersEnableAutoSleep: Bool {
        if case .autoSleepOff = self { return true }
        return false
    }

    // MARK: Banner & row projections (share `SleepVerdict`, derived from `self`)

    /// The list banner — replaces `AppState.sleepVerdict`. `anyIndefinite` is
    /// computed once from the grouped holds so the banner reflects reality, not
    /// the old "any indefinite ⇒ amber" bug.
    func banner(hasHolds: Bool, anyIndefinite: Bool) -> SleepVerdict? {
        guard hasHolds else { return nil }
        switch self {
        case .willSleepAfterIdle(let m, let note, _):
            return SleepVerdict(
                glyph: "checkmark",
                text:
                    "Your Mac will sleep \(Self.idlePhrase(m, batteryNote: note)) \u{2014} these holds don\u{2019}t stop it",
                tone: .calm)
        case .sleepingSoon(let s, _):
            return SleepVerdict(
                glyph: "moon.zzz.fill",
                text: "Sleeping in \(Format.countdown(s)) \u{2014} overriding these holds",
                tone: .positive)
        case .heldByBlocker(let b):
            return anyIndefinite
                ? SleepVerdict(
                    glyph: "exclamationmark.triangle",
                    text: "Won\u{2019}t sleep on its own \u{2014} \(b.rowReason)", tone: .warning)
                : SleepVerdict(
                    glyph: "checkmark", text: "Your Mac will sleep when these finish", tone: .calm)
        case .autoSleepOff:
            return anyIndefinite
                ? SleepVerdict(
                    glyph: "exclamationmark.triangle",
                    text: "Auto-sleep is off \u{2014} these holds will keep your Mac awake",
                    tone: .warning)
                : SleepVerdict(
                    glyph: "checkmark",
                    text: "These holds end on their own \u{2014} your Mac will sleep after",
                    tone: .calm)
        case .keepingAwake:
            return SleepVerdict(
                glyph: "bolt.fill",
                text: "You\u{2019}re keeping your Mac awake \u{2014} these are allowed to hold on",
                tone: .positive)
        case .keepAwakePaused:
            return SleepVerdict(
                glyph: "checkmark", text: "Your Mac will sleep \u{2014} quiet window paused",
                tone: .calm)
        case .freeToSleep, .protectiveSleep:
            return nil
        }
    }

    /// A per-hold row verdict — replaces `HoldLifetime.rowVerdict`. A bounded hold
    /// always ends itself (teal); an indefinite hold's verdict depends on whether
    /// the app will override it, so the row can never contradict the hero line.
    func rowVerdict(for lifetime: HoldLifetime) -> SleepVerdict {
        switch lifetime {
        case .untilProcess(let name):
            return SleepVerdict(
                glyph: "checkmark", text: "Will sleep when \(name) finishes", tone: .calm)
        case .untilWatchedFinishes:
            return SleepVerdict(
                glyph: "checkmark", text: "Will sleep when the watched task finishes", tone: .calm)
        case .timed(let reArms):
            return SleepVerdict(
                glyph: "checkmark",
                text: reArms
                    ? "Will sleep shortly after your agent finishes" : "Auto-releases on a timer",
                tone: .calm)
        case .indefinite:
            switch self {
            case .heldByBlocker(let b):
                return SleepVerdict(
                    glyph: "exclamationmark.triangle",
                    text: "Won\u{2019}t sleep yet \u{2014} \(b.rowReason)",
                    tone: .warning)
            case .autoSleepOff:
                return SleepVerdict(
                    glyph: "exclamationmark.triangle",
                    text: "Won\u{2019}t sleep \u{2014} auto-sleep is off",
                    tone: .warning)
            case .keepingAwake:
                return SleepVerdict(
                    glyph: "bolt.fill", text: "Held \u{2014} you\u{2019}re keeping the Mac awake",
                    tone: .positive)
            case .keepAwakePaused:
                return SleepVerdict(
                    glyph: "checkmark", text: "Will sleep \u{2014} quiet window paused", tone: .calm
                )
            default:
                // States 1/2/3/protectiveSleep — the engine overrides after idle.
                return SleepVerdict(
                    glyph: "checkmark", text: "Will sleep after you step away", tone: .calm)
            }
        }
    }
}
