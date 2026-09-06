import CoreGraphics

// =====================================================================
// The canonical size of every window and panel the app draws itself.
//
// These used to be written twice — once in the view's `.frame(…)` and again
// in `ScreenshotRenderer`'s capture call — so resizing a surface silently
// captured it at the old size and the README kept advertising a layout that
// no longer shipped. One declaration, two readers.
//
// Window chrome that macOS owns (menu-bar height, the popover's own inset,
// safe areas) is deliberately absent: those are OS facts, passed through
// rather than laddered. See docs/DESIGN.md.
// =====================================================================
enum WindowMetrics {
    /// The Settings window. macOS sizes a Settings scene to its content.
    static let settings = CGSize(width: 700, height: 520)

    /// The onboarding window — two fixed panels, same frame.
    static let onboarding = CGSize(width: 500, height: 440)

    /// The pre-sleep countdown HUD. Height is content-driven; the capture pads
    /// it so the panel's edge is visible against the screenshot background.
    static let hudWidth: CGFloat = 360
    static let hudCapture = CGSize(width: 400, height: 130)

    /// The Clamshell Assistant panel. Its height changes with readiness, so the
    /// two captures differ while the width does not.
    static let clamshellWidth: CGFloat = 360
    static let clamshellReadyCapture = CGSize(width: 360, height: 320)
    static let clamshellMissingCapture = CGSize(width: 360, height: 460)

    /// The expanded provenance detail, captured on its own.
    static let assertionDetailCapture = CGSize(width: 360, height: 360)
}
