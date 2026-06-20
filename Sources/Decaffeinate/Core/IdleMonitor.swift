import Foundation
import CoreGraphics

/// Reports how long the human has been away from the keyboard and trackpad.
///
/// Uses `CGEventSource` HID idle time — the same signal macOS itself uses to
/// decide when to dim the display. Zero permissions required; it only reads how
/// long since the *last* input event, never what the input was.
struct IdleMonitor {

    /// Seconds since the last keyboard / mouse / trackpad event.
    func secondsSinceLastInput() -> TimeInterval {
        // `~0` is `kCGAnyInputEventType` — match on any HID input event.
        let anyInput = CGEventType(rawValue: ~0)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                              eventType: anyInput)
        // Guard against the occasional bogus huge value right after wake.
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return seconds
    }
}
