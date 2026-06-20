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

                result.append(
                    PowerAssertion(
                        id: "\(pid)-\(assertionID ?? result.count)-\(type)",
                        pid: pid,
                        processName: name,
                        bundleIdentifier: bundle,
                        assertionType: type,
                        name: assertionName,
                        kind: AssertionType.classify(type),
                        createdAt: created
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
}
