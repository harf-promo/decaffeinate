import XCTest

@testable import Decaffeinate

@MainActor private final class FakeSampler: ProcessSampling {
    struct Step {
        let pids: Set<pid_t>
        let cpuNanoseconds: UInt64
    }
    var steps: [Step] = []
    func sample(_ target: WatchTarget, now: Date) -> ProcessSample {
        let step = steps.isEmpty ? Step(pids: [], cpuNanoseconds: 0) : steps.removeFirst()
        return ProcessSample(pids: step.pids, cpuNanoseconds: step.cpuNanoseconds, at: now)
    }
}

@MainActor
final class AgentWatcherTests: XCTestCase {

    private let pidSet: Set<pid_t> = [100]
    private var t = Date(timeIntervalSince1970: 1_000_000)

    private func advance(_ seconds: TimeInterval) -> Date {
        t += seconds
        return t
    }

    func testWaitingWhenProcessNeverRan() {
        let sampler = FakeSampler()
        sampler.steps = [.init(pids: [], cpuNanoseconds: 0), .init(pids: [], cpuNanoseconds: 0)]
        let watcher = AgentWatcher(sampler: sampler)
        watcher.setTarget(.processName("ghost"))

        watcher.tick(now: advance(1), systemBlockingPIDs: [])
        watcher.tick(now: advance(1), systemBlockingPIDs: [])
        XCTAssertFalse(watcher.hasCompleted)
        XCTAssertEqual(watcher.status, .waiting(label: "ghost"))
    }

    func testCompletesWhenProcessExitsAfterRunning() {
        let sampler = FakeSampler()
        sampler.steps = [
            .init(pids: pidSet, cpuNanoseconds: 0),
            .init(pids: pidSet, cpuNanoseconds: 1_000_000_000),
            .init(pids: [], cpuNanoseconds: 0),  // exited
        ]
        let watcher = AgentWatcher(sampler: sampler)
        watcher.setTarget(.processName("node"))

        watcher.tick(now: advance(1), systemBlockingPIDs: [])
        watcher.tick(now: advance(1), systemBlockingPIDs: [])
        XCTAssertFalse(watcher.hasCompleted)
        watcher.tick(now: advance(1), systemBlockingPIDs: [])
        XCTAssertTrue(watcher.hasCompleted)
    }

    func testCompletesAfterSustainedQuiet() {
        let sampler = FakeSampler()
        // First sample (unknown CPU = busy), then a long run of zero-delta CPU.
        sampler.steps = (0..<8).map { _ in FakeSampler.Step(pids: pidSet, cpuNanoseconds: 0) }
        let watcher = AgentWatcher(sampler: sampler)
        watcher.requiredQuietSeconds = 3
        watcher.setTarget(.processName("node"))

        for _ in 0..<3 {
            watcher.tick(now: advance(1), systemBlockingPIDs: [])
        }
        XCTAssertFalse(watcher.hasCompleted, "should still be within the quiet window")

        for _ in 0..<3 {
            watcher.tick(now: advance(1), systemBlockingPIDs: [])
        }
        XCTAssertTrue(watcher.hasCompleted, "sustained quiet => finished")
    }

    func testHeldAssertionPreventsCompletion() {
        let sampler = FakeSampler()
        sampler.steps = (0..<8).map { _ in FakeSampler.Step(pids: pidSet, cpuNanoseconds: 0) }
        let watcher = AgentWatcher(sampler: sampler)
        watcher.requiredQuietSeconds = 3
        watcher.setTarget(.processName("node"))

        // CPU is quiet, but the subtree still holds a system-sleep assertion.
        for _ in 0..<8 {
            watcher.tick(now: advance(1), systemBlockingPIDs: pidSet)
        }
        XCTAssertFalse(watcher.hasCompleted, "still working (holds an assertion)")
    }

    func testCpuBurstResetsQuietWindow() {
        let sampler = FakeSampler()
        // quiet, quiet, BURST (1s of CPU), then quiet again.
        sampler.steps = [
            .init(pids: pidSet, cpuNanoseconds: 0),  // t1 first
            .init(pids: pidSet, cpuNanoseconds: 0),  // t2 quiet (window opens)
            .init(pids: pidSet, cpuNanoseconds: 0),  // t3 quiet
            .init(pids: pidSet, cpuNanoseconds: 1_000_000_000),  // t4 burst (100%/s) → reset
            .init(pids: pidSet, cpuNanoseconds: 1_000_000_000),  // t5 quiet (window reopens)
            .init(pids: pidSet, cpuNanoseconds: 1_000_000_000),  // t6 quiet
        ]
        let watcher = AgentWatcher(sampler: sampler)
        watcher.requiredQuietSeconds = 3
        watcher.setTarget(.processName("node"))

        for _ in 0..<6 {
            watcher.tick(now: advance(1), systemBlockingPIDs: [])
        }
        // After the burst at t4, only 2s of quiet have elapsed (t5,t6) < 3s.
        XCTAssertFalse(watcher.hasCompleted)
    }

    func testClearingTargetGoesIdle() {
        let sampler = FakeSampler()
        let watcher = AgentWatcher(sampler: sampler)
        watcher.setTarget(.processName("node"))
        XCTAssertTrue(watcher.isActive)
        watcher.setTarget(nil)
        XCTAssertEqual(watcher.status, .idle)
        XCTAssertFalse(watcher.isActive)
    }
}
