import Foundation

/// Traces a sleep assertion routed through a *shared daemon* back to the real
/// application responsible for it.
///
/// macOS surfaces some holds under `coreaudiod` (audio) or `runningboardd`
/// (WebKit media), not the app you'd expect. The real owner is usually encoded
/// in the assertion name (e.g. `…application.com.apple.Safari.821279…`) and
/// sometimes in `AssertionOnBehalfOfPID`. This type extracts a *bundle-id hint*
/// purely from strings (so it's unit-testable); the caller then confirms it
/// resolves to a real installed app before trusting it.
enum AssertionAttributor {

    /// Daemons that commonly hold assertions on behalf of another app.
    static let sharedDaemons: Set<String> = ["coreaudiod", "runningboardd"]

    static func isSharedDaemon(_ processName: String) -> Bool {
        sharedDaemons.contains(processName.lowercased())
    }

    /// Best-effort bundle identifier of the real owner, parsed from an assertion
    /// name. Returns `nil` when no plausible bundle id is present.
    static func bundleIDHint(inName name: String) -> String? {
        let separators = CharacterSet(charactersIn: "()[]{}<>:,;|/\\ \t\n\"'")
        let rawTokens = name.components(separatedBy: separators)

        var candidates: [String] = []
        for raw in rawTokens {
            // `runningboardd`/WebKit wrap the owner as `…application.<bundle id>…`.
            var token = raw
            if let range = token.range(of: "application.") {
                token = String(token[range.upperBound...])
            }
            if let id = trimToBundleID(token) {
                candidates.append(id)
            }
        }

        // Return a real-app-looking id; never fall back to a WebKit/XPC
        // infrastructure id (those aren't real owners and would mis-attribute).
        let infrastructure = ["webkit", ".gpu", ".xpc", "xpcservice", "runningboard"]
        return candidates.first { candidate in
            let lower = candidate.lowercased()
            return !infrastructure.contains { lower.contains($0) }
        }
    }

    /// Trim an over-qualified id like `com.apple.Safari.821279.822163` down to the
    /// bundle id `com.apple.Safari` by dropping trailing instance/number segments.
    /// Returns `nil` if the input isn't a plausible reverse-DNS id.
    static func trimToBundleID(_ string: String) -> String? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var kept: [String] = []
        for part in parts {
            guard let first = part.first else { break }  // empty segment → stop
            if part.allSatisfy(\.isNumber) { break }  // instance id → stop
            if kept.isEmpty, !first.isLetter { return nil }  // must start with a letter
            guard part.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { break }
            kept.append(part)
        }
        guard kept.count >= 2 else { return nil }
        return kept.joined(separator: ".")
    }
}
