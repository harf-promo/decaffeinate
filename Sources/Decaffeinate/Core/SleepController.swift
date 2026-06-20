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

    /// Sleep just the display now (softer than a full system sleep).
    @discardableResult
    func sleepDisplayNow() -> Result<Void, SleepError> {
        run(arguments: ["displaysleepnow"])
    }

    private func run(arguments: [String]) -> Result<Void, SleepError> {
        let process = Process()
        process.executableURL = pmsetURL
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return .failure(.nonZeroExit(process.terminationStatus))
            }
            return .success(())
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }
}
