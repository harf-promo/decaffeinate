import XCTest

@testable import Decaffeinate

final class RestDigestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ kind: RestEvent.Kind, minsAgo: Double) -> RestEvent {
        RestEvent(date: now.addingTimeInterval(-minsAgo * 60), kind: kind)
    }

    func testSummarizesSleepsAndWakes() {
        let events = [
            event(.wake, minsAgo: 30),
            event(.systemSleep, minsAgo: 120),
            event(.wake, minsAgo: 200),
            event(.forcedSleep, minsAgo: 240),
        ]
        let summary = RestDigest.summary(rest: events, now: now)
        let text = try! XCTUnwrap(summary)
        XCTAssertTrue(text.contains("Last slept"), text)
        XCTAssertTrue(text.contains("woken 2 times"), text)
        XCTAssertTrue(text.contains("Decaffeinate stepped in once"), text)
    }

    func testNilWhenNothingNoteworthy() {
        // Only display-off events → not worth a line.
        let events = [event(.displayOff, minsAgo: 10), event(.displayOn, minsAgo: 5)]
        XCTAssertNil(RestDigest.summary(rest: events, now: now))
    }

    func testIgnoresEventsOutsideTheWindow() {
        let old = [event(.systemSleep, minsAgo: 60 * 20)]  // 20h ago, outside 12h
        XCTAssertNil(RestDigest.summary(rest: old, now: now, window: 12 * 3600))
    }

    func testSingularWakePhrasing() {
        let events = [event(.wake, minsAgo: 10), event(.systemSleep, minsAgo: 30)]
        let text = try! XCTUnwrap(RestDigest.summary(rest: events, now: now))
        XCTAssertTrue(text.contains("woken once"), text)
    }
}
