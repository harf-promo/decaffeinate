import XCTest

@testable import Decaffeinate

final class AttributorTests: XCTestCase {

    // Real assertion names captured from a live `--scan` this project's dev Mac.
    private let safariWebKitGPU =
        "xpcservice<com.apple.WebKit.GPU([app<application.com.apple.Safari.821279.822163(501)>"
        + ":64219])(501)>{vt hash: 0}[uuid:3F1B4822-9614-4D37-B4B4-BC0A92E5B49D]"
        + "{definition:com.apple.WebKit.GPU[standard][client]}:64225403-64219-192162:WebKit Media Playback"

    private let safariWebContent =
        "app<application.com.apple.Safari.821279.822163(501)>403-64219-192161:WebKit Media Playback"

    func testExtractsRealOwnerFromWebKitNames() {
        XCTAssertEqual(
            AssertionAttributor.bundleIDHint(inName: safariWebKitGPU), "com.apple.Safari")
        XCTAssertEqual(
            AssertionAttributor.bundleIDHint(inName: safariWebContent), "com.apple.Safari")
    }

    func testPrefersRealAppOverWebKitInfrastructure() {
        // The string contains com.apple.WebKit.GPU too — the app must win.
        XCTAssertNotEqual(
            AssertionAttributor.bundleIDHint(inName: safariWebKitGPU), "com.apple.WebKit.GPU")
    }

    func testTrimsInstanceSegments() {
        XCTAssertEqual(
            AssertionAttributor.trimToBundleID("com.apple.Safari.821279.822163"), "com.apple.Safari"
        )
        XCTAssertEqual(AssertionAttributor.trimToBundleID("us.zoom.xos"), "us.zoom.xos")
    }

    func testRejectsNonBundleIDs() {
        XCTAssertNil(AssertionAttributor.trimToBundleID("node"))  // single segment
        XCTAssertNil(AssertionAttributor.trimToBundleID("123.456"))  // starts numeric
        XCTAssertNil(AssertionAttributor.trimToBundleID("3F1B4822-9614"))  // a UUID chunk
    }

    func testNoHintWhenNoBundleIDPresent() {
        XCTAssertNil(
            AssertionAttributor.bundleIDHint(inName: "Powerd - Prevent sleep while display is on"))
        XCTAssertNil(AssertionAttributor.bundleIDHint(inName: "caffeinate command-line tool"))
    }

    func testSharedDaemonDetection() {
        XCTAssertTrue(AssertionAttributor.isSharedDaemon("coreaudiod"))
        XCTAssertTrue(AssertionAttributor.isSharedDaemon("runningboardd"))
        XCTAssertFalse(AssertionAttributor.isSharedDaemon("Safari"))
    }

    // MARK: PowerAssertion attribution surface

    func testAttributedAssertionDisplaysRealOwner() {
        let assertion = PowerAssertion(
            id: "1", pid: 403, processName: "runningboardd", bundleIdentifier: nil,
            assertionType: AssertionType.preventUserIdleSystemSleep,
            name: "WebKit Media Playback", kind: .systemSleep, createdAt: nil,
            realOwner: AssertionOwner(name: "Safari", bundleIdentifier: "com.apple.Safari")
        )
        XCTAssertEqual(assertion.displayName, "Safari")
        XCTAssertEqual(assertion.attribution, "via runningboardd")
    }

    func testUnattributedAssertionHasNoAttribution() {
        let assertion = Fixtures.assertion(process: "caffeinate", bundle: nil)
        XCTAssertNil(assertion.attribution)
        XCTAssertEqual(assertion.displayName, "caffeinate")
    }
}
