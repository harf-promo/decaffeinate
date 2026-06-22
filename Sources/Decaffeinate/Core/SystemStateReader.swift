import Darwin
import Foundation

/// Reads the kernel boot time so the app can tell how long the Mac has been up
/// (uptime = now − bootTime) — the basis for the restart recommendation. Public
/// `sysctl(CTL_KERN, KERN_BOOTTIME)`, no root, degrades to nil.
struct SystemStateReader: SystemStateReading {
    func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, u_int(mib.count), &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else {
            return nil
        }
        return Date(
            timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }
}
