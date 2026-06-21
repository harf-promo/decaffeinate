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
    private let maxEntries = 64

    func icon(for assertion: PowerAssertion) -> NSImage? {
        let key = cacheKey(for: assertion)
        if let cached = cache[key] { return cached }
        let image = resolve(assertion)
        // Bound the cache so a long session monitoring many apps doesn't grow it
        // without limit (icons can be a few MB each).
        if cache.count >= maxEntries { cache.removeAll() }
        cache[key] = image
        return image
    }

    func cacheKey(for a: PowerAssertion) -> String {
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
/// bundle exists (daemons like `coreaudiod`, `runningboardd`). The icon resolves
/// in a `.task` (after first paint) so the menu never stalls on disk I/O — the
/// category symbol shows until the real icon is ready.
struct AppIconView: View {
    let assertion: PowerAssertion
    var size: CGFloat = 24

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
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
        .task(id: AppIconProvider.shared.cacheKey(for: assertion)) {
            icon = AppIconProvider.shared.icon(for: assertion)
        }
    }
}
