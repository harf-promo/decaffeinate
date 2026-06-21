import Foundation
import Sparkle

/// Wraps Sparkle's updater. Guarded so it's a clean no-op when run unbundled
/// (e.g. `--scan` from a terminal or in CI), where Sparkle has no Info.plist
/// feed/key to work with.
///
/// Publishes `updateAvailable` (set by Sparkle's scheduled background check) so
/// the menu can surface a clear "Update available" affordance — updates must be
/// impossible to miss.
@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var updateAvailable = false

    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil,
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        }
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
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
        // After the user installs (or the cycle ends with nothing pending), clear
        // the badge; a later scheduled check will re-raise it if needed.
        if error != nil { MainActor.assumeIsolated { updateAvailable = false } }
    }
}
