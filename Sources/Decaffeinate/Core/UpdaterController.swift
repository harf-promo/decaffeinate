import Foundation
import Sparkle

/// Wraps Sparkle's updater. Guarded so it's a clean no-op when run unbundled
/// (e.g. `--scan` from a terminal or in CI), where Sparkle has no Info.plist
/// feed/key to work with.
///
/// Publishes `updateAvailable` (set by Sparkle's scheduled background check) so
/// the menu can surface a clear "Update available" affordance, and exposes the
/// standard Settings controls (check now, automatic checks, last-checked).
@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var updateAvailable = false
    @Published private(set) var lastCheckedAt: Date?
    @Published var automaticChecksEnabled: Bool = true {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecksEnabled }
    }

    private var controller: SPUStandardUpdaterController?
    private static let lastCheckedKey = "Decaffeinate.lastUpdateCheck"

    override init() {
        super.init()
        lastCheckedAt = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
        if Bundle.main.bundleIdentifier != nil,
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            automaticChecksEnabled = controller.updater.automaticallyChecksForUpdates
        }
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// A user-initiated "Check for Updates…" (Settings / app menu). Stamps the
    /// last-checked time immediately so the UI reflects the action.
    func checkForUpdatesUserInitiated() {
        stampChecked()
        controller?.checkForUpdates(nil)
    }

    private func stampChecked() {
        let now = Date()
        lastCheckedAt = now
        UserDefaults.standard.set(now, forKey: Self.lastCheckedKey)
    }

    // MARK: SPUUpdaterDelegate — flip the published flag as Sparkle discovers /
    // resolves updates (delegate callbacks arrive on the main thread).

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { updateAvailable = true }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { updateAvailable = false }
    }

    nonisolated func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        // Record when the last check completed; clear the badge on error (a later
        // scheduled check will re-raise it if needed).
        MainActor.assumeIsolated {
            stampChecked()
            if error != nil { updateAvailable = false }
        }
    }
}
