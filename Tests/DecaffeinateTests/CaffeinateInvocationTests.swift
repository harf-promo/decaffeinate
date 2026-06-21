import XCTest

@testable import Decaffeinate

final class CaffeinateInvocationTests: XCTestCase {
    private func parse(_ argv: [String]) -> CaffeinateInvocation {
        CaffeinateArgvParser.parse(argv)
    }

    func testBare() {
        let inv = parse(["caffeinate"])
        XCTAssertTrue(inv.effectivePreventsSystem)
        XCTAssertNil(inv.waitPID)
        XCTAssertNil(inv.timeoutSeconds)
        XCTAssertTrue(inv.trailingCommand.isEmpty)
    }

    func testWaitPIDSeparateAndAttached() {
        XCTAssertEqual(parse(["caffeinate", "-w", "8123"]).waitPID, 8123)
        XCTAssertEqual(parse(["caffeinate", "-w8123"]).waitPID, 8123)
    }

    func testTimeout() {
        XCTAssertEqual(parse(["caffeinate", "-t", "300"]).timeoutSeconds, 300)
        XCTAssertEqual(parse(["caffeinate", "-t300"]).timeoutSeconds, 300)
    }

    func testBundledFlags() {
        let inv = parse(["caffeinate", "-dimsu"])
        XCTAssertTrue(inv.preventsDisplay)
        XCTAssertTrue(inv.preventsIdleSystem)
        XCTAssertTrue(inv.preventsDisk)
        XCTAssertTrue(inv.preventsOnAC)
        XCTAssertTrue(inv.assertsUserActive)
    }

    func testFlagClusterWithValue() {
        let inv = parse(["caffeinate", "-iw", "42"])
        XCTAssertTrue(inv.preventsIdleSystem)
        XCTAssertEqual(inv.waitPID, 42)
    }

    func testTrailingCommand() {
        let inv = parse(["caffeinate", "npm", "run", "build"])
        XCTAssertEqual(inv.trailingCommand, ["npm", "run", "build"])
    }

    func testGracefulBadValues() {
        XCTAssertNil(parse(["caffeinate", "-w", "notanumber"]).waitPID)
        XCTAssertNil(parse(["caffeinate", "-w"]).waitPID)  // missing value — no crash
        XCTAssertFalse(parse(["caffeinate", "-x"]).isAnyFlagSet)  // unknown flag ignored
    }

    // MARK: Explainer

    func testExplainWaitWithAndWithoutName() {
        XCTAssertEqual(
            CaffeinateExplainer.explain(
                parse(["caffeinate", "-w", "8123"]), waitTargetName: "npm"),
            "Keeping the system awake until npm (PID 8123) finishes")
        XCTAssertEqual(
            CaffeinateExplainer.explain(parse(["caffeinate", "-w", "8123"]), waitTargetName: nil),
            "Keeping the system awake until process 8123 exits")
    }

    func testExplainTimeoutAndScopes() {
        XCTAssertEqual(
            CaffeinateExplainer.explain(parse(["caffeinate", "-t", "300"])),
            "Keeping the system awake for up to 5m")
        XCTAssertEqual(
            CaffeinateExplainer.explain(parse(["caffeinate", "-di"])),
            "Keeping the system & display awake")
        XCTAssertEqual(
            CaffeinateExplainer.explain(parse(["caffeinate", "-d"])),
            "Keeping the display awake")
        XCTAssertEqual(
            CaffeinateExplainer.explain(parse(["caffeinate"])),
            "Keeping the system awake")
    }

    func testExplainTrailingCommand() {
        XCTAssertEqual(
            CaffeinateExplainer.explain(parse(["caffeinate", "make", "all"])),
            "Keeping the system awake while make all runs")
    }
}
