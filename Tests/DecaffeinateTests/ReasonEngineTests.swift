import XCTest

@testable import Decaffeinate

final class ReasonEngineTests: XCTestCase {

    private func category(_ a: PowerAssertion) -> AssertionCategory {
        ReasonEngine.categorize(a)
    }

    func testMicrophoneFromAudioInResource() {
        // The honest "is the mic in use / on a call" signal.
        let a = Fixtures.assertion(
            process: "coreaudiod", name: "com.apple.audio.AudioTap…",
            resources: ["audio-in", "6B3B7220-B1E7-4569"])
        XCTAssertEqual(category(a), .microphone)
        XCTAssertEqual(ReasonEngine.classify(a).resourceLabels, ["Microphone"])
    }

    func testAudioPlaybackFromAudioOutResource() {
        let a = Fixtures.assertion(
            process: "coreaudiod", name: "com.apple.audio.BuiltInSpeakerDevice…",
            resources: ["audio-out", "BuiltInSpeakerDevice"])
        XCTAssertEqual(category(a), .audioPlayback)
        XCTAssertEqual(ReasonEngine.classify(a).resourceLabels, ["Speaker"])
    }

    func testMediaPlaybackFromName() {
        XCTAssertEqual(category(Fixtures.assertion(name: "WebKit Media Playback")), .mediaPlayback)
        XCTAssertEqual(
            category(Fixtures.assertion(name: "com.apple.WebCore: HTMLMediaElement playback")),
            .mediaPlayback)
    }

    func testKeepAwakeToolAndAutoRelease() {
        let a = Fixtures.assertion(
            process: "caffeinate", name: "caffeinate command-line tool",
            details: "caffeinate asserting for 300 secs", autoReleaseSeconds: 210)
        XCTAssertEqual(category(a), .keepAwakeTool)
        XCTAssertEqual(ReasonEngine.classify(a).autoReleaseSeconds, 210)
    }

    func testHandoff() {
        XCTAssertEqual(category(Fixtures.assertion(process: "sharingd", name: "Handoff")), .handoff)
    }

    func testDisplayOn() {
        XCTAssertEqual(
            category(
                Fixtures.assertion(
                    process: "powerd", name: "Powerd - Prevent sleep while display is on")),
            .displayOn)
    }

    func testBackupAndUpdate() {
        XCTAssertEqual(
            category(Fixtures.assertion(process: "backupd", name: "Backup")), .backup)
        XCTAssertEqual(
            category(Fixtures.assertion(process: "softwareupdated", name: "Install macOS")),
            .softwareUpdate)
    }

    func testNetworkTransfer() {
        XCTAssertEqual(
            category(Fixtures.assertion(type: AssertionType.networkClientActive, name: "Active")),
            .networkTransfer)
    }

    func testRunningboardBackgroundFallback() {
        let a = Fixtures.assertion(name: "something opaque", viaRunningboard: true)
        XCTAssertEqual(category(a), .systemBackground)
    }

    func testUnknownUsesHumanReadableReason() {
        let a = Fixtures.assertion(
            name: "opaque", humanReadableReason: "SOME APP IS PREVENTING SLEEP.")
        XCTAssertEqual(category(a), .unknown)
        // Sentence-cased fallback explanation.
        XCTAssertEqual(ReasonEngine.classify(a).explanation, "Some app is preventing sleep.")
    }

    // MARK: Precedence (resources win over process/name keywords)

    func testMicrophoneResourceBeatsProcessKeyword() {
        let a = Fixtures.assertion(
            process: "caffeinate", name: "caffeinate command-line tool", resources: ["audio-in"])
        XCTAssertEqual(category(a), .microphone, "the mic/call signal must win over keywords")
    }

    func testAudioOutBeatsBackupKeyword() {
        let a = Fixtures.assertion(process: "backupd", name: "Backup", resources: ["audio-out"])
        XCTAssertEqual(category(a), .audioPlayback)
    }

    func testCloudBackupKeywordIsNotTimeMachine() {
        // A bare "backup" keyword must not brand every cloud-backup app as TM.
        let a = Fixtures.assertion(process: "bzbmenu", name: "Cloud backup in progress")
        XCTAssertNotEqual(category(a), .backup)
    }

    func testUnknownFallsBackToDetailsThenLabel() {
        let withDetails = Fixtures.assertion(
            name: "opaque", humanReadableReason: nil, details: "Pending background work")
        XCTAssertEqual(ReasonEngine.classify(withDetails).explanation, "Pending background work")

        let bare = Fixtures.assertion(name: "opaque", humanReadableReason: nil, details: nil)
        XCTAssertEqual(ReasonEngine.classify(bare).explanation, AssertionCategory.unknown.label)
    }

    // MARK: Sanitization of app-controlled text

    func testSanitizeRemovesControlCharsAndClamps() {
        let dirty = "Reason\u{1B}[2J\u{07}with codes " + String(repeating: "x", count: 200)
        let clean = ReasonEngine.sanitize(dirty)
        XCTAssertFalse(
            clean.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) },
            "no control / ANSI characters survive")
        XCTAssertLessThanOrEqual(clean.count, 120)
        XCTAssertTrue(clean.hasPrefix("Reason"))
    }

    func testUnknownExplanationIsSanitized() {
        let a = Fixtures.assertion(
            name: "opaque", humanReadableReason: "Playing\u{1B}[31m something.mov")
        let explanation = ReasonEngine.classify(a).explanation
        XCTAssertFalse(
            explanation.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
    }

    func testEveryCategoryHasLabelAndIcon() {
        let cats: [AssertionCategory] = [
            .microphone, .audioPlayback, .mediaPlayback, .networkTransfer, .handoff,
            .softwareUpdate, .backup, .displayOn, .location, .push, .keepAwakeTool,
            .systemBackground, .unknown,
        ]
        for c in cats {
            XCTAssertFalse(c.label.isEmpty)
            XCTAssertFalse(c.systemImage.isEmpty)
        }
    }
}
