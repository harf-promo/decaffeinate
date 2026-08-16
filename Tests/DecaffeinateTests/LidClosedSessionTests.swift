import XCTest

@testable import Decaffeinate

/// Phase B spike only (`docs/PHASE-B-SPIKE.md`) — pure state-machine tests,
/// no XPC, no `LidHelperClient`, mirroring `HoldLifetimeTests`'/
/// `CaffeineEngineTests`' plain-transition-table style.
final class LidClosedSessionTests: XCTestCase {
    private let expiry = Date(timeIntervalSince1970: 1_700_000_000)

    func testArmedConfirmedByHelperBecomesActive() {
        let state = LidClosedSession.transition(
            .armed(ttlSeconds: 120), on: .helperConfirmed(expiresAt: expiry))
        XCTAssertEqual(state, .active(expiresAt: expiry))
        XCTAssertTrue(state.isActive)
    }

    func testArmedUnreachableHelperEndsWithHelperUnreachable() {
        let state = LidClosedSession.transition(.armed(ttlSeconds: 120), on: .helperUnreachable)
        XCTAssertEqual(state, .ending(reason: .helperUnreachable))
    }

    func testActiveHeartbeatRenewedStaysActiveWithNewExpiry() {
        let laterExpiry = expiry.addingTimeInterval(30)
        let state = LidClosedSession.transition(
            .active(expiresAt: expiry), on: .heartbeatRenewed(expiresAt: laterExpiry))
        XCTAssertEqual(state, .active(expiresAt: laterExpiry))
    }

    func testActiveEndsOnEveryTerminalEventWithTheMatchingReason() {
        let cases: [(LidClosedSession.Event, LidClosedEndReason)] = [
            (.userReleased, .userReleased),
            (.leaseExpired, .leaseExpired),
            (.lidReopened, .lidReopened),
            (.batteryFloorBreached, .batteryFloorBreached),
            (.thermalRail, .thermalRail),
            (.helperUnreachable, .helperUnreachable),
        ]
        for (event, reason) in cases {
            let state = LidClosedSession.transition(.active(expiresAt: expiry), on: event)
            XCTAssertEqual(
                state, .ending(reason: reason), "event \(event) should end with \(reason)")
        }
    }

    func testEndingIsTerminalAndIgnoresFurtherEvents() {
        let ended = LidClosedSession.ending(reason: .userReleased)
        XCTAssertEqual(
            LidClosedSession.transition(ended, on: .helperConfirmed(expiresAt: expiry)), ended)
        XCTAssertEqual(LidClosedSession.transition(ended, on: .leaseExpired), ended)
    }

    func testArmedIgnoresActiveOnlyEvents() {
        let armed = LidClosedSession.armed(ttlSeconds: 60)
        XCTAssertEqual(LidClosedSession.transition(armed, on: .leaseExpired), armed)
        XCTAssertEqual(LidClosedSession.transition(armed, on: .lidReopened), armed)
    }

    func testIsActiveOnlyTrueForActiveCase() {
        XCTAssertFalse(LidClosedSession.armed(ttlSeconds: 60).isActive)
        XCTAssertTrue(LidClosedSession.active(expiresAt: expiry).isActive)
        XCTAssertFalse(LidClosedSession.ending(reason: .leaseExpired).isActive)
    }
}
