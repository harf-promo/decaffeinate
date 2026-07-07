import Foundation

/// Puts the Mac to sleep on demand.
///
/// Uses `/usr/bin/pmset sleepnow`, which the current user can invoke without
/// root. This is the one and only way Decaffeinate makes the machine sleep —
/// the same call macOS' own menu uses — so even processes holding "prevent idle
/// sleep" assertions are overridden, cleanly and safely, by the kernel's normal
/// sleep transition. There is no private API and no forced memory access.
struct SleepController {

    enum SleepError: Error, CustomStringConvertible {
        case launchFailed(String)
        /// Never produced at runtime — `run(arguments:)` deliberately does not
        /// `waitUntilExit()`, so only `.launchFailed` can occur. Retained as a
        /// distinct failure the test suite injects to exercise the failed-sleep
        /// path (see `AppStateTests.testFailedSleepDoesNotClaimSlept…`).
        case nonZeroExit(Int32)

        var description: String {
            switch self {
            case .launchFailed(let message): return "Could not launch pmset: \(message)"
            case .nonZeroExit(let code): return "pmset exited with code \(code)"
            }
        }
    }

    /// The executable we shell out to. Overridable so tests can point at a stub.
    var pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")

    /// Sleep the whole machine now.
    @discardableResult
    func sleepNow() -> Result<Void, SleepError> {
        run(arguments: ["sleepnow"])
    }

    /// Turn the display off now, leaving the system running — the inverse of the
    /// Rest & Restart "display off vs sleep" distinction the app already teaches.
    /// `pmset displaysleepnow` needs no root, same as `sleepnow`.
    @discardableResult
    func displayOffNow() -> Result<Void, SleepError> {
        run(arguments: ["displaysleepnow"])
    }

    private func run(arguments: [String]) -> Result<Void, SleepError> {
        let process = Process()
        process.executableURL = pmsetURL
        process.arguments = arguments
        do {
            try process.run()
            // Deliberately do NOT block on `waitUntilExit()`: `pmset sleepnow`
            // does not return until the kernel begins the sleep transition, and
            // this is invoked on the @MainActor tick — waiting would freeze the
            // menu and the run-loop timer at the exact moment of sleep. A
            // successful launch is the signal we need; the machine is already on
            // its way down. (`nonZeroExit` is retained for the test/protocol seam.)
            return .success(())
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }
}
