import AppKit
import SwiftUI

/// Resolves and caches the real macOS app icon for a blocker, so the menu can
/// show *who* is keeping the Mac awake at a glance (far easier to judge than a
/// process name). Prefers the attributed real owner's bundle (the actual app
/// behind a shared daemon). Daemons with no app bundle return `nil` and the view
/// falls back to the reason's category symbol.
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cache: [String: NSImage?] = [:]

    func icon(for assertion: PowerAssertion) -> NSImage? {
        let key = cacheKey(for: assertion)
        if let cached = cache[key] { return cached }
        let image = resolve(assertion)
        cache[key] = image
        return image
    }

    private func cacheKey(for a: PowerAssertion) -> String {
        a.realOwner?.bundleIdentifier ?? a.bundleIdentifier ?? a.bundlePath ?? "pid:\(a.pid)"
    }

    private func resolve(_ a: PowerAssertion) -> NSImage? {
        // Prefer the real owner's bundle — the actual app behind a daemon.
        if let bundleID = a.realOwner?.bundleIdentifier ?? a.bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let icon = NSRunningApplication(processIdentifier: a.pid)?.icon {
            return icon
        }
        if let path = a.bundlePath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
}

/// The app icon for a blocker, or its reason-category symbol when no real app
/// bundle exists (daemons like `coreaudiod`, `runningboardd`).
struct AppIconView: View {
    let assertion: PowerAssertion
    var size: CGFloat = 24

    var body: some View {
        if let icon = AppIconProvider.shared.icon(for: assertion) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: assertion.reason.category.systemImage)
                .font(.system(size: size * 0.66))
                .foregroundStyle(Color.ink2)
                .frame(width: size, height: size)
        }
    }
}
