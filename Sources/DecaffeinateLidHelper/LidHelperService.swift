import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// The mechanism-only coordinator behind the helper's XPC surface — no
/// policy, no UI, no TTL choice: those stay in the unprivileged app,
/// mirroring this codebase's existing `SafetyRails`/`CaffeineEngine`
/// separation (`docs/ARCHITECTURE.md`'s engine map). Every XPC method
/// (`acquireLease`/`renewLease`/`releaseLease`/`currentState`/
/// `helperVersion`) is a thin pass-through to this type (see
/// `LidHelperXPCService`).
///
/// An `actor` (not `@MainActor`, unlike this app's own engines) because a
/// real deployment's XPC connections can call in concurrently from launchd's
/// dispatch — actor isolation is the synchronization the mutable `lease`
/// needs, with no UI/run-loop reason to prefer the main actor the way
/// `AppState`'s engines do.
///
/// Hardcoded, not configurable over XPC, per the original design: clears the
/// flag on launch (the `RunAtLoad` reboot-antidote — a fresh launchd start
/// always begins from a known-clear state), on `SIGTERM`, and the instant a
/// lease expires (the dead-man switch). Callers drive `now` explicitly so
/// this stays deterministic and fully testable via `DisableSleepControlling`
/// fakes — no test in this repository ever supplies the real
/// `LiveDisableSleepController`.
public actor LidHelperService {
    private let disableSleep: any DisableSleepControlling
    private var lease = LidHelperLease()

    public init(disableSleep: any DisableSleepControlling) {
        self.disableSleep = disableSleep
    }

    /// Call once, first thing, from `main.swift` before the XPC listener
    /// starts accepting connections — the `RunAtLoad` reboot antidote.
    /// Clears any stale flag a prior, uncleanly-terminated run might have
    /// left set. NEVER INVOKED in this spike (main.swift's call site is
    /// never executed).
    public func clearOnLaunch() {
        disableSleep.setDisableSleep(false)
        lease.release()
    }

    /// Call from the process's `SIGTERM` handler (`launchctl stop` / a
    /// system shutdown request) — clears the flag before the process
    /// actually exits, so a normal stop never strands the flag set. NEVER
    /// INVOKED in this spike.
    public func clearOnSIGTERM() {
        disableSleep.setDisableSleep(false)
        lease.release()
    }

    @discardableResult
    public func acquireLease(ttlSeconds: Int, now: Date) -> LeaseState {
        expireIfNeeded(now: now)
        lease.acquire(ttlSeconds: ttlSeconds, now: now)
        disableSleep.setDisableSleep(true)
        return currentState(now: now)
    }

    /// A heartbeat, expected every ~30 s while a lease is active. A late
    /// heartbeat that arrives **after** the dead-man switch already fired and
    /// cleared the flag deliberately does NOT resurrect a session — the app
    /// must call `acquireLease` again instead. Silently re-arming on a stale
    /// renew would defeat the entire point of the expiry-triggered clear (a
    /// backgrounded/crashed app, or a Mac in a bag with no network, must not
    /// be able to "catch up" a lease that already timed out).
    @discardableResult
    public func renewLease(ttlSeconds: Int, now: Date) -> LeaseState {
        expireIfNeeded(now: now)
        guard lease.isActive else {
            return currentState(now: now)
        }
        lease.renew(ttlSeconds: ttlSeconds, now: now)
        // Idempotent — the flag should already be set from the original
        // acquire, but reasserting is cheap and self-healing if it was ever
        // cleared out from under an active lease by something else.
        disableSleep.setDisableSleep(true)
        return currentState(now: now)
    }

    @discardableResult
    public func releaseLease(now: Date) -> LeaseState {
        lease.release()
        disableSleep.setDisableSleep(false)
        return currentState(now: now)
    }

    public func currentState(now: Date = Date()) -> LeaseState {
        expireIfNeeded(now: now)
        return LeaseState(isActive: lease.isActive, expiresAt: lease.expiresAt)
    }

    public nonisolated func helperVersion() -> String {
        LeaseState.currentHelperVersion
    }

    /// The dead-man switch: if the lease's expiry has passed, clear the flag
    /// immediately rather than waiting for a heartbeat that may never come.
    private func expireIfNeeded(now: Date) {
        guard lease.isExpired(now: now) else { return }
        lease.release()
        disableSleep.setDisableSleep(false)
    }
}
