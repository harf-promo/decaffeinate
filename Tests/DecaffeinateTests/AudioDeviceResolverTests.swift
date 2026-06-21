import XCTest

@testable import Decaffeinate

@MainActor
final class AudioDeviceResolverTests: XCTestCase {

    // MARK: deviceTokens (ReasonEngine)

    func testDeviceTokensSplitsOutClassTokens() {
        XCTAssertEqual(
            ReasonEngine.deviceTokens(["audio-out", "BuiltInSpeakerDevice"]),
            ["BuiltInSpeakerDevice"])
        XCTAssertEqual(ReasonEngine.deviceTokens(["audio-in", "network"]), [])
        XCTAssertEqual(ReasonEngine.deviceTokens(["audio-in", "ABC-UID"]), ["ABC-UID"])
        XCTAssertEqual(ReasonEngine.deviceTokens([]), [])
    }

    // MARK: Pure prettify

    func testPrettifyBuiltIn() {
        XCTAssertEqual(
            AudioDeviceResolver.prettifyBuiltIn("BuiltInSpeakerDevice"), "Built-in Speakers")
        XCTAssertEqual(
            AudioDeviceResolver.prettifyBuiltIn("BuiltInMicrophoneDevice"), "Built-in Microphone")
        XCTAssertNil(AudioDeviceResolver.prettifyBuiltIn("SomethingElse"))
    }

    func testLooksLikeUUIDAndPrettifyUnknown() {
        XCTAssertTrue(AudioDeviceResolver.looksLikeUUID(UUID().uuidString))
        XCTAssertTrue(AudioDeviceResolver.looksLikeUUID("6B3B7220B1E74569ABCD"))
        XCTAssertFalse(AudioDeviceResolver.looksLikeUUID("AirPods Pro"))
        XCTAssertEqual(AudioDeviceResolver.prettifyUnknown("AirPods Pro"), "AirPods Pro")
        XCTAssertNil(AudioDeviceResolver.prettifyUnknown(UUID().uuidString))
    }

    // MARK: Resolver (seam-injected enumeration)

    func testResolverMatchesByUIDAndName() {
        let resolver = AudioDeviceResolver(enumerate: {
            [AudioDeviceInfo(uid: "AABB", name: "AirPods Pro", hasInput: true, hasOutput: true)]
        })
        // UID match (case-insensitive), name match, then an unknown UUID → nil.
        XCTAssertEqual(resolver.friendlyName(forToken: "aabb"), "AirPods Pro")
        XCTAssertEqual(resolver.friendlyName(forToken: "AirPods Pro"), "AirPods Pro")
        XCTAssertNil(resolver.friendlyName(forToken: UUID().uuidString))
    }

    func testBuiltInResolvesWithoutEnumerating() {
        var calls = 0
        let resolver = AudioDeviceResolver(enumerate: {
            calls += 1
            return []
        })
        XCTAssertEqual(resolver.friendlyName(forToken: "BuiltInSpeakerDevice"), "Built-in Speakers")
        XCTAssertEqual(calls, 0, "built-in tokens prettify without a CoreAudio call")
    }

    func testEnumerationFailureDegrades() {
        let resolver = AudioDeviceResolver(enumerate: { [] })
        // No devices + a UUID token → nil (no crash). A name-like token would be
        // returned as-is; a bare UUID is never surfaced raw.
        XCTAssertNil(resolver.friendlyName(forToken: UUID().uuidString))
    }
}
