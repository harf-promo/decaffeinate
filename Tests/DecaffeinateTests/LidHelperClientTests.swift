import XCTest

@testable import Decaffeinate

/// Phase B spike only (`docs/PHASE-B-SPIKE.md`). `LidHelperClient` itself —
/// the real, XPC-calling implementation — is never constructed anywhere in
/// this file (or anywhere else in the test suite): it isn't wired into the
/// shipped app, and connecting to a real Mach service isn't something a unit
/// test should ever do. What's tested instead:
///   1. `LidHelperReply`'s JSON round-trip — the exact wire shape
///      `LidHelperClient.decode(_:)` and `LidHelperXPCService.encode(_:)`
///      (in `DecaffeinateLidHelper`, a separate module) independently agree
///      on.
///   2. That `LidClosedControlling` is a genuine protocol seam — a fake
///      conforms to it, mirroring `Core/SleepController.swift`'s
///      protocol + real + fake shape on the app side of this mechanism too.
final class LidHelperReplyTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let original = LidHelperReply(
            isActive: true,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            helperVersion: "1.0.0-spike"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LidHelperReply.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testInactiveDefaultsToNoExpiry() {
        let reply = LidHelperReply.inactive(helperVersion: "1.0.0-spike")
        XCTAssertFalse(reply.isActive)
        XCTAssertNil(reply.expiresAt)
        XCTAssertEqual(reply.helperVersion, "1.0.0-spike")
    }
}

/// A fake conforming to `LidClosedControlling` — proof the seam is usable
/// without ever touching XPC, the same shape every other engine seam in
/// `Core/Protocols.swift` gets in `Tests/DecaffeinateTests/TestSupport.swift`.
@MainActor
private final class FakeLidClosedController: LidClosedControlling {
    var acquireReply = LidHelperReply.inactive()
    var renewReply = LidHelperReply.inactive()
    var releaseReply = LidHelperReply.inactive()
    var stateReply = LidHelperReply.inactive()
    var versionReply: String? = "1.0.0-spike"

    private(set) var acquireCallCount = 0
    private(set) var renewCallCount = 0
    private(set) var releaseCallCount = 0

    func acquireLease(ttlSeconds: Int) async -> LidHelperReply {
        acquireCallCount += 1
        return acquireReply
    }

    func renewLease(ttlSeconds: Int) async -> LidHelperReply {
        renewCallCount += 1
        return renewReply
    }

    func releaseLease() async -> LidHelperReply {
        releaseCallCount += 1
        return releaseReply
    }

    func currentState() async -> LidHelperReply {
        stateReply
    }

    func helperVersion() async -> String? {
        versionReply
    }
}

final class LidClosedControllingSeamTests: XCTestCase {
    @MainActor
    func testFakeSatisfiesTheProtocolAndRecordsCalls() async {
        let fake = FakeLidClosedController()
        fake.acquireReply = LidHelperReply(isActive: true, expiresAt: nil, helperVersion: "1.0.0-spike")

        let controller: any LidClosedControlling = fake
        let reply = await controller.acquireLease(ttlSeconds: 60)

        XCTAssertTrue(reply.isActive)
        XCTAssertEqual(fake.acquireCallCount, 1)
        XCTAssertEqual(fake.renewCallCount, 0)
    }

    @MainActor
    func testFakeHelperVersionCanReportNilForAnUnreachableHelper() async {
        let fake = FakeLidClosedController()
        fake.versionReply = nil

        let controller: any LidClosedControlling = fake
        let version = await controller.helperVersion()

        XCTAssertNil(version)
    }
}
