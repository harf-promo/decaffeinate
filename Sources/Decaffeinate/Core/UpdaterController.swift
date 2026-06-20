import Foundation
import Sparkle

/// Wraps Sparkle's updater. Guarded so it's a clean no-op when run unbundled
/// (e.g. `--scan` from a terminal or in CI), where Sparkle has no Info.plist
/// feed/key to work with.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    init() {
        if Bundle.main.bundleIdentifier != nil,
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
