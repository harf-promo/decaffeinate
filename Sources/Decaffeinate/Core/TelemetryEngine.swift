import Foundation
import IOKit.pwr_mgt

/// Per-assertion dictionary keys returned by `IOPMCopyAssertionsByProcess`.
/// These are *not* exposed as SDK symbols (unlike `kIOPMAssertionTypeKey` /
/// `kIOPMAssertionNameKey`), so they're centralized here. Values were verified
/// empirically against the live API.
enum AssertionDetailKey {
    static let startWhen = "AssertStartWhen"  // Date the assertion was created
    static let assertionID = "AssertionId"
    static let globalUniqueID = "GlobalUniqueID"
    static let processName = "Process Name"
    static let onBehalfOfPID = "AssertionOnBehalfOfPID"
    static let bundlePath = "BundlePath"
}

/// Reads the live set of power assertions on the system and attributes each one
/// to the process that owns it.
///
/// This is the honest core of Decaffeinate: rather than guessing, it asks the
/// kernel directly via `IOPMCopyAssertionsByProcess` which processes are
/// currently holding the Mac awake. No private APIs, no root, no kexts.
struct TelemetryEngine {

    /// Snapshot every active assertion, attributed to its owning process.
    func scan() -> [PowerAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
            let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else {
            return []
        }

        var result: [PowerAssertion] = []
        result.reserveCapacity(byProcess.count)

        for (pidNumber, assertions) in byProcess {
            let pid = pid_t(truncating: pidNumber)
            let name = processName(forPID: pid)
            let bundle = bundleIdentifier(forPID: pid)

            for detail in assertions {
                let type = detail[kIOPMAssertionTypeKey as String] as? String ?? "Unknown"
                let assertionName = detail[kIOPMAssertionNameKey as String] as? String ?? "Unnamed"
                let created = detail[AssertionDetailKey.startWhen] as? Date
                let assertionID =
                    (detail[AssertionDetailKey.assertionID] as? Int)
                    ?? (detail[AssertionDetailKey.globalUniqueID] as? Int)
                let onBehalfOfPID = (detail[AssertionDetailKey.onBehalfOfPID] as? Int).map(
                    pid_t.init)

                result.append(
                    PowerAssertion(
                        id: "\(pid)-\(assertionID ?? result.count)-\(type)",
                        pid: pid,
                        processName: name,
                        bundleIdentifier: bundle,
                        assertionType: type,
                        name: assertionName,
                        kind: AssertionType.classify(type),
                        createdAt: created,
                        realOwner: resolveRealOwner(
                            ownerProcessName: name,
                            ownerPID: pid,
                            onBehalfOfPID: onBehalfOfPID,
                            assertionName: assertionName
                        )
                    )
                )
            }
        }

        // Stable, useful ordering: machine-blockers first, then by process name.
        return result.sorted { lhs, rhs in
            if lhs.blocksSystemSleep != rhs.blocksSystemSleep {
                return lhs.blocksSystemSleep
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                == .orderedAscending
        }
    }

    /// Resolve the real app behind a hold routed through a shared daemon. Only
    /// attributes when the owner is a known shared daemon AND the resolved owner
    /// is a real installed app — so system holds (e.g. coreaudiod's built-in
    /// speaker) are left attributed to the daemon, not mislabelled.
    private func resolveRealOwner(
        ownerProcessName: String,
        ownerPID: pid_t,
        onBehalfOfPID: pid_t?,
        assertionName: String
    ) -> AssertionOwner? {
        guard AssertionAttributor.isSharedDaemon(ownerProcessName) else { return nil }

        // Prefer the explicit on-behalf-of PID when present and distinct.
        if let behalf = onBehalfOfPID, behalf > 0, behalf != ownerPID {
            let resolvedName = processName(forPID: behalf)
            let resolvedBundle = bundleIdentifier(forPID: behalf)
            if !resolvedName.hasPrefix("PID ") {
                return AssertionOwner(name: resolvedName, bundleIdentifier: resolvedBundle)
            }
        }

        // Otherwise parse the assertion name and resolve it to the *canonical*
        // top-level app, so e.g. `com.google.Chrome.helper` maps to Google
        // Chrome, not a helper sub-bundle.
        if let hint = AssertionAttributor.bundleIDHint(inName: assertionName) {
            return canonicalOwner(forHint: hint)
        }
        return nil
    }

    /// Walk reverse-DNS prefixes of `hint` shortest-first and return the first
    /// that resolves to an installed top-level app — so the canonical app id wins
    /// over a `.helper` / `.gpu` sub-bundle, and framework/XPC bundles are
    /// rejected entirely.
    private func canonicalOwner(forHint hint: String) -> AssertionOwner? {
        let segments = hint.split(separator: ".").map(String.init)
        if segments.count >= 3 {
            for count in 3...segments.count {
                let candidate = segments.prefix(count).joined(separator: ".")
                if let app = topLevelAppName(forBundleID: candidate) {
                    return AssertionOwner(name: app, bundleIdentifier: candidate)
                }
            }
            return nil
        }
        if let app = topLevelAppName(forBundleID: hint) {
            return AssertionOwner(name: app, bundleIdentifier: hint)
        }
        return nil
    }
}
