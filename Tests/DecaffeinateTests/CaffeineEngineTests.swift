import XCTest

@testable import Decaffeinate

/// The keep-awake reconcile state machine — the decision layer between "what
/// the tick wants" and the IOKit create/release calls.
final class CaffeineEngineTests: XCTestCase {

    func testReconcileActionTable() {
        XCTAssertEqual(
            CaffeineEngine.reconcileAction(hold: true, currentlyHolding: false), .create)
        XCTAssertEqual(
            CaffeineEngine.reconcileAction(hold: false, currentlyHolding: true), .release)
        XCTAssertEqual(
            CaffeineEngine.reconcileAction(hold: true, currentlyHolding: true), .keep,
            "an existing hold is never re-created")
        XCTAssertEqual(
            CaffeineEngine.reconcileAction(hold: false, currentlyHolding: false), .keep,
            "nothing to release when nothing is held")
    }

    @MainActor
    func testUpdateIsIdempotentAndReleaseAllDropsBoth() {
        // Runs against the real engine: IOPMAssertionCreateWithName is a public,
        // unprivileged API, and releaseAll() guarantees no assertion outlives
        // the test. This is the create/hold/release lifecycle the fakes can't cover.
        let engine = CaffeineEngine()
        defer { engine.releaseAll() }

        engine.update(keepSystemAwake: true, keepDisplayAwake: true, reason: "decaf unit test")
        XCTAssertTrue(engine.holdingSystem)
        XCTAssertTrue(engine.holdingDisplay)
        XCTAssertTrue(engine.isActive)

        // Idempotent: describing the same desired state changes nothing.
        engine.update(keepSystemAwake: true, keepDisplayAwake: true, reason: "decaf unit test")
        XCTAssertTrue(engine.holdingSystem)

        engine.update(keepSystemAwake: true, keepDisplayAwake: false, reason: "decaf unit test")
        XCTAssertTrue(engine.holdingSystem)
        XCTAssertFalse(engine.holdingDisplay)

        engine.releaseAll()
        XCTAssertFalse(engine.holdingSystem)
        XCTAssertFalse(engine.holdingDisplay)
        XCTAssertFalse(engine.isActive)
    }
}
