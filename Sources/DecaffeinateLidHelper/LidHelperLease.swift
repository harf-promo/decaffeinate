import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// Pure lease bookkeeping — no XPC, no IOKit, no subprocess. Given "now" and
/// a requested TTL, decides the next expiry and whether the lease is still
/// live. Fully unit-testable without any live system call; `LidHelperService`
/// is the only thing that drives real wall-clock time into it.
public struct LidHelperLease: Equatable, Sendable {
    /// Hard ceiling on any requested TTL, regardless of what the app asks
    /// for — baked into the mechanism, not policy the app (or an XPC caller)
    /// controls. Matches the design's stated cap (see `docs/PLAN-NEXT.md`'s
    /// Phase B section: "TTL hard cap 8 h").
    public static let maxTTLSeconds: Int = 8 * 60 * 60

    /// The heartbeat cadence the app is expected to renew at — informational
    /// only, mirrors the design doc's "~30 s heartbeats"; the lease itself
    /// doesn't enforce a *minimum* renewal cadence, only the maximum TTL per
    /// request and the absolute expiry below.
    public static let expectedRenewIntervalSeconds: TimeInterval = 30

    public private(set) var expiresAt: Date?

    public init(expiresAt: Date? = nil) {
        self.expiresAt = expiresAt
    }

    public var isActive: Bool { expiresAt != nil }

    /// Clamp a requested TTL to the hard cap — never trust the caller's
    /// number directly (mirrors `CaffeineEngine`'s clamp-not-trust idempotent
    /// shape elsewhere in this codebase). Negative requests clamp to zero
    /// (an immediately-expired lease) rather than being rejected outright —
    /// the caller finds out via `isActive` being false right away.
    public static func clamp(ttlSeconds: Int) -> Int {
        max(0, min(ttlSeconds, maxTTLSeconds))
    }

    /// Acquire (or replace) a lease starting at `now` for a clamped TTL.
    public mutating func acquire(ttlSeconds: Int, now: Date) {
        let clamped = Self.clamp(ttlSeconds: ttlSeconds)
        expiresAt = now.addingTimeInterval(TimeInterval(clamped))
    }

    /// Renew an existing lease — same clamp, same shape as `acquire`. Callers
    /// (`LidHelperService`) decide separately whether a renew is even
    /// meaningful when there's no live lease; this type just recomputes the
    /// expiry unconditionally.
    public mutating func renew(ttlSeconds: Int, now: Date) {
        acquire(ttlSeconds: ttlSeconds, now: now)
    }

    public mutating func release() {
        expiresAt = nil
    }

    /// True once `now` has passed the lease's expiry — the dead-man switch's
    /// trigger condition. False for an already-released (nil) lease: "not
    /// expired" and "not active" are different questions.
    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}
