import AppIntents
import Foundation

// Modern automation surface: Shortcuts.app / Spotlight / Siri actions that mirror
// what the CLI (`--scan`, `--sleep-now`) and the menu already do. The intents must
// live in the executable target (not a library) for the metadata extractor to find
// them; see Scripts/build-app.sh. The always-reliable fallback is the URL scheme
// (decaffeinate://…) handled in DecaffeinateApp.swift.

// MARK: - Shared helpers

/// A plain-language summary of what's blocking sleep — the pure, testable core of
/// `WhatsKeepingMacAwakeIntent`, factored out so `perform()` stays a thin shell.
struct AwakeSummary: Equatable {
    /// A spoken/dialog sentence (Siri, Spotlight).
    let spoken: String
    /// One line per blocker: "Name — why", for the Shortcuts value result.
    let items: [String]
}

enum AwakeReport {
    static func summarize(_ assertions: [PowerAssertion]) -> AwakeSummary {
        let blockers = assertions.filter(\.blocksSystemSleep)
        guard !blockers.isEmpty else {
            return AwakeSummary(spoken: "Nothing is keeping your Mac awake.", items: [])
        }
        let items = blockers.map { "\($0.displayName) — \($0.reason.explanation)" }
        let names = blockers.map(\.displayName).removingDuplicates()
        let spoken: String
        if names.count == 1 {
            spoken = "\(names[0]) is keeping your Mac awake."
        } else {
            let lead = names.prefix(3).joined(separator: ", ")
            spoken = "\(names.count) things are keeping your Mac awake: \(lead)."
        }
        return AwakeSummary(spoken: spoken, items: items)
    }
}

/// Thrown so a failed Sleep-Now surfaces as a real error in Shortcuts (not a
/// silent success), with a readable message.
enum DecaffeinateIntentError: Error, CustomLocalizedStringResourceConvertible {
    case sleepFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .sleepFailed(let message):
            return "Couldn’t put the Mac to sleep: \(message)"
        }
    }
}

/// Duration presets for `KeepAwakeIntent` — a finite set so Siri/Spotlight can
/// pre-bake phrases like "keep my Mac awake for 30 minutes".
enum KeepAwakePreset: Int, AppEnum {
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case oneTwenty = 120

    var minutes: Int { rawValue }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Duration"
    static let caseDisplayRepresentations: [KeepAwakePreset: DisplayRepresentation] = [
        .fifteen: "15 minutes",
        .thirty: "30 minutes",
        .sixty: "1 hour",
        .oneTwenty: "2 hours",
    ]
}

// MARK: - Intents

/// Force the Mac to sleep now. Self-contained (like `--scan`): runs the same
/// `pmset sleepnow` path with no live engine, so it works even if launched cold.
struct SleepNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sleep Now"
    static let description = IntentDescription(
        "Force your Mac to sleep immediately, overriding whatever is holding it awake.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch SleepController().sleepNow() {
        case .success:
            return .result(dialog: "Putting your Mac to sleep.")
        case .failure(let error):
            throw DecaffeinateIntentError.sleepFailed(error.description)
        }
    }
}

/// Report every process currently blocking system sleep, and why. Self-contained
/// so it answers correctly even when the menu-bar app isn't foregrounded.
struct WhatsKeepingMacAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Keeping My Mac Awake"
    static let description = IntentDescription(
        "List every app or process currently preventing your Mac from sleeping, and why.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        // The intent runs inside the app process — filter our own pid exactly
        // like AppState.tick() does, or an active keep-awake/quiet window makes
        // Siri answer "Decaffeinate is keeping your Mac awake" as a blocker.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let report = AwakeReport.summarize(
            TelemetryEngine().scan().filter { $0.pid != ownPID })
        return .result(value: report.items, dialog: IntentDialog(stringLiteral: report.spoken))
    }
}

/// Keep the Mac awake for a preset duration, then let it sleep again. Routes
/// through the persistent `AppState` so the hold outlives this call (and is
/// persisted, so it survives a background relaunch).
struct KeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription(
        "Keep your Mac awake for a set duration, then let it sleep again.")
    // Guarantee the always-on instance is alive to hold and later release the window.
    static let openAppWhenRun = true

    @Parameter(title: "Duration", default: .thirty)
    var duration: KeepAwakePreset

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppState.shared.stayAwake(forMinutes: duration.minutes)
        return .result(
            dialog: IntentDialog(
                stringLiteral: "Keeping your Mac awake for \(duration.minutes) minutes."))
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Keep my Mac awake for \(\.$duration)")
    }
}

/// End any active keep-awake window immediately.
struct StopKeepingAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Keeping Mac Awake"
    static let description = IntentDescription("End any active keep-awake window right now.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppState.shared.clearQuietWindow()
        return .result(dialog: "Okay — your Mac can sleep normally again.")
    }
}

// MARK: - Shortcuts provider (Siri / Spotlight / Shortcuts.app discovery)

struct DecaffeinateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SleepNowIntent(),
            phrases: [
                "Sleep now with \(.applicationName)",
                "Put my Mac to sleep with \(.applicationName)",
                "\(.applicationName) sleep now",
            ],
            shortTitle: "Sleep Now",
            systemImageName: "moon.zzz.fill")

        AppShortcut(
            intent: WhatsKeepingMacAwakeIntent(),
            phrases: [
                "What's keeping my Mac awake with \(.applicationName)",
                "Why won't my Mac sleep with \(.applicationName)",
                "Ask \(.applicationName) what's keeping my Mac awake",
            ],
            shortTitle: "What's Keeping It Awake",
            systemImageName: "bolt.badge.clock")

        AppShortcut(
            intent: KeepAwakeIntent(),
            phrases: [
                "Keep my Mac awake with \(.applicationName)",
                "Caffeinate my Mac with \(.applicationName)",
                "\(.applicationName) keep awake",
            ],
            shortTitle: "Keep Awake",
            systemImageName: "cup.and.saucer.fill")

        AppShortcut(
            intent: StopKeepingAwakeIntent(),
            phrases: [
                "Stop keeping my Mac awake with \(.applicationName)",
                "Let my Mac sleep with \(.applicationName)",
                "\(.applicationName) stop keeping awake",
            ],
            shortTitle: "Stop Keep Awake",
            systemImageName: "moon.fill")
    }
}
