import XCTest

@testable import Decaffeinate

/// Pure tests for the stale-holder quiet-window logic — no libproc, samples fed
/// directly. Mirrors the AgentWatcher quiet-window tests but for the *inverted*
/// signal (a holder that keeps asserting while idle).
final class StaleHolderDetectorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    private func sample(_ pid: pid_t, cpu: UInt64, at seconds: TimeInterval) -> ProcessSample {
        ProcessSample(pids: [pid], cpuNanoseconds: cpu, at: at(seconds))
    }

    // A holder whose subtree CPU keeps rising is never stale, however long it holds.
    func testBusyHolderNeverStale() {
        var d = StaleHolderDetector(requiredStaleSeconds: 3)
        var cpu: UInt64 = 0
        for t in 0...10 {
            cpu &+= 2_000_000_000  // ~200% between 1 s samples → firmly busy
            let ev = d.update(
                samples: [100: sample(100, cpu: cpu, at: Double(t))], holding: [100],
                now: at(Double(t)))
            XCTAssertFalse(ev[100]!.isStale, "busy holder must never be stale (t=\(t))")
        }
    }

    // A holder that keeps asserting at a flat (0-delta) CPU crosses the window.
    func testSustainedQuietCrossesThreshold() {
        var d = StaleHolderDetector(requiredStaleSeconds: 3)
        // t=0 first sample (unknown CPU → busy, not stale).
        _ = d.update(samples: [100: sample(100, cpu: 5_000, at: 0)], holding: [100], now: at(0))
        // t=1 flat → quiet window opens; still 0 s quiet.
        let e1 = d.update(
            samples: [100: sample(100, cpu: 5_000, at: 1)], holding: [100], now: at(1))
        XCTAssertFalse(e1[100]!.isStale)
        XCTAssertEqual(e1[100]!.cpuPercent ?? -1, 0, accuracy: 0.001)
        // t=3 → 2 s quiet, still under the 3 s bar.
        let e3 = d.update(
            samples: [100: sample(100, cpu: 5_000, at: 3)], holding: [100], now: at(3))
        XCTAssertFalse(e3[100]!.isStale)
        // t=4 → 3 s quiet → stale.
        let e4 = d.update(
            samples: [100: sample(100, cpu: 5_000, at: 4)], holding: [100], now: at(4))
        XCTAssertTrue(e4[100]!.isStale)
        XCTAssertEqual(e4[100]!.quietSeconds, 3, accuracy: 0.001)
    }

    // A burst of CPU mid-window resets the quiet timer.
    func testCpuBurstResetsWindow() {
        var d = StaleHolderDetector(requiredStaleSeconds: 3)
        _ = d.update(samples: [100: sample(100, cpu: 1_000, at: 0)], holding: [100], now: at(0))
        // t=1 flat → quiet window opens; t=2 → 1 s quiet.
        _ = d.update(samples: [100: sample(100, cpu: 1_000, at: 1)], holding: [100], now: at(1))
        _ = d.update(samples: [100: sample(100, cpu: 1_000, at: 2)], holding: [100], now: at(2))
        // Burst at t=3: +2e9 ns over 1 s ≈ 200% → busy, resets.
        let burst = d.update(
            samples: [100: sample(100, cpu: 2_000_001_000, at: 3)], holding: [100], now: at(3))
        XCTAssertFalse(burst[100]!.isStale)
        XCTAssertEqual(burst[100]!.quietSeconds, 0)
        // Flat again from t=4 reopens the window; needs a fresh 3 s, so not stale
        // until t=7.
        _ = d.update(
            samples: [100: sample(100, cpu: 2_000_001_000, at: 4)], holding: [100], now: at(4))
        let e6 = d.update(
            samples: [100: sample(100, cpu: 2_000_001_000, at: 6)], holding: [100], now: at(6))
        XCTAssertFalse(e6[100]!.isStale, "window restarted after the burst")
        let e7 = d.update(
            samples: [100: sample(100, cpu: 2_000_001_000, at: 7)], holding: [100], now: at(7))
        XCTAssertTrue(e7[100]!.isStale)
    }

    // A lower cumulative reading (a proc_pidinfo read racing an exit) clamps to 0%,
    // so it reads as quiet — never a phantom burst that resets the window.
    func testCumulativeDipReadsAsQuietNotBurst() {
        var d = StaleHolderDetector(requiredStaleSeconds: 3)
        _ = d.update(samples: [100: sample(100, cpu: 9_000_000, at: 0)], holding: [100], now: at(0))
        // Dip to a lower cumulative value at t=1 → clamp to 0%, quiet opens.
        let dip = d.update(
            samples: [100: sample(100, cpu: 1_000, at: 1)], holding: [100], now: at(1))
        XCTAssertEqual(dip[100]!.cpuPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertFalse(dip[100]!.isStale)
        // Flat onward → stale at t=4 (3 s quiet), proving the dip did NOT reset.
        _ = d.update(samples: [100: sample(100, cpu: 1_000, at: 3)], holding: [100], now: at(3))
        let e4 = d.update(
            samples: [100: sample(100, cpu: 1_000, at: 4)], holding: [100], now: at(4))
        XCTAssertTrue(e4[100]!.isStale)
    }

    // Releasing then re-acquiring a hold restarts the window (state is pruned).
    func testReleasedHolderIsPrunedAndWindowResets() {
        var d = StaleHolderDetector(requiredStaleSeconds: 3)
        _ = d.update(samples: [100: sample(100, cpu: 1_000, at: 0)], holding: [100], now: at(0))
        // Quiet window opens at t=1.
        _ = d.update(samples: [100: sample(100, cpu: 1_000, at: 1)], holding: [100], now: at(1))
        // Hold released for a tick — pid not in `holding`.
        let gone = d.update(samples: [:], holding: [], now: at(2))
        XCTAssertNil(gone[100])
        // Re-acquired at t=3: first sample again (unknown CPU → busy), window restarts.
        let back = d.update(
            samples: [100: sample(100, cpu: 1_000, at: 3)], holding: [100], now: at(3))
        XCTAssertFalse(back[100]!.isStale)
        // Would have been stale at t=4 under the old window; must not be.
        let e4 = d.update(
            samples: [100: sample(100, cpu: 1_000, at: 4)], holding: [100], now: at(4))
        XCTAssertFalse(e4[100]!.isStale, "window restarted on re-acquire")
    }

    // Two holders keep independent windows: a busy one never taints a quiet one.
    func testMultipleHoldersIndependentWindows() {
        var d = StaleHolderDetector(requiredStaleSeconds: 3)
        var busyCPU: UInt64 = 0
        func tick(_ t: TimeInterval) -> [pid_t: StaleEvidence] {
            busyCPU &+= 2_000_000_000
            return d.update(
                samples: [
                    200: sample(200, cpu: busyCPU, at: t),  // busy
                    300: sample(300, cpu: 7_000, at: t),  // flat/quiet
                ], holding: [200, 300], now: at(t))
        }
        _ = tick(0)
        _ = tick(1)
        _ = tick(2)
        _ = tick(3)
        let e = tick(4)  // pid 300 has been quiet since t=1 → 3 s at t=4
        XCTAssertFalse(e[200]!.isStale, "busy holder stays non-stale")
        XCTAssertTrue(e[300]!.isStale, "quiet holder goes stale independently")
    }

    // A vanished subtree (empty sample) counts as busy, never stale.
    func testVanishedSubtreeIsNotStale() {
        var d = StaleHolderDetector(requiredStaleSeconds: 1)
        _ = d.update(
            samples: [100: ProcessSample(pids: [], cpuNanoseconds: 0, at: at(0))],
            holding: [100], now: at(0))
        let e = d.update(
            samples: [100: ProcessSample(pids: [], cpuNanoseconds: 0, at: at(5))],
            holding: [100], now: at(5))
        XCTAssertFalse(e[100]!.isStale)
    }
}
