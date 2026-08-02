import Foundation

// Phase B spike only — see docs/PHASE-B-SPIKE.md.
//
// MARK: - Entry point — NEVER EXECUTED as part of this spike.
//
// This file wires the real, privileged mechanism (`LiveDisableSleepController`)
// into a live Mach-service XPC listener. Per this spike's HARD SAFETY
// CONSTRAINTS:
//   - this binary is never launched — not by launchd (the embedded
//     `Resources/com.harfpromo.Decaffeinate.LidHelper.plist` is a static
//     resource, not wired into any build step or `SMAppService.daemon(...)`
//     call), not by any test, not manually;
//   - `LiveDisableSleepController.setDisableSleep` is therefore never invoked
//     for real anywhere in this repository.
// It exists only so `DecaffeinateLidHelper` is a structurally complete,
// compiling executable target — see docs/PHASE-B-SPIKE.md for exactly what
// was and wasn't verified.

let service = LidHelperService(disableSleep: LiveDisableSleepController())

// The reboot antidote: a fresh launchd-started process always begins by
// clearing any flag a prior, uncleanly-terminated run might have left set.
Task {
    await service.clearOnLaunch()
}

// SIGTERM (a normal `launchctl stop` / shutdown request) must clear the flag
// before the process actually exits — never stand the flag on a clean stop.
// Ignore the default disposition first so the DispatchSource sees the signal
// instead of the process being torn down before it can clean up.
signal(SIGTERM, SIG_IGN)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    Task {
        await service.clearOnSIGTERM()
        exit(0)
    }
}
sigtermSource.resume()

let xpcService = LidHelperXPCService(service: service)
let listenerDelegate = LidHelperListenerDelegate(exportedObject: xpcService)

// Matches the `MachServices` key in
// Resources/com.harfpromo.Decaffeinate.LidHelper.plist.
let listener = NSXPCListener(machServiceName: "com.harfpromo.Decaffeinate.lidhelper")
listener.delegate = listenerDelegate
listener.resume()

RunLoop.main.run()
