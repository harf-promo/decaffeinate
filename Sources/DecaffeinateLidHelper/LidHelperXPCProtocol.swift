import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// The Mach service's `@objc` XPC surface (`com.harfpromo.Decaffeinate.lidhelper`
/// — see `Resources/com.harfpromo.Decaffeinate.LidHelper.plist`'s
/// `MachServices` key) — the shape `NSXPCConnection`/`NSXPCListener` (Apple's
/// long-standing mechanism for a privileged-helper `LaunchDaemon` registered
/// via `SMAppService.daemon`) requires: an `@objc` protocol whose methods
/// take only Objective-C-bridgeable types and reply blocks.
///
/// `LeaseState` is a pure Swift struct (see `LeaseState.swift`), not directly
/// `@objc`-representable, so replies cross the wire as JSON-encoded `Data`,
/// decoded back into `LeaseState` on each side — the same "Codable payload
/// over `Data`" bridge many `NSXPCConnection`-based privileged helpers use
/// instead of hand-writing an `NSSecureCoding` box for every value type.
/// `Int`/`String` cross natively (both are Objective-C-bridgeable).
///
/// Nothing else lives on this surface — mechanism-only, no policy — matching
/// the design: rails, TTL choice, and all UI stay in the unprivileged app.
///
/// Structurally correct and used by `main.swift`'s listener wiring — but per
/// this spike's HARD SAFETY CONSTRAINTS, that listener is never started, and
/// no test connects over a real `NSXPCConnection`: every test exercises
/// `LidHelperService` directly, in-process, against a fake
/// `DisableSleepControlling`.
@objc public protocol LidHelperXPCProtocol {
    /// `ttlSeconds` is clamped server-side to `LidHelperLease.maxTTLSeconds`
    /// regardless of what's requested — the helper never trusts the caller's
    /// number directly.
    func acquireLease(ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void)
    /// Heartbeat, expected every ~30 s from the app while a lease is active.
    func renewLease(ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void)
    func releaseLease(reply: @escaping @Sendable (Data) -> Void)
    func currentState(reply: @escaping @Sendable (Data) -> Void)
    func helperVersion(reply: @escaping @Sendable (String) -> Void)
}
