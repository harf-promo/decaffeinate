import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at login" toggle.
/// Guarded so it no-ops cleanly when run unbundled.
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// The live registration state from the OS, or nil when unbundled. The OS
    /// owns this state — System Settings can flip it behind the app's back — so
    /// UI must read this, never a cached preference.
    static var isEnabled: Bool? {
        guard isAvailable else { return nil }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
