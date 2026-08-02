import XCTest

@testable import DecaffeinateLidHelper

/// `DisableSleepControlling`-style fake-driven coverage: every test drives
/// `LidHelperService` (an actor) with a `FakeDisableSleepController` and
/// explicit `now` values — never a live `pmset`, never real wall-clock time.
/// This is the seam the spike's hard safety constraints require: the real
/// `LiveDisableSleepController` is never constructed anywhere in this file.
final class LidHelperServiceTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    func testAcquireLeaseAssertsTheFlagAndReturnsActiveState() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        let state = await service.acquireLease(ttlSeconds: 120, now: epoch)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.expiresAt, epoch.addingTimeInterval(120))
        XCTAssertEqual(fake.calls, [true])
    }

    func testAcquireLeaseClampsAnOversizedTTLToTheMax() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        let state = await service.acquireLease(ttlSeconds: 999_999, now: epoch)

        XCTAssertEqual(state.expiresAt, epoch.addingTimeInterval(TimeInterval(LidHelperLease.maxTTLSeconds)))
    }

    func testRenewLeaseExtendsAnActiveLeaseAndReassertsTheFlag() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        _ = await service.acquireLease(ttlSeconds: 60, now: epoch)
        let renewed = await service.renewLease(ttlSeconds: 60, now: epoch.addingTimeInterval(30))

        XCTAssertTrue(renewed.isActive)
        XCTAssertEqual(renewed.expiresAt, epoch.addingTimeInterval(30 + 60))
        XCTAssertEqual(fake.calls, [true, true])
    }

    func testRenewLeaseWithNoActiveLeaseDoesNotReassertTheFlag() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        let state = await service.renewLease(ttlSeconds: 60, now: epoch)

        XCTAssertFalse(state.isActive)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    /// The dead-man switch: a late heartbeat arriving after expiry must never
    /// silently resurrect the session — the whole point of the expiry-driven
    /// clear is that a crashed/backgrounded app (or a Mac in a bag with no
    /// network) can't "catch up" past it.
    func testRenewLeaseAfterExpiryDoesNotResurrectTheSession() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        _ = await service.acquireLease(ttlSeconds: 60, now: epoch)
        let afterExpiry = epoch.addingTimeInterval(120)
        let renewed = await service.renewLease(ttlSeconds: 60, now: afterExpiry)

        XCTAssertFalse(renewed.isActive)
        // acquire -> true, then the stale renew's own expiry check -> false;
        // never a second `true` from the stale renew itself.
        XCTAssertEqual(fake.calls, [true, false])
    }

    func testCurrentStateAloneTriggersTheDeadManSwitchOnceExpired() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        _ = await service.acquireLease(ttlSeconds: 60, now: epoch)
        let state = await service.currentState(now: epoch.addingTimeInterval(61))

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(fake.calls, [true, false])
    }

    func testReleaseLeaseClearsTheFlagImmediately() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        _ = await service.acquireLease(ttlSeconds: 60, now: epoch)
        let released = await service.releaseLease(now: epoch.addingTimeInterval(1))

        XCTAssertFalse(released.isActive)
        XCTAssertEqual(fake.calls, [true, false])
    }

    func testClearOnLaunchClearsTheFlagEvenWithNoActiveLease() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        await service.clearOnLaunch()

        XCTAssertEqual(fake.calls, [false])
        let state = await service.currentState(now: epoch)
        XCTAssertFalse(state.isActive)
    }

    func testClearOnSIGTERMClearsAnActiveLease() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        _ = await service.acquireLease(ttlSeconds: 60, now: epoch)
        await service.clearOnSIGTERM()

        XCTAssertEqual(fake.calls, [true, false])
        let state = await service.currentState(now: epoch)
        XCTAssertFalse(state.isActive)
    }

    func testHelperVersionMatchesLeaseStateCurrentVersion() async {
        let fake = FakeDisableSleepController()
        let service = LidHelperService(disableSleep: fake)

        XCTAssertEqual(service.helperVersion(), LeaseState.currentHelperVersion)
    }
}
