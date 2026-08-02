import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// The `NSXPCListener`-facing glue: bridges `LidHelperXPCProtocol`'s
/// Data/String reply shape to `LidHelperService`'s `actor`-isolated Swift
/// API. A plain `NSObject` subclass (XPC's exported object must be one) that
/// hops onto the service actor per call and replies once that call
/// completes.
///
/// NEVER INSTANTIATED except by `main.swift`'s listener wiring, which is
/// never executed as part of this spike — see the spike's hard safety
/// constraints. No test in this repository creates an `NSXPCConnection` to
/// talk to this type; tests call `LidHelperService` directly.
// `@unchecked Sendable`: the only stored property is an immutable reference to
// an `actor` (itself Sendable) — safe to cross into the `Task { }` closures
// below, but `NSObject` subclassing keeps the compiler from verifying that
// automatically.
public final class LidHelperXPCService: NSObject, LidHelperXPCProtocol, @unchecked Sendable {
    private let service: LidHelperService

    public init(service: LidHelperService) {
        self.service = service
    }

    public func acquireLease(ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let state = await service.acquireLease(ttlSeconds: ttlSeconds, now: Date())
            reply(Self.encode(state))
        }
    }

    public func renewLease(ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let state = await service.renewLease(ttlSeconds: ttlSeconds, now: Date())
            reply(Self.encode(state))
        }
    }

    public func releaseLease(reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let state = await service.releaseLease(now: Date())
            reply(Self.encode(state))
        }
    }

    public func currentState(reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let state = await service.currentState(now: Date())
            reply(Self.encode(state))
        }
    }

    public func helperVersion(reply: @escaping @Sendable (String) -> Void) {
        reply(service.helperVersion())
    }

    private static func encode(_ state: LeaseState) -> Data {
        (try? JSONEncoder().encode(state)) ?? Data()
    }
}
