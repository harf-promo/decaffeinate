import XCTest

@testable import Decaffeinate

final class AgentRegistryTests: XCTestCase {

    func testCommonWatchListMatchesLegacyNames() {
        XCTAssertEqual(
            AgentRegistry.commonWatchProcessNames,
            ["claude", "node", "python3", "xcodebuild", "cargo", "make", "swift", "docker"])
    }

    func testIdentifyByBundleID() {
        let hit = AgentRegistry.identify(
            originApp: nil, bundleID: "com.anthropic.claude", processNames: [])
        XCTAssertEqual(hit?.id, "claude-code")
        XCTAssertTrue(hit?.isAIAgent == true)
    }

    func testIdentifyByOriginAppName() {
        XCTAssertEqual(
            AgentRegistry.identify(originApp: "Cursor", bundleID: nil, processNames: [])?.id,
            "cursor")
    }

    func testIdentifyByProcessNameInChain() {
        // Claude Code's proc shows as a version string, but `claude` is in argv/chain.
        let hit = AgentRegistry.identify(
            originApp: nil, bundleID: nil, processNames: ["2.1.183", "claude", "zsh"])
        XCTAssertEqual(hit?.id, "claude-code")
    }

    func testGenericNodeIsNotAnAIAgent() {
        let hit = AgentRegistry.identify(originApp: nil, bundleID: nil, processNames: ["node"])
        XCTAssertEqual(hit?.id, "node")
        XCTAssertFalse(hit?.isAIAgent == true)
    }

    func testUnknownIsNil() {
        XCTAssertNil(
            AgentRegistry.identify(originApp: nil, bundleID: nil, processNames: ["Finder"]))
    }
}
