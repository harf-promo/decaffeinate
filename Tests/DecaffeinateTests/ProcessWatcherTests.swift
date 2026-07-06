import XCTest

@testable import Decaffeinate

/// The folding rules that keep a watched subtree's CPU total honest across
/// member exits — the guard against "fork-heavy build reads as idle".
final class SubtreeCPUAccumulatorTests: XCTestCase {

    func testLiveMembersSumDirectly() {
        var acc = SubtreeCPUAccumulator()
        XCTAssertEqual(acc.fold(live: ["1-100": 5, "2-100": 7]), 12)
        XCTAssertEqual(acc.fold(live: ["1-100": 9, "2-100": 7]), 16)
    }

    func testExitedMemberKeepsItsCPUInTheTotal() {
        // The P0 scenario: a child ran hot, then exited between samples. Its CPU
        // must stay in the total so the next delta doesn't read as 0%.
        var acc = SubtreeCPUAccumulator()
        _ = acc.fold(live: ["root-1": 10, "child-2": 5_000_000_000])
        let total = acc.fold(live: ["root-1": 10])  // child gone
        XCTAssertEqual(total, 5_000_000_010, "exited child's CPU is retired, not dropped")
        // A new child appears — total keeps growing monotonically.
        XCTAssertEqual(acc.fold(live: ["root-1": 10, "child-3": 100]), 5_000_000_110)
    }

    func testTransientlyMissingMemberIsNotDoubleCounted() {
        // A proc_pidinfo read racing a fork/exit drops a still-alive member from
        // one sample. Retiring it immediately and re-adding it on reappearance
        // would double its lifetime CPU — one phantom delta big enough to reset
        // the agent quiet window every time the race recurs.
        var acc = SubtreeCPUAccumulator()
        _ = acc.fold(live: ["a-1": 1_000])
        XCTAssertEqual(acc.fold(live: [:]), 1_000, "carried, not retired, on a single miss")
        XCTAssertEqual(
            acc.fold(live: ["a-1": 1_200]), 1_200,
            "a reappearing member resumes its own series — no retirement double-count")
    }

    func testTotalNeverDecreases() {
        var acc = SubtreeCPUAccumulator()
        var previous: UInt64 = 0
        let samples: [[String: UInt64]] = [
            ["a-1": 100, "b-1": 200],
            ["a-1": 300],  // b exits
            ["a-1": 300, "c-1": 50],
            [:],  // everything exits
            ["d-9": 10],  // a new subtree member later
        ]
        for live in samples {
            let total = acc.fold(live: live)
            XCTAssertGreaterThanOrEqual(total, previous, "cumulative total must be monotonic")
            previous = total
        }
    }

    func testFailedReadDoesNotEraseAMembersHistory() {
        // proc_pidinfo can race an exit and read 0; the member's last-seen value
        // must win so its work isn't erased from the total.
        var acc = SubtreeCPUAccumulator()
        _ = acc.fold(live: ["a-1": 400])
        XCTAssertEqual(acc.fold(live: ["a-1": 0]), 400, "a lower read keeps the previous value")
        XCTAssertEqual(acc.fold(live: [:]), 400, "and retires at the previous value")
    }

    func testReusedPidIsANewMember() {
        // Same pid, different start time — a different process. Both count.
        var acc = SubtreeCPUAccumulator()
        _ = acc.fold(live: ["77-1000": 250])
        XCTAssertEqual(acc.fold(live: ["77-2000": 40]), 290)
    }
}
