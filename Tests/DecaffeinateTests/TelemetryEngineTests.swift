import XCTest

@testable import Decaffeinate

/// `TelemetryEngine.scan()` hits real IOKit, so it can't be unit-tested directly.
/// The row-identity logic is extracted into the pure `stableID(...)` helper, which
/// these tests pin: the same live assertion must produce the same id across scans,
/// independent of global scan order, and every assertion within a pid must be unique.
final class TelemetryEngineTests: XCTestCase {

    private let created = Date(timeIntervalSince1970: 1_700_000_000)

    func testStableIDPrefersIOKitAssertionID() {
        let id = TelemetryEngine.stableID(
            pid: 42, assertionID: 7, type: "PreventUserIdleSystemSleep",
            createdAt: created, indexWithinPID: 0)
        XCTAssertEqual(id, "42-7-PreventUserIdleSystemSleep")
    }

    func testStableIDIsDeterministicAcrossScans() {
        // Two scans of the same live assertion (no IOKit id) → identical id.
        func make() -> String {
            TelemetryEngine.stableID(
                pid: 99, assertionID: nil, type: "PreventUserIdleDisplaySleep",
                createdAt: created, indexWithinPID: 2)
        }
        XCTAssertEqual(make(), make())
    }

    func testStableIDIndependentOfGlobalScanOrder() {
        // The old code mixed `result.count` (global append order) into the id, so the
        // same hold churned when the surrounding set reordered. The helper takes no
        // such parameter — same inputs always yield the same id.
        let a = TelemetryEngine.stableID(
            pid: 7, assertionID: nil, type: "T", createdAt: created, indexWithinPID: 0)
        let b = TelemetryEngine.stableID(
            pid: 7, assertionID: nil, type: "T", createdAt: created, indexWithinPID: 0)
        XCTAssertEqual(a, b)
    }

    func testStableIDUniquePerAssertionWithinPID() {
        // Two assertions from the same pid must get distinct ids (duplicate ForEach
        // ids trigger SwiftUI runtime warnings and glitches).
        let first = TelemetryEngine.stableID(
            pid: 5, assertionID: nil, type: "T", createdAt: created, indexWithinPID: 0)
        let second = TelemetryEngine.stableID(
            pid: 5, assertionID: nil, type: "T", createdAt: created, indexWithinPID: 1)
        XCTAssertNotEqual(first, second)
    }

    func testStableIDHandlesMissingCreationDate() {
        // A hold with no start time is still deterministic and unique per index.
        let a = TelemetryEngine.stableID(
            pid: 5, assertionID: nil, type: "T", createdAt: nil, indexWithinPID: 0)
        let b = TelemetryEngine.stableID(
            pid: 5, assertionID: nil, type: "T", createdAt: nil, indexWithinPID: 0)
        let c = TelemetryEngine.stableID(
            pid: 5, assertionID: nil, type: "T", createdAt: nil, indexWithinPID: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
