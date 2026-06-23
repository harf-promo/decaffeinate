import Foundation
import Sparkle

/// Wraps Sparkle's updater. Guarded so it's a clean no-op when run unbundled
/// (e.g. `--scan` from a terminal or in CI), where Sparkle has no Info.plist
/// feed/key to work with.
///
/// Publishes `state` (and the derived `updateAvailable`) so the menu and
/// Settings → About can surface clear, contextual feedback after every check.
@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {

    /// The lifecycle of an update check — drives status UI in Settings → About.
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case failed(reason: String)

        static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking),
                (.upToDate, .upToDate), (.updateAvailable, .updateAvailable):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var lastCheckedAt: Date?
    @Published var automaticChecksEnabled: Bool = true {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecksEnabled }
    }

    /// Derived convenience — keeps existing call sites compiling unchanged.
    var updateAvailable: Bool { state == .updateAvailable }

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
        state = .checking
        controller?.checkForUpdates(nil)
    }

    /// A user-initiated "Check for Updates…" (Settings / app menu). Stamps the
    /// last-checked time immediately so the UI reflects the action.
    func checkForUpdatesUserInitiated() {
        state = .checking
        stampChecked()
        controller?.checkForUpdates(nil)
    }

    private func stampChecked() {
        let now = Date()
        lastCheckedAt = now
        UserDefaults.standard.set(now, forKey: Self.lastCheckedKey)
    }

    // MARK: SPUUpdaterDelegate — drive the published state as Sparkle discovers /
    // resolves updates (delegate callbacks arrive on the main thread).

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { state = .updateAvailable }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { state = .upToDate }
    }

    nonisolated func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        // Record when the last check completed. The find/not-found callbacks have
        // already set the terminal state; only override it here on error.
        MainActor.assumeIsolated {
            stampChecked()
            if let error { state = .failed(reason: error.localizedDescription) }
        }
    }
}
