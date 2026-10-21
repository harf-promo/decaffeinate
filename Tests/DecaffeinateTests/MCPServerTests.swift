import MCP
import XCTest

@testable import Decaffeinate

/// Pure tests for the MCP request→action mapping and tool catalogue — no live
/// stdio transport.
final class MCPServerTests: XCTestCase {

    func testToolListExposesTheSixTools() {
        let names = Set(MCPServer.toolList().map(\.name))
        XCTAssertEqual(
            names,
            [
                "whats_keeping_awake", "keep_awake", "release_keep_awake", "sleep_now",
                "sleep_if_idle", "clamshell_status",
            ])
    }

    func testClamshellStatusIsReadOnlyWithNoArguments() {
        // No case exists to ARM a clamshell session over MCP — read-only status
        // only, deliberately (see the doc comment on `clamshell_status`'s
        // registration).
        XCTAssertEqual(
            MCPServer.parseAction(name: "clamshell_status", arguments: nil), .clamshellStatus)
    }

    func testEveryToolHasAnObjectSchema() {
        for tool in MCPServer.toolList() {
            guard case .object(let schema) = tool.inputSchema else {
                return XCTFail("\(tool.name) input schema must be an object")
            }
            XCTAssertEqual(schema["type"]?.stringValue, "object")
        }
    }

    func testParseStatusAndSleepAndRelease() {
        XCTAssertEqual(MCPServer.parseAction(name: "whats_keeping_awake", arguments: nil), .status)
        XCTAssertEqual(MCPServer.parseAction(name: "sleep_now", arguments: nil), .sleepNow)
        XCTAssertEqual(
            MCPServer.parseAction(name: "release_keep_awake", arguments: nil), .releaseKeepAwake)
    }

    func testParseKeepAwakeReadsMinutes() {
        XCTAssertEqual(
            MCPServer.parseAction(name: "keep_awake", arguments: ["minutes": .int(30)]),
            .keepAwake(minutes: 30))
    }

    func testParseKeepAwakeWithoutMinutesIsNil() {
        XCTAssertNil(MCPServer.parseAction(name: "keep_awake", arguments: nil))
        XCTAssertNil(MCPServer.parseAction(name: "keep_awake", arguments: [:]))
    }

    func testParseSleepIfIdleDefaultsAndReadsSeconds() {
        XCTAssertEqual(
            MCPServer.parseAction(name: "sleep_if_idle", arguments: ["seconds": .int(600)]),
            .sleepIfIdle(seconds: 600))
        XCTAssertEqual(
            MCPServer.parseAction(name: "sleep_if_idle", arguments: nil),
            .sleepIfIdle(seconds: HookInstaller.defaultIdleSeconds))
    }

    func testUnknownToolIsNil() {
        XCTAssertNil(MCPServer.parseAction(name: "delete_everything", arguments: nil))
    }

    // MARK: sleep_if_idle safety rails (T4 / F4)

    func testSleepIfIdleReplyLeavesAwakeWithTheReason() {
        XCTAssertEqual(
            MCPServer.sleepIfIdleHoldMessage(
                verdict: .leaveAwake(reason: "Microphone is in use (likely a call)"),
                idleSeconds: 900, threshold: 300),
            "Not sleeping — leaving this Mac awake: Microphone is in use (likely a call)")
    }

    func testSleepIfIdleReplyForRecentActivityAndForSleep() {
        XCTAssertEqual(
            MCPServer.sleepIfIdleHoldMessage(
                verdict: .stillActive, idleSeconds: 12, threshold: 300),
            "Active 12s ago (< 300s) — leaving this Mac awake.")
        XCTAssertNil(
            MCPServer.sleepIfIdleHoldMessage(verdict: .sleep, idleSeconds: 900, threshold: 300),
            "nil means go ahead and sleep")
    }

    func testSleepIfIdleVerdictFromAMicrophoneHoldIsLeaveAwake() {
        let mic = Fixtures.assertion(
            pid: 900, process: "coreaudiod", bundle: nil, resources: ["audio-in"])
        let verdict = CLI.sleepIfIdleVerdict(
            idleSeconds: 900, threshold: 300, assertions: [mic],
            power: PowerSnapshot(onBattery: false, charge: 1.0, isCharging: false),
            thermalState: .nominal, settings: DecaffeinateSettings())
        let message = MCPServer.sleepIfIdleHoldMessage(
            verdict: verdict, idleSeconds: 900, threshold: 300)
        XCTAssertEqual(message?.hasPrefix("Not sleeping — leaving this Mac awake: "), true)
    }
}
