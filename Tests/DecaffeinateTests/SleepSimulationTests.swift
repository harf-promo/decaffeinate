import XCTest

@testable import Decaffeinate

/// End-to-end sleep scenarios played through `SleepSimulator`: scripted
/// assertions, idle time, and kernel sleep/wake events in, the firewall's
/// decisions (pmset requests, history, notifications) out. No test here can
/// sleep this Mac — pmset and NSWorkspace are both simulated.
@MainActor
final class SleepSimulationTests: XCTestCase {

    /// 10-minute idle threshold, no pre-sleep HUD unless a test opts in, so the
    /// expected pmset second is exact.
    private func makeSim(
        _ configure: (inout DecaffeinateSettings) -> Void = { _ in }
    ) -> SleepSimulator {
        SleepSimulator {
            $0.idleThresholdMinutes = 10
            $0.showPreSleepWarning = false
            configure(&$0)
        }
    }

    func testEventSourceAttachesOnceAndDetachesOnShutDown() {
        let sim = makeSim(); defer { sim.tearDown() }
        XCTAssertTrue(sim.events.isStarted)
        sim.state.registerRestObservers()
        XCTAssertEqual(sim.events.startCount, 2)
        sim.naturalSleep()
        XCTAssertEqual(sim.restKinds, [.displayOff, .systemSleep], "one handler, not two")
        sim.state.shutDown()
        XCTAssertFalse(sim.events.isStarted, "shutDown stops the event stream")
    }

    func testStubbornHolderIsOverriddenAtIdleThreshold() {
        let sim = makeSim(); defer { sim.tearDown() }
        sim.hold("Chrome")
        let ran = sim.run(for: 900)
        XCTAssertEqual(ran, 600, "pmset fires on the first tick at the 10-minute idle mark")
        XCTAssertEqual(sim.pmsetRequests.count, 1)
        XCTAssertEqual(sim.pmsetRequests.first?.slept, true)
        XCTAssertTrue(sim.isAsleep)
        XCTAssertEqual(sim.forcedSleeps.count, 1)
        XCTAssertEqual(sim.restKinds, [.displayOff, .forcedSleep])
    }

    func testUserReturningBeforeThresholdPreventsSleep() {
        let sim = makeSim(); defer { sim.tearDown() }
        sim.hold("Chrome")
        sim.run(for: 590)
        sim.userInput()
        sim.run(for: 590)
        XCTAssertTrue(sim.pmsetRequests.isEmpty)
        XCTAssertFalse(sim.isAsleep)
    }

    func testWakeMeasuresSleepDurationAndLogsTimeline() {
        let sim = makeSim(); defer { sim.tearDown() }
        sim.run(for: 600)
        XCTAssertTrue(sim.isAsleep)
        sim.wake(after: 3600, userTouches: true)
        XCTAssertEqual(sim.forcedSleeps.first?.sleptSeconds, 3600)
        XCTAssertEqual(sim.restKinds, [.displayOff, .forcedSleep, .wake, .displayOn])
    }

    func testWakeWithoutInputGetsGraceBeforeResleep() throws {
        // HID idle survives sleep as wall-clock time, so a lid-open wake with no
        // keypress reads as an hour idle. The firewall must not slam the Mac
        // straight back to sleep.
        let sim = makeSim(); defer { sim.tearDown() }
        sim.run(for: 600)
        sim.wake(after: 3600)
        let wokeAt = sim.clock.date
        sim.run(for: 120)
        XCTAssertEqual(sim.pmsetRequests.count, 2)
        let resleep = try XCTUnwrap(sim.pmsetRequests.last)
        XCTAssertGreaterThanOrEqual(resleep.at.timeIntervalSince(wokeAt), 60)
    }

