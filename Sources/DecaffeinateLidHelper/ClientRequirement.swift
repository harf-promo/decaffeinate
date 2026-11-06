import Foundation
import Security

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// Builds the code-signing requirement an XPC client must satisfy before the
/// helper accepts its connection. Pure string logic so it is unit-testable
/// without any live signing identity.
enum ClientRequirement {
    /// The app's bundle identifier, as declared in `Resources/Info.plist`.
    static let appBundleIdentifier = "com.harfpromo.Decaffeinate"

    /// Apple Team IDs are exactly 10 uppercase alphanumerics. Anything else is
    /// rejected so a hostile value can never be spliced into the requirement.
    static func isValidTeamID(_ teamID: String) -> Bool {
        teamID.count == 10
            && teamID.unicodeScalars.allSatisfy {
                ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x30 && $0.value <= 0x39)
            }
    }

    /// Requirement: Apple-issued cert chain, our bundle identifier, our team ID
    /// (the team check is what restricts it to our own signing identity).
    /// Returns `nil` (caller must fail closed) when no valid team ID is known —
    /// the repo declares none, so it is supplied at runtime (see `ownTeamID`).
    static func requirementString(
        teamID: String?, bundleIdentifier: String = appBundleIdentifier
    ) -> String? {
        guard let teamID, isValidTeamID(teamID) else { return nil }
        guard
            !bundleIdentifier.isEmpty,
            bundleIdentifier.unicodeScalars.allSatisfy({
                ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
                    || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "." || $0 == "-"
            })
        else { return nil }
        return
            "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// The helper's own team ID, read from its code signature. `nil` when
    /// ad-hoc/unsigned, which makes the listener reject every client.
    static func ownTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
        else { return nil }
        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
