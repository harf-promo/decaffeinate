import XCTest

@testable import Decaffeinate

@MainActor private final class FakeHold: KeepAwakeControlling {
    private(set) var isActive = false
    private(set) var releaseCount = 0
    func update(keepSystemAwake: Bool, keepDisplayAwake: Bool, reason: String) {
        isActive = keepSystemAwake || keepDisplayAwake
    }
    func releaseAll() {
        isActive = false
        releaseCount += 1
    }
}

/// MCP argument errors (L4), the idle floor note (L3) and the rail-release
/// signal on `keep_awake` (L5).
@MainActor
final class MCPKeepAwakeTests: XCTestCase {

    func testKeepAwakeWithoutMinutesNamesTheMissingArgument() {
        guard
            case .invalidArguments(let message) = MCPServer.parseAction(
                name: "keep_awake", arguments: nil)
        else { return XCTFail("expected .invalidArguments") }
        XCTAssertTrue(message.contains("minutes"), message)
        XCTAssertFalse(message.contains("Unknown tool"), message)
    }

    func testIdleFloorNoteOnlyWhenRaised() {
        XCTAssertEqual(MCPServer.idleFloorNote(requested: nil, used: 300), "")
        XCTAssertEqual(MCPServer.idleFloorNote(requested: 600, used: 600), "")
        let note = MCPServer.idleFloorNote(requested: 0, used: 30)
        XCTAssertTrue(note.contains("0s") && note.contains("30s"), note)
    }

    func testClampedIdleSeconds() {
        XCTAssertEqual(HookInstaller.clampedIdleSeconds(-5), HookInstaller.minimumIdleSeconds)
        XCTAssertEqual(HookInstaller.clampedIdleSeconds(0), HookInstaller.minimumIdleSeconds)
        XCTAssertEqual(HookInstaller.clampedIdleSeconds(300), 300)
    }

    func testRailReleaseIsRecordedForTheClient() async throws {
        let hold = FakeHold()
        var rail: String?
        let server = MCPServer(engine: hold, railCheck: { rail }, pollNanoseconds: 10_000_000)

        _ = server.startKeepAwake(minutes: 5)
        XCTAssertTrue(hold.isActive)
        XCTAssertNil(server.keepAwakeReleasedReason)

        rail = "battery below the floor"
        for _ in 0..<200 where hold.isActive {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(hold.isActive, "the rail must release the hold")
        XCTAssertEqual(server.keepAwakeReleasedReason, "battery below the floor")

        // A new hold clears the old reason.
        rail = nil
        _ = server.startKeepAwake(minutes: 5)
        XCTAssertNil(server.keepAwakeReleasedReason)
        XCTAssertTrue(hold.isActive)
    }

    func testRefusesToStartUnderARail() {
        let hold = FakeHold()
        let server = MCPServer(engine: hold, railCheck: { "too hot" }, pollNanoseconds: 10_000_000)
        let reply = server.startKeepAwake(minutes: 5)
        XCTAssertTrue(reply.contains("too hot"), reply)
        XCTAssertFalse(hold.isActive)
    }

    func testStatusJSONOmitsTheReasonUnlessSet() throws {
        var report = StatusReport(
            version: "1", generatedAt: "t", onBattery: false, batteryPercent: nil,
            idleSeconds: 0, thermal: "nominal", uptimeSeconds: nil, holdingSystemSleep: 0,
            blockers: [])
        XCTAssertFalse(report.jsonString().contains("keepAwakeReleasedReason"))
        report.keepAwakeReleasedReason = "thermal"
        XCTAssertTrue(report.jsonString().contains("\"keepAwakeReleasedReason\" : \"thermal\""))
    }
}