    func testPreventSystemSleepAbortsAndFirewallRetriesWithoutClaimingSleep() {
        let sim = makeSim(); defer { sim.tearDown() }
        sim.hold("Backup", type: AssertionType.preventSystemSleep)
        sim.run(for: 600 + 59)
        XCTAssertEqual(sim.pmsetRequests.map(\.slept), [false], "one attempt, then a cooldown")
        XCTAssertTrue(sim.forcedSleeps.isEmpty, "an aborted transition is not a sleep")
        XCTAssertNil(sim.state.lastSleepAt)
        sim.run(for: 1)
        XCTAssertEqual(sim.pmsetRequests.map(\.slept), [false, false], "retried after 60 s")
        sim.release("Backup")
        sim.run(for: 60)
        XCTAssertEqual(sim.pmsetRequests.last?.slept, true)
        XCTAssertEqual(sim.forcedSleeps.count, 1)
    }

    func testAllowedAppHoldsMacAwakeUntilItLetsGo() {
        let sim = makeSim(); defer { sim.tearDown() }
        let zoom = sim.hold("Zoom")
        sim.rules.setPolicy(.allow, for: zoom)
        sim.run(for: 1800)
        XCTAssertTrue(sim.pmsetRequests.isEmpty, "an allowed app keeps the Mac awake")
        sim.release("Zoom")
        XCTAssertEqual(sim.run(for: 10), 1, "already past threshold → sleeps on the next tick")
        XCTAssertTrue(sim.isAsleep)
    }

    func testIgnoredAppDoesNotDelaySleep() {
        let sim = makeSim(); defer { sim.tearDown() }
        let spotify = sim.hold("Spotify")
        sim.rules.setPolicy(.ignore, for: spotify)
        XCTAssertEqual(sim.run(for: 900), 600)
        XCTAssertTrue(sim.isAsleep)
    }

    func testNaturalSleepIsNotRecordedAsForced() {
        let sim = makeSim(); defer { sim.tearDown() }
        sim.run(for: 30)
        sim.naturalSleep()
        sim.wake(after: 600, userTouches: true)
        XCTAssertTrue(sim.pmsetRequests.isEmpty)
        XCTAssertTrue(sim.forcedSleeps.isEmpty)
        XCTAssertEqual(sim.restKinds, [.displayOff, .systemSleep, .wake, .displayOn])
    }

    func testPreSleepWarningDelaysAndUserInputCancels() {
        let sim = makeSim { $0.showPreSleepWarning = true }; defer { sim.tearDown() }
        sim.hold("Chrome")
        sim.run(for: 600)
        XCTAssertNotNil(sim.state.pendingIdleSleepWarning, "threshold arms the HUD first")
        XCTAssertTrue(sim.pmsetRequests.isEmpty)
        sim.userInput()
        sim.run(for: 30)
        XCTAssertNil(sim.state.pendingIdleSleepWarning, "fresh input disarms the warning")
        XCTAssertTrue(sim.pmsetRequests.isEmpty)
        // Walk away for good: threshold, then the 20 s countdown, then sleep.
        XCTAssertEqual(sim.run(for: 900), 600 - 30 + 20)
        XCTAssertTrue(sim.isAsleep)
    }

    func testForcedSleepNotificationOnlyAfterKernelConfirms() {
        let sim = makeSim { $0.notifyOnForcedSleep = true }; defer { sim.tearDown() }
        sim.hold("Backup", type: AssertionType.preventSystemSleep)
        sim.run(for: 600)
        XCTAssertTrue(sim.notifier.forcedSleeps.isEmpty, "pmset launched, but nothing slept")
        sim.release("Backup")
        sim.run(for: 60)
        XCTAssertEqual(sim.notifier.forcedSleeps.count, 1)
    }

    func testUserSleepNowThatNeverTakesIsReported() {
        let sim = makeSim(); defer { sim.tearDown() }
        sim.hold("Backup", type: AssertionType.preventSystemSleep)
        sim.run(for: 5)
        sim.state.sleepNow(requireCallConfirmation: false)
        sim.run(for: 15)
        XCTAssertEqual(sim.pmsetRequests.map(\.slept), [false])
        XCTAssertEqual(sim.notifier.sleepFailures.count, 1)
        XCTAssertTrue(sim.notifier.sleepFailures[0].contains("Backup"))
    }
}
