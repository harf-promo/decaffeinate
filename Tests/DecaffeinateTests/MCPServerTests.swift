import MCP
import XCTest

@testable import Decaffeinate

/// Pure tests for the MCP request→action mapping and tool catalogue — no live
/// stdio transport.
final class MCPServerTests: XCTestCase {

    func testToolListExposesTheFiveTools() {
        let names = Set(MCPServer.toolList().map(\.name))
        XCTAssertEqual(
            names,
            [
                "whats_keeping_awake", "keep_awake", "release_keep_awake", "sleep_now",
                "sleep_if_idle",
            ])
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
}
