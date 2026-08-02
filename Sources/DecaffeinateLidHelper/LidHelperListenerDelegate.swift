import Foundation

/// Phase B spike only — see `docs/PHASE-B-SPIKE.md`.
///
/// `NSXPCListenerDelegate` for the Mach service — accepts a connection,
/// exports `LidHelperXPCProtocol` against a `LidHelperXPCService`. Standard
/// shape for an `SMAppService.daemon`-registered privileged helper.
///
/// NEVER USED except by `main.swift`'s listener wiring, which is never
/// executed as part of this spike.
final class LidHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject: LidHelperXPCService

    init(exportedObject: LidHelperXPCService) {
        self.exportedObject = exportedObject
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: LidHelperXPCProtocol.self)
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}
