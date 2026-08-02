import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`. This file, and the
/// `DecaffeinateLidHelper` target it would talk to, are **not** part of the
/// shipped app: nothing in `AppState.swift` or any View constructs a
/// `LidHelperClient` or references `LidClosedControlling`
/// (`Core/Protocols.swift`). It exists and compiles so the client-side half
/// of the mechanism is complete; it is exercised in tests only through a
/// fake conforming to `LidClosedControlling`.

/// This module's own, independent mirror of `DecaffeinateLidHelper`'s
/// `LeaseState` — deliberately NOT the same Swift type (`Decaffeinate` does
/// not depend on the `DecaffeinateLidHelper` target at all; see that
/// target's Package.swift comment). Both sides decode the same JSON wire
/// shape into their own, separately-declared type, exactly as any two
/// independent XPC processes would — there is no shared Swift module between
/// a privileged `LaunchDaemon` and the app that talks to it.
struct LidHelperReply: Equatable, Sendable, Codable {
    var isActive: Bool
    var expiresAt: Date?
    var helperVersion: String

    static func inactive(helperVersion: String = "") -> LidHelperReply {
        LidHelperReply(isActive: false, expiresAt: nil, helperVersion: helperVersion)
    }
}

/// This module's own mirror of `DecaffeinateLidHelper.LidHelperXPCProtocol`
/// — same method names and Objective-C-bridgeable signatures, so
/// `NSXPCInterface`'s selector-based dispatch lines up with the real helper,
/// without `Decaffeinate` depending on the `DecaffeinateLidHelper` target. In
/// a shipped, non-spike Phase B this pairing would normally be factored into
/// a small shared "XPC contract" library both targets depend on instead of
/// hand-duplicated — noted here, not done, to keep this spike's footprint to
/// exactly the two targets the design calls for.
@objc protocol LidHelperClientXPCProtocol {
    func acquireLease(ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void)
    func renewLease(ttlSeconds: Int, reply: @escaping @Sendable (Data) -> Void)
    func releaseLease(reply: @escaping @Sendable (Data) -> Void)
    func currentState(reply: @escaping @Sendable (Data) -> Void)
    func helperVersion(reply: @escaping @Sendable (String) -> Void)
}

/// `NSXPCConnection` isn't `Sendable`, but a connection this code creates and
/// only ever touches through its own completion handler is safe to hand
/// across the `@Sendable` reply-block boundary below — this box just makes
/// that explicit to the compiler, the same "narrow, documented `@unchecked`"
/// shape `Tests/DecaffeinateTests/TestSupport.swift`'s own fakes use.
private final class XPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection
    init(_ connection: NSXPCConnection) { self.connection = connection }
}

/// Real, XPC-calling client for the Phase B privileged lid-closed helper
/// (`com.harfpromo.Decaffeinate.lidhelper` — see
/// `Resources/com.harfpromo.Decaffeinate.LidHelper.plist`). Exists and
/// compiles so the mechanism is complete, but per this spike's HARD SAFETY
/// CONSTRAINTS it is never invoked: nothing in `AppState.swift` or any View
/// holds a reference to this type, and no test calls its real XPC methods —
/// tests exercise `LidClosedSession` (the pure state machine) and this
/// protocol seam via a fake conforming to `LidClosedControlling` instead.
@MainActor
final class LidHelperClient: LidClosedControlling {
    private let machServiceName = "com.harfpromo.Decaffeinate.lidhelper"

    /// NEVER CALLED in this spike — see the type's own doc comment. Opens a
    /// fresh connection per call (a lid-closed session is rare and
    /// long-lived relative to connection setup cost; there's no hot-path
    /// reason to keep one open) and always resumes exactly once, whether the
    /// connection resolves or not.
    private func call(
        _ body: @escaping (any LidHelperClientXPCProtocol, @escaping @Sendable (LidHelperReply) -> Void) -> Void
    ) async -> LidHelperReply {
        await withCheckedContinuation { (continuation: CheckedContinuation<LidHelperReply, Never>) in
            let box = XPCConnectionBox(NSXPCConnection(machServiceName: machServiceName, options: .privileged))
            box.connection.remoteObjectInterface = NSXPCInterface(with: LidHelperClientXPCProtocol.self)
            box.connection.resume()
            guard let proxy = box.connection.remoteObjectProxy as? LidHelperClientXPCProtocol else {
                box.connection.invalidate()
                continuation.resume(returning: .inactive())
                return
            }
            body(proxy) { reply in
                box.connection.invalidate()
                continuation.resume(returning: reply)
            }
        }
    }

    func acquireLease(ttlSeconds: Int) async -> LidHelperReply {
        await call { proxy, finish in
            proxy.acquireLease(ttlSeconds: ttlSeconds) { data in finish(Self.decode(data)) }
        }
    }

    func renewLease(ttlSeconds: Int) async -> LidHelperReply {
        await call { proxy, finish in
            proxy.renewLease(ttlSeconds: ttlSeconds) { data in finish(Self.decode(data)) }
        }
    }

    func releaseLease() async -> LidHelperReply {
        await call { proxy, finish in
            proxy.releaseLease { data in finish(Self.decode(data)) }
        }
    }

    func currentState() async -> LidHelperReply {
        await call { proxy, finish in
            proxy.currentState { data in finish(Self.decode(data)) }
        }
    }

    func helperVersion() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let box = XPCConnectionBox(NSXPCConnection(machServiceName: machServiceName, options: .privileged))
            box.connection.remoteObjectInterface = NSXPCInterface(with: LidHelperClientXPCProtocol.self)
            box.connection.resume()
            guard let proxy = box.connection.remoteObjectProxy as? LidHelperClientXPCProtocol else {
                box.connection.invalidate()
                continuation.resume(returning: nil)
                return
            }
            proxy.helperVersion { version in
                box.connection.invalidate()
                continuation.resume(returning: version)
            }
        }
    }

    /// `nonisolated` — called from inside `@Sendable` XPC reply closures that
    /// may run off the main actor; decoding JSON has no actor-isolated state
    /// to protect.
    private nonisolated static func decode(_ data: Data) -> LidHelperReply {
        (try? JSONDecoder().decode(LidHelperReply.self, from: data)) ?? .inactive()
    }
}
