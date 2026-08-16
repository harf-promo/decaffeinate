import XCTest

@testable import DecaffeinateLidHelper

/// Pure bookkeeping — no actor, no XPC, no subprocess. Mirrors
/// `HoldLifetimeTests`' plain-value-type test shape.
final class LidHelperLeaseTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    func testAcquireSetsExpiryFromNowPlusTTL() {
        var lease = LidHelperLease()
        lease.acquire(ttlSeconds: 60, now: epoch)
        XCTAssertTrue(lease.isActive)
        XCTAssertEqual(lease.expiresAt, epoch.addingTimeInterval(60))
    }

    func testClampCapsAtEightHours() {
        XCTAssertEqual(LidHelperLease.clamp(ttlSeconds: 999_999), LidHelperLease.maxTTLSeconds)
        XCTAssertEqual(LidHelperLease.maxTTLSeconds, 8 * 60 * 60)
    }

    func testClampFloorsNegativeRequestsAtZero() {
        XCTAssertEqual(LidHelperLease.clamp(ttlSeconds: -30), 0)
    }

    func testAcquireHonorsTheClampInsideExpiry() {
        var lease = LidHelperLease()
        lease.acquire(ttlSeconds: 999_999, now: epoch)
        XCTAssertEqual(
            lease.expiresAt, epoch.addingTimeInterval(TimeInterval(LidHelperLease.maxTTLSeconds)))
    }

    func testRenewReplacesTheExpiry() {
        var lease = LidHelperLease()
        lease.acquire(ttlSeconds: 60, now: epoch)
        lease.renew(ttlSeconds: 120, now: epoch.addingTimeInterval(30))
        XCTAssertEqual(lease.expiresAt, epoch.addingTimeInterval(30 + 120))
    }

    func testReleaseClearsTheLease() {
        var lease = LidHelperLease()
        lease.acquire(ttlSeconds: 60, now: epoch)
        lease.release()
        XCTAssertFalse(lease.isActive)
        XCTAssertNil(lease.expiresAt)
    }

    func testIsExpiredIsFalseBeforeExpiryTrueAtOrAfter() {
        var lease = LidHelperLease()
        lease.acquire(ttlSeconds: 60, now: epoch)
        XCTAssertFalse(lease.isExpired(now: epoch.addingTimeInterval(59)))
        XCTAssertTrue(lease.isExpired(now: epoch.addingTimeInterval(60)))
        XCTAssertTrue(lease.isExpired(now: epoch.addingTimeInterval(61)))
    }

    func testIsExpiredIsFalseForAnUnacquiredLease() {
        let lease = LidHelperLease()
        XCTAssertFalse(lease.isExpired(now: epoch))
    }
}
