import XCTest

@testable import DecaffeinateLidHelper

final class ClientRequirementTests: XCTestCase {
    func testBuildsRequirementForValidTeamID() {
        XCTAssertEqual(
            ClientRequirement.requirementString(teamID: "ABCDE12345"),
            "anchor apple generic and identifier \"com.harfpromo.Decaffeinate\" and certificate leaf[subject.OU] = \"ABCDE12345\""
        )
    }

    func testFailsClosedWithoutOrWithMalformedTeamID() {
        XCTAssertNil(ClientRequirement.requirementString(teamID: nil))
        XCTAssertNil(ClientRequirement.requirementString(teamID: ""))
        XCTAssertNil(ClientRequirement.requirementString(teamID: "abcde12345"))
        XCTAssertNil(ClientRequirement.requirementString(teamID: "ABCDE1234\" or true"))
    }

    func testRejectsInjectedBundleIdentifier() {
        XCTAssertNil(
            ClientRequirement.requirementString(
                teamID: "ABCDE12345", bundleIdentifier: "x\" or \"a"))
    }

    func testListenerRejectsEveryClientWithoutRequirement() {
        let service = LidHelperService(disableSleep: FakeDisableSleepController())
        let delegate = LidHelperListenerDelegate(
            exportedObject: LidHelperXPCService(service: service), clientRequirement: nil)
        let conn = NSXPCConnection(machServiceName: "invalid.test.service")
        XCTAssertFalse(
            delegate.listener(NSXPCListener.anonymous(), shouldAcceptNewConnection: conn))
    }
}
