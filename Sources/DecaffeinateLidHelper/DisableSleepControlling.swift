import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// Seam over the single, undocumented, root-only mechanism that could force a
/// closed, displayless Mac to stay awake: `pmset disablesleep <0|1>` (see
/// `docs/ARCHITECTURE.md`'s non-goals — the private in-process alternatives
/// all field-verified fail; only this global kernel flag actually works).
/// Mirrors `Core/SleepController.swift`'s exact protocol + real + fake shape
/// one-for-one, so `LidHelperService`'s lease bookkeeping is fully testable
/// via a fake.
///
/// The real, `Process`-based implementation below (`LiveDisableSleepController`)
/// exists so this code compiles into a structurally complete helper — but
/// per this spike's HARD SAFETY CONSTRAINTS it is **never invoked**: no test
/// in this repository exercises it, and `main.swift` (which would wire it
/// into a live XPC listener) is never executed as part of this spike.
public protocol DisableSleepControlling: Sendable {
    @discardableResult
    func setDisableSleep(_ disabled: Bool) -> Result<Void, DisableSleepError>
}

public enum DisableSleepError: Error, CustomStringConvertible, Sendable, Equatable {
    case launchFailed(String)
    case nonZeroExit(Int32)

    public var description: String {
        switch self {
        case .launchFailed(let message): return "Could not launch pmset: \(message)"
        case .nonZeroExit(let code): return "pmset disablesleep exited with code \(code)"
        }
    }
}

/// The real implementation. This binary would run as root (registered as a
/// `LaunchDaemon` via `SMAppService.daemon`), so no `sudo` prefix is needed —
/// unlike `Core/SleepController.swift`'s `pmset sleepnow`, which the current
/// (unprivileged) user can already invoke, `disablesleep` genuinely requires
/// root, which is the entire reason this helper would need to exist.
///
/// NEVER INVOKED in this spike — exists only so the source compiles into a
/// structurally complete helper. See the file's top doc comment.
public struct LiveDisableSleepController: DisableSleepControlling {
    public var pmsetURL: URL

    public init(pmsetURL: URL = URL(fileURLWithPath: "/usr/bin/pmset")) {
        self.pmsetURL = pmsetURL
    }

    @discardableResult
    public func setDisableSleep(_ disabled: Bool) -> Result<Void, DisableSleepError> {
        let process = Process()
        process.executableURL = pmsetURL
        process.arguments = ["disablesleep", disabled ? "1" : "0"]
        do {
            try process.run()
            // Unlike `SleepController.sleepNow()`, this call is NOT racing a
            // sleep transition — waiting for the exit code is safe and lets a
            // real (never-invoked) caller distinguish a launch failure from a
            // non-zero `pmset` exit.
            process.waitUntilExit()
            let status = process.terminationStatus
            return status == 0 ? .success(()) : .failure(.nonZeroExit(status))
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }
}
