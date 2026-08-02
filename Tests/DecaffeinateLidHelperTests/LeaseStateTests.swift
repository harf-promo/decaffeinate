import XCTest

@testable import DecaffeinateLidHelper

final class LeaseStateTests: XCTestCase {
    func testInactiveDefaultsToNoExpiryAndCurrentVersion() {
        let state = LeaseState.inactive()
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.expiresAt)
        XCTAssertEqual(state.helperVersion, LeaseState.currentHelperVersion)
    }

    /// Round-trips through JSON exactly the way `LidHelperXPCService` encodes
    /// a reply and a real (never-built) app-side client would decode it.
    func testRoundTripsThroughJSON() throws {
        let original = LeaseState(
            isActive: true,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            helperVersion: "1.0.0-spike"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LeaseState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class DisableSleepErrorTests: XCTestCase {
    func testDescriptionsAreHumanReadable() {
        XCTAssertEqual(
            DisableSleepError.launchFailed("boom").description,
            "Could not launch pmset: boom"
        )
        XCTAssertEqual(
            DisableSleepError.nonZeroExit(17).description,
            "pmset disablesleep exited with code 17"
        )
    }
}
