import XCTest

@testable import Decaffeinate

final class ClamshellAdvisorTests: XCTestCase {
    private let acPower = PowerSnapshot(onBattery: false, charge: nil, isCharging: false)
    private let batteryPower = PowerSnapshot(onBattery: true, charge: 0.8, isCharging: false)
    private let noLid = LidSnapshot(isPresent: false, isClosed: false)
    private let lidOpen = LidSnapshot(isPresent: true, isClosed: false)
    private let lidClosed = LidSnapshot(isPresent: true, isClosed: true)
    private let externalDisplay = DisplayTopology(externalDisplayCount: 1, builtinDisplayActive: false)
    private let noExternalDisplay = DisplayTopology(externalDisplayCount: 0, builtinDisplayActive: true)

    // MARK: notApplicable — no lid (desktop Mac)

    func testDesktopMacIsNotApplicable() {
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: noLid, displays: externalDisplay, power: acPower, input: .detected),
            .notApplicable)
    }

    func testNoLidStaysNotApplicableEvenWithEverythingElseReady() {
        // A desktop with an external display + AC + keyboard/mouse (the
        // ordinary case) still reports notApplicable — clamshell mode is
        // specifically about *lid* laptops, not "has all the peripherals".
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: noLid, displays: externalDisplay, power: acPower, input: .inconclusive),
            .notApplicable)
    }

    // MARK: ready — lid present, every requirement met

    func testLidPresentAllReady() {
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidOpen, displays: externalDisplay, power: acPower, input: .detected),
            .ready)
    }

    func testLidClosedAllReady() {
        // Readiness doesn't depend on whether the lid is *currently* closed —
        // the panel is pre-flight guidance shown before the user closes it.
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidClosed, displays: externalDisplay, power: acPower, input: .detected),
            .ready)
    }

    func testInconclusiveInputStillCountsAsReady() {
        // Best-effort: an inconclusive probe is not evidence of *absence* —
        // asserting "missing" here would be false-confident in the other
        // direction from a false "detected".
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidOpen, displays: externalDisplay, power: acPower, input: .inconclusive),
            .ready)
    }

    // MARK: missing — each single requirement

    func testMissingPowerOnly() {
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidOpen, displays: externalDisplay, power: batteryPower, input: .detected),
            .missing(unmet: [.power]))
    }

    func testMissingExternalDisplayOnly() {
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidOpen, displays: noExternalDisplay, power: acPower, input: .detected),
            .missing(unmet: [.externalDisplay]))
    }

    func testMissingExternalInputOnly() {
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidOpen, displays: externalDisplay, power: acPower, input: .notDetected),
            .missing(unmet: [.externalInput]))
    }

    // MARK: missing — everything

    func testAllMissing() {
        XCTAssertEqual(
            ClamshellAdvisor.classify(
                lid: lidOpen, displays: noExternalDisplay, power: batteryPower, input: .notDetected),
            .missing(unmet: [.power, .externalDisplay, .externalInput]))
    }

    // MARK: ClamshellRequirement labels — every case has a plain-language string

    func testEveryRequirementHasALabel() {
        for requirement in ClamshellRequirement.allCases {
            XCTAssertFalse(requirement.label.isEmpty)
        }
    }

    // MARK: ClamshellStatusReport — the CLI/MCP JSON shape

    func testStatusReportShapeForEachState() {
        XCTAssertEqual(
            ClamshellStatusReport.from(readiness: .notApplicable),
            ClamshellStatusReport(state: "notApplicable", missing: []))
        XCTAssertEqual(
            ClamshellStatusReport.from(readiness: .ready),
            ClamshellStatusReport(state: "ready", missing: []))
        XCTAssertEqual(
            ClamshellStatusReport.from(readiness: .missing(unmet: [.power])),
            ClamshellStatusReport(state: "missing", missing: ["power"]))
    }

    func testStatusReportJSONRoundTrips() {
        let report = ClamshellStatusReport.from(
            readiness: .missing(unmet: [.power, .externalDisplay]))
        let json = report.jsonString()
        let decoded = try! JSONDecoder().decode(ClamshellStatusReport.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, report)
    }
}
