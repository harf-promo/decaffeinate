import Foundation
import AppKit
import Darwin

/// Resolve a process executable name from its PID using `proc_pidpath`,
/// falling back to `proc_name`. Returns the last path component (e.g. the
/// binary name) so `…/Google Chrome.app/Contents/MacOS/Google Chrome`
/// becomes `Google Chrome`.
func processName(forPID pid: pid_t) -> String {
    if let running = NSRunningApplication(processIdentifier: pid),
       let localized = running.localizedName, !localized.isEmpty {
        return localized
    }

    var pathBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
    if pathLength > 0, let path = nullTerminatedString(pathBuffer) {
        let last = (path as NSString).lastPathComponent
        if !last.isEmpty { return last }
    }

    var nameBuffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let nameLength = proc_name(pid, &nameBuffer, UInt32(MAXPATHLEN))
    if nameLength > 0, let name = nullTerminatedString(nameBuffer), !name.isEmpty {
        return name
    }

    return "PID \(pid)"
}

private func nullTerminatedString(_ bytes: [UInt8]) -> String? {
    let trimmed = bytes.prefix { $0 != 0 }
    return trimmed.isEmpty ? nil : String(decoding: trimmed, as: UTF8.self)
}

/// Resolve a bundle identifier for a PID via the running-application registry.
/// Many sleep-holders (browsers, music apps) are GUI apps and expose this;
/// daemons and helpers will return `nil`.
func bundleIdentifier(forPID pid: pid_t) -> String? {
    NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
}

/// Localized application display name for a bundle identifier, if one is
/// installed. Used to turn `com.google.Chrome` into `Google Chrome`.
func NSWorkspaceAppName(_ bundleID: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        return nil
    }
    let name = FileManager.default.displayName(atPath: url.path)
    let trimmed = (name as NSString).deletingPathExtension
    return trimmed.isEmpty ? nil : trimmed
}
